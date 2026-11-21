import { z } from 'zod';
import { STATE_KEYS, type MemoryItem, type MemoryState } from '../schemas/models.ts';
import { errors } from '../utils/errors.ts';
import { ok } from '../utils/result.ts';
import { paginate } from '../utils/pagination.ts';
import { nowStamp } from '../utils/dates.ts';
import { newId } from '../utils/ids.ts';
import type { ToolDefinition } from './registry.ts';
import { cleanText, readObject } from './shared.ts';

const CATEGORIES = [
  'identity',
  'preference',
  'goal',
  'project',
  'skill',
  'decision',
  'relationship',
  'workflow',
  'other'
] as const;

/** Same markers the app refuses to extract from a conversation. */
const SENSITIVE = [
  'password',
  'passphrase',
  'otp',
  'cvv',
  'pin is',
  'card number',
  'aadhaar',
  'aadhar',
  'pan number',
  'api key',
  'secret key',
  'private key',
  'seed phrase',
  'account number'
];

function terms(text: string): Set<string> {
  return new Set(
    text
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, ' ')
      .split(/\s+/)
      .filter((w) => w.length > 1)
  );
}

function isDuplicate(a: string, b: string): boolean {
  const x = terms(a);
  const y = terms(b);
  if (!x.size || !y.size) return false;
  let overlap = 0;
  for (const t of x) if (y.has(t)) overlap += 1;
  return overlap / Math.max(x.size, y.size) >= 0.8;
}

function ensureSafe(content: string): void {
  const low = content.toLowerCase();
  const hit = SENSITIVE.find((m) => low.includes(m));
  if (hit) {
    throw errors.invalidInput(
      'This looks like a credential or identity secret. MeOS memory is not a password store; store secrets in a dedicated password manager.'
    );
  }
}

function memoryForClient(item: MemoryItem) {
  return {
    id: item.id,
    content: item.content,
    category: item.category,
    importance: item.importance,
    source: item.source,
    confidence: item.confidence,
    pinned: item.pinned,
    created_at: item.createdAt,
    updated_at: item.updatedAt
  };
}

function rank(item: MemoryItem, query: Set<string>): number {
  let overlap = 0;
  const t = terms(item.content);
  for (const word of query) if (t.has(word)) overlap += 1;
  const relevant = overlap > 0 || item.pinned || item.category === 'identity' || item.category === 'preference';
  if (!relevant) return -1;
  let score = overlap * 2;
  if (item.category === 'identity' || item.category === 'preference') score += 0.75;
  if (item.pinned) score += 3;
  score += item.importance * 0.35;
  score *= Math.max(0.4, item.confidence);
  return score;
}

