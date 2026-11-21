import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import { randomBytes, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { deriveKey, newSalt, normalizeRecoveryCode, seal, sealValue, type CryptoMeta } from '../../../diet/src/crypto.ts';
import type { AccountConfig, ClientConfig, RuntimeConfig } from '../../src/config/types.ts';
import type { Scope } from '../../src/auth/scopes.ts';
import { RateLimiter } from '../../src/auth/rateLimit.ts';
import { ServiceRegistry } from '../../src/services/account.ts';
import { silentLogger } from '../../src/services/logger.ts';
import type { ToolContext } from '../../src/tools/registry.ts';
import { findTool } from '../../src/tools/index.ts';
import { runTool } from '../../src/tools/registry.ts';
import { nowStamp, todayKey } from '../../src/utils/dates.ts';
import { monthStart } from '../../src/services/financeEngine.ts';

const CHECK_TOKEN = Buffer.from('myos.vault.check.v1');
const ITERATIONS = 1000;

export interface SeedUser {
  username: string;
  password: string;
  passphrase: string;
  raw: Record<string, unknown>;
}

interface FakeState {
  seed: SeedUser;
  cells: Record<string, unknown>;
  cookie: string | null;
}

export interface Harness {
  baseUrl: string;
  accounts: Record<'a' | 'b', SeedUser>;
  meta: CryptoMeta;
  deletedEventMedia: string[];
  deletedBodyPhotos: string[];
  close(): Promise<void>;
  ctxFor(which: 'a' | 'b', scopes?: Scope[], opts?: { rateLimit?: number }): ToolContext;
  call(ctx: ToolContext, name: string, args?: Record<string, unknown>): ReturnType<typeof runTool>;
  userState(which: 'a' | 'b'): Record<string, unknown>;
}

interface FakeOptions {
  withoutFoldForB?: boolean;
}

async function makeVault(passphrase: string): Promise<{ meta: CryptoMeta; dek: Buffer }> {
  const dek = randomBytes(32);
  const passSalt = newSalt();
  const recoverySalt = newSalt();
  const kek = await deriveKey(passphrase, passSalt, ITERATIONS);
  const recovery = 'TEST-RECOVERY-CODE';
  const rek = await deriveKey(normalizeRecoveryCode(recovery), recoverySalt, ITERATIONS);
  const meta: CryptoMeta = {
    v: 1,
    kdf: 'pbkdf2-sha256',
    iterations: ITERATIONS,
    passSalt: passSalt.toString('base64'),
    recoverySalt: recoverySalt.toString('base64'),
    wrappedByPass: seal(dek, kek, Buffer.from('wrap:pass')),
    wrappedByRecovery: seal(dek, rek, Buffer.from('wrap:recovery')),
    check: seal(CHECK_TOKEN, dek, Buffer.from('check'))
  };
  return { meta, dek };
}

function sealAll(raw: Record<string, unknown>, dek: Buffer): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(raw)) {
    if (key === 'meos.crypto' || key === 'myos.crypto' || key === 'meos.ai.routes') out[key] = value;
    else out[key] = sealValue(Buffer.from(JSON.stringify(value), 'utf8'), dek, key);
  }
  return out;
}

function readBody(req: IncomingMessage): Promise<any> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on('data', (c: Buffer) => chunks.push(c));
    req.on('end', () => {
      if (!chunks.length) return resolve({});
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        reject(new Error('bad json'));
      }
    });
    req.on('error', reject);
  });
}

function json(res: ServerResponse, status: number, body: unknown, headers: Record<string, string> = {}) {
  const text = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(text),
    ...headers
  });
  res.end(text);
}

function cookieFor(req: IncomingMessage): string | null {
  const raw = req.headers.cookie ?? '';
  const match = /(?:^|;\s*)meos_session=([^;]+)/.exec(raw);
  return match ? decodeURIComponent(match[1]!) : null;
}