export const memoryTools: ToolDefinition[] = [
  {
    name: 'meos_memory_list',
    title: 'List memories',
    description:
      'List durable facts MeOS remembers about the owner: projects, preferences, decisions, people, workflows. This is a curated memory bank, not a chat transcript.',
    inputSchema: {
      category: z.enum(CATEGORIES).optional(),
      pinned_only: z.boolean().optional(),
      limit: z.number().int().min(1).max(100).optional(),
      cursor: z.string().optional()
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const state = await readObject<MemoryState>(ctx, STATE_KEYS.memory, { items: [] });
      let items = state.items ?? [];
      if (args.category) items = items.filter((i) => i.category === args.category);
      if (args.pinned_only === true) items = items.filter((i) => i.pinned);
      items = [...items].sort(
        (a, b) =>
          Number(b.pinned) - Number(a.pinned) ||
          b.importance - a.importance ||
          (b.updatedAt ?? '').localeCompare(a.updatedAt ?? '')
      );
      const page = paginate(items, args.limit, args.cursor);
      return ok({ ...page, items: page.items.map(memoryForClient), total_matching: items.length });
    }
  },

  {
    name: 'meos_memory_search',
    title: 'Search memories',
    description:
      'Search the memory bank by relevance to a query, lifted by importance, confidence and pinning. Identity and preference memories always remain eligible; unrelated facts are excluded.',
    inputSchema: {
      query: z.string().min(1).max(500),
      limit: z.number().int().min(1).max(50).optional()
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const state = await readObject<MemoryState>(ctx, STATE_KEYS.memory, { items: [] });
      const q = args.query.trim();
      const query = terms(q);
      const limit = Math.min(args.limit ?? 8, 50);
      const scored = (state.items ?? [])
        .map((item) => ({ item, score: rank(item, query) }))
        .filter((row) => row.score >= 0)
        .sort((a, b) => b.score - a.score || (b.item.updatedAt ?? '').localeCompare(a.item.updatedAt ?? ''))
        .slice(0, limit)
        .map((row) => memoryForClient(row.item));
      return ok({ query: q, memories: scored, returned: scored.length });
    }
  },

  {
    name: 'meos_memory_get',
    title: 'Get a memory',
    description: 'Read one memory by id.',
    inputSchema: { id: z.string().min(1) },
    scopes: ['read'],
    async handler(args, ctx) {
      const state = await readObject<MemoryState>(ctx, STATE_KEYS.memory, { items: [] });
      const item = (state.items ?? []).find((i) => i.id === String(args.id).toLowerCase());
      if (!item) throw errors.notFound('Memory');
      return ok(memoryForClient(item));
    }
  },

  {
    name: 'meos_memory_create',
    title: 'Create a memory',
    description:
      'Store one durable fact about the owner. Credentials, OTPs, card/account numbers and similar secrets are refused. Near-duplicates of an existing memory are refused rather than silently appended.',
    inputSchema: {
      content: z.string().min(8).max(400).describe('One self-contained sentence about the user.'),
      category: z.enum(CATEGORIES).optional(),
      importance: z.number().int().min(1).max(5).optional(),
      pinned: z.boolean().optional()
    },
    scopes: ['write'],
    async handler(args, ctx) {
      const content = cleanText(args.content, 'content', 400);
      if (content.length < 8) throw errors.invalidInput('content must be at least 8 characters');
      ensureSafe(content);
      const state = await readObject<MemoryState>(ctx, STATE_KEYS.memory, { items: [] });
      if ((state.items ?? []).some((i) => isDuplicate(i.content, content))) {
        throw errors.conflict('A near-duplicate memory already exists; update it instead of adding another.');
      }
      const stamp = nowStamp();
      const item: MemoryItem = {
        id: newId(),
        content,
        category: args.category ?? 'other',
        importance: Math.max(1, Math.min(5, args.importance ?? 3)),
        source: 'manual',
        confidence: 1,
        createdAt: stamp,
        updatedAt: stamp,
        pinned: args.pinned === true
      };
      await ctx.services.store.update<MemoryState>(STATE_KEYS.memory, (current) => ({
        items: [item, ...((current?.items ?? []) as MemoryItem[])]
      }));
      return ok(memoryForClient(item), { written: STATE_KEYS.memory });
    }
  },

  {
    name: 'meos_memory_update',
    title: 'Update a memory',
    description: 'Edit one memory\'s content, category, importance or pin. Only supplied fields change.',
    inputSchema: {
      id: z.string().min(1),
      content: z.string().min(8).max(400).optional(),
      category: z.enum(CATEGORIES).optional(),
      importance: z.number().int().min(1).max(5).optional(),
      pinned: z.boolean().optional()
    },
    scopes: ['write'],
    async handler(args, ctx) {
      const id = String(args.id).toLowerCase();
      const content = args.content !== undefined ? cleanText(args.content, 'content', 400) : undefined;
      if (content) ensureSafe(content);
      if (
        content === undefined &&
        args.category === undefined &&
        args.importance === undefined &&
        args.pinned === undefined
      ) {
        throw errors.invalidInput('Nothing to update');
      }
      let updated: MemoryItem | null = null;
      await ctx.services.store.update<MemoryState>(STATE_KEYS.memory, (current) => {
        const items = current?.items ?? [];
        return {
          items: items.map((i) => {
            if (i.id !== id) return i;
            updated = {
              ...i,
              ...(content !== undefined ? { content, source: 'manual' as const, confidence: 1 } : {}),
              ...(args.category !== undefined ? { category: args.category } : {}),
              ...(args.importance !== undefined ? { importance: args.importance } : {}),
              ...(args.pinned !== undefined ? { pinned: Boolean(args.pinned) } : {}),
              updatedAt: nowStamp()
            };
            return updated;
          })
        };
      });
      if (!updated) throw errors.notFound('Memory');
      return ok(memoryForClient(updated), { written: STATE_KEYS.memory });
    }
  }
];