const ALLOWED_KEYS = new Set([
  'meos.fitness',
  'meos.fitnessProfile',
  'meos.notes',
  'meos.days',
  'meos.profile',
  'meos.chat',
  'meos.nutrition',
  'meos.training',
  'meos.events',
  'meos.eventTags',
  'meos.watch',
  'meos.belongings',
  'meos.fold',
  'meos.memory',
  'meos.scans',
  'meos.taskMode',
  'meos.weekly',
  'meos.activity',
  'meos.appearance',
  'meos.crypto',
  'meos.sixPack',
  'meos.finance',
  'meos.trash'
]);

export async function createHarness(options: FakeOptions = {}): Promise<Harness> {
  const today = todayKey();
  const { meta, dek } = await makeVault('vault-pass-A');

  const foods = JSON.parse(readFileSync(new URL('../../../diet/src/foods.json', import.meta.url), 'utf8')) as Array<{
    id: string;
    name: string;
  }>;
  const seedFood = foods[0]!;

  const rawA: Record<string, unknown> = {
    'meos.crypto': meta,
    'meos.profile': {
      name: 'Berjil',
      dob: '1996-04-12',
      age: 30,
      bloodGroup: 'O+',
      relationship: 'Single',
      phone: '+91 99999 00000',
      email: 'berjil@example.com',
      city: 'Chennai',
      hometown: 'Kochi',
      education: 'B.Tech',
      heightCm: 178,
      photoBase64: 'SECRET_PROFILE_PHOTO_BASE64',
      role: 'Founder',
      work: 'MeOS',
      website: 'https://example.com',
      instagram: '',
      github: 'berjilberjil',
      goalsShort: ['Ship the MCP gateway'],
      goalsMid: ['Launch MeOS 2'],
      goalsLong: ['Build a personal OS'],
      achievements: [{ id: 'ach1', year: '2025', title: 'Shipped v1', note: 'Shipped the first version' }],
      healthNotes: 'PRIVATE_HEALTH_NOTE',
      about: 'PRIVATE_ABOUT_TEXT',
      habits: ['Gym', 'Read']
    },
    'meos.notes': [
      {
        id: 'note-normal',
        createdAt: '2026-01-01T10:00:00',
        updatedAt: '2026-01-02T10:00:00',
        title: 'Groceries',
        body: 'Milk and eggs',
        pinned: false,
        locked: false,
        content: {
          blocks: [
            { id: 'b1', type: 'paragraph', spans: [{ text: 'Milk and eggs', marks: [] }] },
            { id: 'b2', type: 'image', spans: [], src: 'ATTACHMENT_BASE64' }
          ]
        }
      },
      {
        id: 'note-locked',
        createdAt: '2026-01-03T10:00:00',
        updatedAt: '2026-01-04T10:00:00',
        title: 'Private',
        body: 'LOCKED_BODY_TEXT',
        pinned: true,
        locked: true
      }
    ],
    'meos.days': {
      [today]: {
        todos: [
          { id: 'todo-1', text: 'Ship the gateway', done: false, mins: 50, spent: 120 },
          { id: 'todo-2', text: 'Old task', done: true, mins: null, spent: 0 }
        ],
        habits: { Gym: true }
      },
      '2026-01-01': { todos: [{ id: 'todo-old', text: 'Past task', done: false, spent: 0 }], habits: {} }
    },
    'meos.events': [
      {
        id: 'event-birthday',
        date: '1990-05-20',
        title: 'Birthday',
        tagIDs: ['family'],
        note: '',
        media: [],
        special: false,
        time: null,
        recurrence: { unit: 'yearly', interval: 1, until: null },
        reminders: ['oneWeek', 'sameDay'],
        category: 'family',
        done: false
      },
      {
        id: 'event-trip',
        date: today,
        title: 'Trip',
        tagIDs: ['travel'],
        note: 'Pack',
        media: [{ id: 'm1', kind: 'image', data: '', r2Key: 'm1', posterKey: null }],
        special: true,
        time: '09:30',
        recurrence: { unit: 'none', interval: 1, until: null },
        reminders: ['sameDay'],
        category: 'travel',
        done: false
      }
    ],
    'meos.eventTags': [
      { id: 'personal', name: 'Personal', symbol: 'person.fill', colorHex: '58CC02', builtIn: true },
      { id: 'travel', name: 'Travel', symbol: 'airplane', colorHex: '1CB0F6', builtIn: true },
      { id: 'family', name: 'Family', symbol: 'house.fill', colorHex: 'FF9600', builtIn: true },
      { id: 'work', name: 'Work', symbol: 'briefcase.fill', colorHex: 'FFC800', builtIn: true },
      { id: 'milestone', name: 'Milestone', symbol: 'flag.fill', colorHex: 'CE82FF', builtIn: true },
      { id: 'reminder', name: 'Reminder', symbol: 'bell.fill', colorHex: '84D8FF', builtIn: true },
      { id: 'other', name: 'Other', symbol: 'calendar', colorHex: '9A9A9A', builtIn: true }
    ],
    'meos.fitness': {
      [today]: { weightKg: 74, calories: 2100, proteinG: 150, waterMl: 2500, steps: 9000, note: 'good day', hailed: [1] },
      '2026-01-01': { weightKg: 77.5, calories: 2500, proteinG: 120, waterMl: 2000, steps: 6000 }
    },
    'meos.fitnessProfile': {
      goal: 'cut',
      sex: 'male',
      activity: 'moderate',
      targetWeightKg: 70,
      calorieTargetKcal: 2000,
      proteinTargetG: 160
    },
    'meos.training': {
      customExercises: [
        {
          id: 'ex-custom',
          name: 'Cable Fly',
          category: 'chest',
          equipment: 'Cable',
          primary: 'chest',
          muscles: ['chest'],
          weighted: true,
          isDefault: false
        }
      ],
      weekPlan: {},
      dayLog: {
        [today]: {
          done: true,
          skipped: false,
          title: 'Push A',
          dayId: 'day1',
          programId: 'prog1',
          restOverride: false,
          entries: [
            {
              id: 'el1',
              exerciseId: 'ex-custom',
              group: 'chest',
              sets: [
                { id: 's1', weightKg: 60, reps: 8, done: true },
                { id: 's2', weightKg: 60, reps: 7, done: true }
              ]
            },
            {
              id: 'el2',
              exerciseId: 'seed-exercise',
              group: 'triceps',
              sets: [{ id: 's3', weightKg: 20, reps: 12, done: true }]
            }
          ]
        },
        '2026-01-01': { done: false, skipped: true, restOverride: false, entries: [] }
      },
      programs: [
        {
          id: 'prog1',
          name: 'PPL',
          notes: null,
          goal: 'Strength',
          days: [],
          anchorDate: null,
          createdAt: '2026-01-01T00:00:00'
        }
      ],
      activeProgramId: 'prog1',
      migratedWeekPlan: true
    },
    'meos.nutrition': {
      customFoods: [],
      mealPlan: {
        [String(new Date(Date.UTC(Number(today.slice(0, 4)), Number(today.slice(5, 7)) - 1, Number(today.slice(8, 10)))).getUTCDay())]: {
          breakfast: [{ id: 'pi1', foodId: seedFood.id, quantity: 2 }]
        }
      },
      log: {
        [today]: {
          meals: { breakfast: [{ id: 'li1', foodId: seedFood.id, quantity: 1 }] },
          skipped: [],
          confirmed: ['breakfast']
        }
      }
    },
    'meos.memory': {
      items: [
        {
          id: 'mem1',
          content: 'Uses PostgreSQL for all projects',
          category: 'preference',
          importance: 4,
          source: 'stated',
          confidence: 1,
          createdAt: '2026-01-01T00:00:00',
          updatedAt: '2026-01-01T00:00:00',
          pinned: true
        },
        {
          id: 'mem2',
          content: 'Building MeOS as a personal operating system',
          category: 'project',
          importance: 5,
          source: 'manual',
          confidence: 1,
          createdAt: '2026-01-02T00:00:00',
          updatedAt: '2026-01-02T00:00:00',
          pinned: false
        }
      ]
    },
    'meos.belongings': {
      salaryPaise: 5_000_000,
      categories: [],
      items: [
        {
          id: 'buy1',
          name: 'CMF Buds',
          kind: 'gadgets',
          pricePaise: 249900,
          boughtOn: '2026-01-01',
          lifeDays: 1080,
          note: '',
          retired: false,
          photoBase64: '',
          categoryID: 'gadgets',
          link: ''
        },
        {
          id: 'buy2',
          name: 'Old Phone',
          kind: 'gadgets',
          pricePaise: 5000000,
          boughtOn: '2020-01-01',
          lifeDays: 1080,
          note: '',
          retired: true,
          photoBase64: '',
          categoryID: 'gadgets',
          link: ''
        }
      ]
    },
    'meos.fold': {
      asOf: today,
      currency: 'INR',
      netWorth: 1234567,
      liquid: 200000,
      investments: 1100000,
      debt: 65433,
      spentThisMonth: 42000,
      stocksValue: 600000,
      mfValue: 500000,
      changeValue: 12345,
      changePercent: 1.2,
      changeLabel: 'up',
      history: [1000000, 1100000, 1234567],
      banks: [
        { name: 'HDFC', last4: '1234', balance: 150000 },
        { name: 'ICICI', last4: '9876', balance: 50000 }
      ],
      topSpends: [
        { category: 'food', amount: 12000 },
        { category: 'refunds', amount: 3000 },
        { category: 'interest', amount: 500 }
      ]
    },
    'meos.trash': [],
    'meos.watch': [
      {
        id: 'watch1',
        url: 'https://youtu.be/abc123',
        videoId: 'abc123',
        title: 'Investing basics',
        channel: 'Money',
        thumbUrl: '',
        addedAt: '2026-01-01T00:00:00',
        category: 'investing',
        takeaway: 'Index funds',
        watched: false
      }
    ],
    'meos.scans': [],
    'meos.taskMode': { on: false, since: '', device: '' },
    'meos.weekly': [],
    'meos.activity': { days: [] },
    'meos.appearance': { theme: 'dark' },
    'meos.sixPack': { days: {} },
    'meos.chat': { threads: [], activeID: null },
    'meos.finance': {
      schemaVersion: 1,
      updatedAt: nowStamp(),
      settings: {
        trackingStartDate: '2026-01-01',
        birthDate: null,
        currency: 'INR',
        locale: 'en_IN',
        includeHouseholdInNetWorth: false,
        emergencyFundMonths: 6,
        hideBalances: false,
        demoMode: false,
        demoSeededAt: null
      },
      accounts: [
        {
          id: 'acct-bank', name: 'Everyday salary', institution: 'Northstar Bank',
          type: 'savings', currency: 'INR', openingDate: '2026-01-01',
          openingBalancePaise: 0, statementBalancePaise: null, statementBalanceOn: null,
          statementBalanceSource: 'verified', creditLimitPaise: null, status: 'active',
          notes: '', lastReconciledOn: null, isDemo: false,
          createdAt: nowStamp(), updatedAt: nowStamp()
        },
        {
          id: 'acct-card', name: 'Aster card', institution: 'Aster',
          type: 'creditCard', currency: 'INR', openingDate: '2026-01-01',
          openingBalancePaise: 0, statementBalancePaise: null, statementBalanceOn: null,
          statementBalanceSource: 'verified', creditLimitPaise: 5_000_000, status: 'active',
          notes: '', lastReconciledOn: null, isDemo: false,
          createdAt: nowStamp(), updatedAt: nowStamp()
        }
      ],
      categories: [
        { id: 'cat-food', name: 'Food', kind: 'expense', group: 'Living', icon: 'fork.knife', parentID: null, isSystem: false, archived: false, isDemo: false, createdAt: nowStamp() },
        { id: 'cat-salary', name: 'Salary', kind: 'income', group: 'Employment', icon: 'briefcase', parentID: null, isSystem: false, archived: false, isDemo: false, createdAt: nowStamp() }
      ],
      transactions: [
        {
          id: 'txn-income', date: today, postedDate: null, amountPaise: 10_000_000,
          currency: 'INR', direction: 'inflow', type: 'income', accountID: 'acct-bank',
          transferAccountID: null, categoryID: 'cat-salary', subcategoryID: null,
          merchant: 'Employer', paymentMethod: 'bankTransfer', note: '', reference: '',
          tags: [], source: 'manual', statementID: null, importBatchID: null,
          verification: 'verified', transferID: null, linkedTransactionID: null,
          investmentID: null, liabilityID: null, principalPaise: null, interestPaise: null,
          costBasisPaise: null, realisedGainPaise: null, isDemo: false,
          createdAt: nowStamp(), updatedAt: nowStamp()
        },
        {
          id: 'txn-food', date: today, postedDate: null, amountPaise: 500_000,
          currency: 'INR', direction: 'outflow', type: 'expense', accountID: 'acct-bank',
          transferAccountID: null, categoryID: 'cat-food', subcategoryID: null,
          merchant: 'Cafe', paymentMethod: 'upi', note: '', reference: '',
          tags: [], source: 'manual', statementID: null, importBatchID: null,
          verification: 'verified', transferID: null, linkedTransactionID: null,
          investmentID: null, liabilityID: null, principalPaise: null, interestPaise: null,
          costBasisPaise: null, realisedGainPaise: null, isDemo: false,
          createdAt: nowStamp(), updatedAt: nowStamp()
        },
        {
          id: 'txn-card', date: today, postedDate: null, amountPaise: 200_000,
          currency: 'INR', direction: 'outflow', type: 'expense', accountID: 'acct-card',
          transferAccountID: null, categoryID: 'cat-food', subcategoryID: null,
          merchant: 'Shop', paymentMethod: 'card', note: '', reference: '',
          tags: [], source: 'manual', statementID: null, importBatchID: null,
          verification: 'verified', transferID: null, linkedTransactionID: null,
          investmentID: null, liabilityID: null, principalPaise: null, interestPaise: null,
          costBasisPaise: null, realisedGainPaise: null, isDemo: false,
          createdAt: nowStamp(), updatedAt: nowStamp()
        },
        {
          id: 'txn-transfer-out', date: today, postedDate: null, amountPaise: 200_000,
          currency: 'INR', direction: 'outflow', type: 'transfer', accountID: 'acct-bank',
          transferAccountID: 'acct-card', categoryID: null, subcategoryID: null,
          merchant: 'Card payment', paymentMethod: 'bankTransfer', note: '', reference: '',
          tags: [], source: 'manual', statementID: null, importBatchID: null,
          verification: 'verified', transferID: 'tr-seed', linkedTransactionID: 'txn-transfer-in',
          investmentID: null, liabilityID: null, principalPaise: null, interestPaise: null,
          costBasisPaise: null, realisedGainPaise: null, isDemo: false,
          createdAt: nowStamp(), updatedAt: nowStamp()
        },
        {
          id: 'txn-transfer-in', date: today, postedDate: null, amountPaise: 200_000,
          currency: 'INR', direction: 'inflow', type: 'transfer', accountID: 'acct-card',
          transferAccountID: 'acct-bank', categoryID: null, subcategoryID: null,
          merchant: 'Card payment', paymentMethod: 'bankTransfer', note: '', reference: '',
          tags: [], source: 'manual', statementID: null, importBatchID: null,
          verification: 'verified', transferID: 'tr-seed', linkedTransactionID: 'txn-transfer-out',
          investmentID: null, liabilityID: null, principalPaise: null, interestPaise: null,
          costBasisPaise: null, realisedGainPaise: null, isDemo: false,
          createdAt: nowStamp(), updatedAt: nowStamp()
        },
        {
          id: 'txn-refund', date: today, postedDate: null, amountPaise: 50_000,
          currency: 'INR', direction: 'inflow', type: 'refund', accountID: 'acct-bank',
          transferAccountID: null, categoryID: 'cat-food', subcategoryID: null,
          merchant: 'Cafe refund', paymentMethod: 'upi', note: '', reference: '',
          tags: [], source: 'manual', statementID: null, importBatchID: null,
          verification: 'verified', transferID: null, linkedTransactionID: null,
          investmentID: null, liabilityID: null, principalPaise: null, interestPaise: null,
          costBasisPaise: null, realisedGainPaise: null, isDemo: false,
          createdAt: nowStamp(), updatedAt: nowStamp()
        },
        {
          id: 'txn-invest', date: today, postedDate: null, amountPaise: 1_000_000,
          currency: 'INR', direction: 'outflow', type: 'investmentPurchase', accountID: 'acct-bank',
          transferAccountID: null, categoryID: null, subcategoryID: null,
          merchant: 'Index fund', paymentMethod: 'bankTransfer', note: '', reference: '',
          tags: [], source: 'manual', statementID: null, importBatchID: null,
          verification: 'verified', transferID: null, linkedTransactionID: null,
          investmentID: 'inv-index', liabilityID: null, principalPaise: null, interestPaise: null,
          costBasisPaise: null, realisedGainPaise: null, isDemo: false,
          createdAt: nowStamp(), updatedAt: nowStamp()
        },
        {
          id: 'txn-loan', date: today, postedDate: null, amountPaise: 100_000,
          currency: 'INR', direction: 'outflow', type: 'loanRepayment', accountID: 'acct-bank',
          transferAccountID: null, categoryID: null, subcategoryID: null,
          merchant: 'Education loan', paymentMethod: 'autoDebit', note: '', reference: '',
          tags: [], source: 'manual', statementID: null, importBatchID: null,
          verification: 'verified', transferID: null, linkedTransactionID: null,
          investmentID: null, liabilityID: 'liab-education', principalPaise: 80_000, interestPaise: 20_000,
          costBasisPaise: null, realisedGainPaise: null, isDemo: false,
          createdAt: nowStamp(), updatedAt: nowStamp()
        }
      ],
      transfers: [
        {
          id: 'tr-seed', fromAccountID: 'acct-bank', toAccountID: 'acct-card', amountPaise: 200_000,
          date: today, feePaise: 0, reference: '', note: '', fromTransactionID: 'txn-transfer-out',
          toTransactionID: 'txn-transfer-in', feeTransactionID: null, reconciled: true,
          isDemo: false, createdAt: nowStamp()
        }
      ],
      budgets: [
        { id: 'budget-food', name: 'Food', categoryID: 'cat-food', period: 'monthly', startDate: monthStart(today), endDate: null, plannedPaise: 600_000, note: '', archived: false, isDemo: false, createdAt: nowStamp() }
      ],
      investments: [
        {
          id: 'inv-index', name: 'Index fund', assetClass: 'mutualFund', institution: 'Meridian',
          units: 100, purchaseDate: '2026-01-01', purchasePricePaise: 10_000,
          investedPaise: 1_000_000, currentValuePaise: 1_200_000, currentValueOn: today,
          realisedGainPaise: 0, dividendsPaise: 0, interestPaise: 0, notes: '',
          accountID: null, archived: false, isDemo: false, createdAt: nowStamp(), updatedAt: nowStamp()
        }
      ],
      valuations: [
        { id: 'val-index', investmentID: 'inv-index', date: today, valuePaise: 1_200_000, source: 'manual', note: '', isDemo: false, createdAt: nowStamp() }
      ],
      liabilities: [
        {
          id: 'liab-education', name: 'Education loan', kind: 'educationLoan', lender: 'Northstar Bank',
          ownership: 'personal', originalPrincipalPaise: 500_000, outstandingPaise: 500_000,
          asOf: '2026-01-01', interestRateBps: 950, emiPaise: 100_000, dueDay: 7,
          startDate: '2026-01-01', maturityDate: null, accountID: null, notes: '', closed: false,
          isDemo: false, createdAt: nowStamp(), updatedAt: nowStamp()
        }
      ],
      debtPayments: [
        { id: 'dp-loan', liabilityID: 'liab-education', transactionID: 'txn-loan', date: today, amountPaise: 100_000, principalPaise: 80_000, interestPaise: 20_000, note: '', isDemo: false, createdAt: nowStamp() }
      ],
      goals: [
        { id: 'goal-emergency', name: 'Emergency fund', kind: 'emergencyFund', targetPaise: 5_000_000, currentPaise: 1_000_000, deadline: null, monthlyContributionPaise: 100_000, accountID: null, note: '', achieved: false, isDemo: false, createdAt: nowStamp(), updatedAt: nowStamp() }
      ],
      recurring: [],
      statements: [],
      importBatches: [],
      importRows: [],
      reconciliations: [],
      audit: [],
      snapshots: [],
      milestones: []
    },
    'meos.ai.routes': { default: { keyId: 1, model: 'gemini-2.5-flash' } }
  };

  const rawB: Record<string, unknown> = {
    'meos.crypto': meta,
    'meos.profile': {
      ...(rawA['meos.profile'] as object),
      name: 'Other Person',
      phone: '+91 88888 11111',
      email: 'other@example.com',
      goalsShort: ['Stay separate']
    },
    'meos.notes': [
      {
        id: 'note-b',
        createdAt: '2026-02-01T10:00:00',
        updatedAt: '2026-02-01T10:00:00',
        title: 'B only',
        body: 'SECRET_B_BODY',
        pinned: false,
        locked: false
      }
    ],
    'meos.days': {},
    'meos.events': [],
    'meos.eventTags': rawA['meos.eventTags'],
    'meos.fitness': {},
    'meos.fitnessProfile': rawA['meos.fitnessProfile'],
    'meos.training': { customExercises: [], weekPlan: {}, dayLog: {}, programs: [], activeProgramId: null, migratedWeekPlan: false },
    'meos.nutrition': { customFoods: [], log: {}, mealPlan: {} },
    'meos.memory': { items: [] },
    'meos.belongings': { items: [], salaryPaise: 1, categories: [] },
    ...(options.withoutFoldForB ? {} : { 'meos.fold': { ...(rawA['meos.fold'] as object), netWorth: 2 } }),
    'meos.trash': [],
    'meos.watch': [],
    'meos.scans': [],
    'meos.taskMode': { on: false, since: '', device: '' },
    'meos.weekly': [],
    'meos.activity': { days: [] },
    'meos.appearance': { theme: 'light' },
    'meos.sixPack': { days: {} },
    'meos.chat': { threads: [], activeID: null }
  };

  const users: Record<'a' | 'b', FakeState> = {
    a: { seed: { username: 'owner-a', password: 'pass-a', passphrase: 'vault-pass-A', raw: sealAll(rawA, dek) }, cells: {}, cookie: null },
    b: { seed: { username: 'owner-b', password: 'pass-b', passphrase: 'vault-pass-A', raw: sealAll(rawB, dek) }, cells: {}, cookie: null }
  };

  const deletedEventMedia: string[] = [];
  const deletedBodyPhotos: string[] = [];

  const server: Server = createServer(async (req, res) => {
    const url = new URL(req.url ?? '/', 'http://localhost');
    const cookie = cookieFor(req);
    const state = Object.values(users).find((u) => u.cookie === cookie) ?? null;

    if (req.method === 'POST' && url.pathname === '/api/auth/login') {
      const body = await readBody(req);
      const found = (Object.values(users) as FakeState[]).find(
        (u) => u.seed.username === body.username && u.seed.password === body.password
      );
      if (!found) return json(res, 401, { message: 'Bad credentials' });
      const token = randomUUID();
      found.cookie = token;
      return json(res, 200, { id: found.seed.username, username: found.seed.username }, {
        'Set-Cookie': `meos_session=${token}; Path=/; HttpOnly; SameSite=Lax`
      });
    }

    if (!state) return json(res, 401, { message: 'Not logged in' });

    if (url.pathname === '/api/me' && req.method === 'GET') {
      return json(res, 200, { id: state.seed.username, username: state.seed.username });
    }
    if (url.pathname === '/api/state' && req.method === 'GET') {
      return json(res, 200, { ...state.seed.raw, ...state.cells });
    }
    if (url.pathname.startsWith('/api/state/') && req.method === 'PUT') {
      const key = decodeURIComponent(url.pathname.slice('/api/state/'.length));
      if (!ALLOWED_KEYS.has(key)) return json(res, 400, { message: 'Unknown state key' });
      state.cells[key] = await readBody(req);
      return json(res, 200, { ok: true });
    }
    if (url.pathname === '/api/devices' && req.method === 'GET') {
      return json(res, 200, {
        devices: [
          {
            id: 'dev1',
            name: 'Berjil Mac',
            system_name: 'MacBook',
            platform: 'macOS',
            kind: 'mac',
            app_version: '1.0',
            created_at: '2026-01-01T00:00:00',
            last_seen: '2026-01-02T00:00:00'
          }
        ]
      });
    }
    if (url.pathname === '/api/ai/keys' && req.method === 'GET') {
      return json(res, 200, {
        keys: [
          {
            id: 1,
            provider: 'gemini',
            label: 'Personal',
            masked: 'AIza••••1234',
            enabled: true,
            models: ['gemini-2.5-flash', 'gemini-2.5-pro']
          }
        ]
      });
    }
    if (url.pathname === '/api/ai/routes' && req.method === 'GET') {
      return json(res, 200, { default: { keyId: 1, model: 'gemini-2.5-flash', secret: 'NOPE' } });
    }
    if (url.pathname === '/api/body-photos' && req.method === 'GET') {
      return json(res, 200, [
        { id: '2026-01-01__p1', date: '2026-01-01', url: 'https://signed.example/secret', updatedAt: '2026-01-01T00:00:00', bytes: 1000 },
        { id: '2026-02-01__p2', date: '2026-02-01', url: 'https://signed.example/secret2', updatedAt: '2026-02-01T00:00:00', bytes: 2000 }
      ]);
    }
    if (url.pathname.startsWith('/api/event-media/') && (req.method === 'DELETE' || req.method === 'GET')) {
      deletedEventMedia.push(url.pathname);
      return json(res, 200, { ok: true });
    }
    if (url.pathname.startsWith('/api/body-photos/') && req.method === 'DELETE') {
      deletedBodyPhotos.push(url.pathname);
      return json(res, 200, { ok: true });
    }
    return json(res, 404, { message: 'not found' });
  });

  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  const accounts: Record<'a' | 'b', SeedUser> = { a: users.a.seed, b: users.b.seed };

  const accountConfig = (which: 'a' | 'b'): AccountConfig => ({
    id: which,
    baseUrl,
    username: accounts[which].username,
    password: accounts[which].password,
    vaultPassphrase: accounts[which].passphrase,
    requestTimeoutMs: 5000
  });

  const registry = new ServiceRegistry(
    new Map([
      ['a', accountConfig('a')],
      ['b', accountConfig('b')]
    ]),
    silentLogger
  );

  const limiter = new RateLimiter(60_000, 1000);

  return {
    baseUrl,
    accounts,
    meta,
    deletedEventMedia,
    deletedBodyPhotos,
    async close() {
      await new Promise<void>((resolve) => server.close(() => resolve()));
    },
    ctxFor(which, scopes = ['read'], opts = {}) {
      const client: ClientConfig = {
        id: `client-${which}`,
        tokenHash: null,
        scopes,
        accountId: which
      };
      return {
        client,
        services: registry.get(which),
        logger: silentLogger,
        limiter: opts.rateLimit
          ? new RateLimiter(60_000, opts.rateLimit)
          : limiter,
        now: new Date()
      };
    },
    call(ctx, name, args = {}) {
      return runTool(findTool(name), args, ctx);
    },
    userState(which) {
      return users[which].cells;
    }
  };
}

export function payload(result: any): any {
  return result.structuredContent;
}

export function errorCode(result: any): string | undefined {
  return result.structuredContent?.error?.code;
}

export function testConfig(overrides: Partial<RuntimeConfig> = {}): RuntimeConfig {
  return {
    transport: 'http',
    http: { host: '127.0.0.1', port: 0, path: '/mcp', maxBodyBytes: 1_000_000 },
    accounts: new Map(),
    clients: new Map(),
    stdioClientId: 'stdio',
    rateLimit: { windowMs: 60_000, max: 1000 },
    logLevel: 'error',
    ...overrides
  };
}
