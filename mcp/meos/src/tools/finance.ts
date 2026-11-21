import { z } from 'zod';
import { STATE_KEYS, DEFAULT_BELONGINGS, type BelongingsState, type BelongingItem, type FoldData } from '../schemas/models.ts';
import { errors } from '../utils/errors.ts';
import { ok } from '../utils/result.ts';
import { paginate } from '../utils/pagination.ts';
import { addDays, todayKey } from '../utils/dates.ts';
import { newId } from '../utils/ids.ts';
import type { ToolDefinition } from './registry.ts';
import {
  belongingSnapshot,
  cleanText,
  monthlyBurnPaise,
  purchaseForClient,
  readObject,
  recycleAndRemove,
  spendHealth,
  trashEntry
} from './shared.ts';

const BUILT_IN_CATEGORIES = ['gadgets', 'clothes', 'home', 'books', 'wheels', 'other'] as const;
const NON_SPEND = new Set(['returns', 'return', 'refund', 'refunds', 'cashback', 'interest', 'dividend']);

function foldOrNull(fold: FoldData | null): FoldData | null {
  // An empty object is not a linked Fold account. Requiring the headline number
  // prevents "undefined" from leaking into a financial answer.
  return fold && typeof fold === 'object' && typeof fold.netWorth === 'number' ? fold : null;
}

function foldMetadata(fold: FoldData, today = todayKey()): Record<string, unknown> {
  const asOf = typeof fold.asOf === 'string' ? fold.asOf.slice(0, 10) : '';
  const ageDays = /^\d{4}-\d{2}-\d{2}$/.test(asOf)
    ? Math.max(0, Math.round((Date.parse(`${today}T00:00:00Z`) - Date.parse(`${asOf}T00:00:00Z`)) / 86_400_000))
    : null;
  return {
    source_kind: 'synced_external_snapshot',
    provider: 'Fold',
    as_of: asOf || null,
    age_days: ageDays,
    stale: ageDays == null ? null : ageDays > 2,
    note: 'Balances are Fold\'s own snapshot. MeOS does not recompute them from transactions.'
  };
}

function categoryIds(state: BelongingsState): string[] {
  return [...BUILT_IN_CATEGORIES, ...state.categories.map((c) => c.id)];
}

/** Custom shelves still need one of the six built-in enum values on the item. */
function kindForCategory(category: string): BelongingItem['kind'] {
  return (BUILT_IN_CATEGORIES as readonly string[]).includes(category) ? category : 'other';
}

function parseRupees(value: number | string | undefined, field: string): number | undefined {
  if (value === undefined) return undefined;
  const n = typeof value === 'number' ? value : Number(String(value).replace(/[^0-9.-]/g, ''));
  if (!Number.isFinite(n) || n < 0 || n > 1_000_000_000) throw errors.invalidInput(`${field} must be a sensible positive amount`);
  return Math.round(n * 100);
}

function parseLink(value: string | undefined): string | undefined {
  if (value === undefined) return undefined;
  const raw = value.trim();
  if (!raw) return '';
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw errors.invalidInput('link must be an http(s) URL');
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') throw errors.invalidInput('link must be an http(s) URL');
  return url.toString();
}

const CursorShape = {
  limit: z.number().int().min(1).max(100).optional(),
  cursor: z.string().optional()
};

export const financeTools: ToolDefinition[] = [
  {
    name: 'meos_finance_get_summary',
    title: 'Get finance summary',
    description:
      'Read the separate Fold external banking snapshot: net worth, liquid cash, investments, debt, this month\'s spend, and ownership burn from logged purchases. For the owner\'s actual transaction ledger, call meos_finance_ledger_get_summary instead. This tool never sums ledger transactions and must not be mixed with them.',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      const fold = foldOrNull(await readObject<FoldData | null>(ctx, STATE_KEYS.fold, null));
      const belongings = await readObject<BelongingsState>(ctx, STATE_KEYS.belongings, DEFAULT_BELONGINGS);
      const live = (belongings.items ?? []).filter((i) => !i.retired);
      const burn = monthlyBurnPaise(live);
      const salary = belongings.salaryPaise ?? 4_000_000;

      if (!fold) {
        return ok(
          {
            linked: false,
            purchases: {
              live_items: live.length,
              total_spent_inr: live.reduce((s, i) => s + i.pricePaise, 0) / 100,
              monthly_burn_inr: burn / 100,
              salary_inr: salary / 100,
              spend_health: spendHealth(burn, salary)
            }
          },
          {
            source_kind: 'meos_stuff',
            note: 'Fold is not linked, so net worth, balances and investments are unavailable. They are not zero.'
          }
        );
      }

      const spendCats = (fold.topSpends ?? []).filter((s) => !NON_SPEND.has(String(s.category).toLowerCase()));
      return ok(
        {
          linked: true,
          currency: fold.currency || 'INR',
          net_worth: fold.netWorth,
          liquid: fold.liquid,
          investments: fold.investments,
          debt: fold.debt,
          spent_this_month: fold.spentThisMonth,
          change: {
            value: fold.changeValue,
            percent: fold.changePercent,
            label: fold.changeLabel
          },
          accounts: (fold.banks ?? []).length,
          top_spend_categories: spendCats,
          purchases: {
            live_items: live.length,
            total_spent_inr: live.reduce((s, i) => s + i.pricePaise, 0) / 100,
            monthly_burn_inr: burn / 100,
            salary_inr: salary / 100,
            spend_health: spendHealth(burn, salary)
          },
          provenance: {
            balances: 'Fold snapshot stored in meos.fold',
            purchases: 'MeOS Stuff ledger (meos.belongings)'
          }
        },
        foldMetadata(fold)
      );
    }
  },

  {
    name: 'meos_finance_list_accounts',
    title: 'List linked bank accounts',
    description:
      'List the bank accounts in the separate Fold snapshot with masked last four digits and balances. For owned ledger accounts, call meos_finance_ledger_list_accounts. Full account numbers are not stored and are never returned.',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      const fold = foldOrNull(await readObject<FoldData | null>(ctx, STATE_KEYS.fold, null));
      if (!fold) {
        return ok({ linked: false, accounts: [] }, { note: 'Fold is not linked. No account balances are available.' });
      }
      return ok(
        {
          linked: true,
          currency: fold.currency || 'INR',
          total_liquid: fold.liquid,
          accounts: (fold.banks ?? []).map((b) => ({
            name: b.name,
            masked_number: b.last4 ? `••••${b.last4}` : null,
            balance: b.balance
          }))
        },
        foldMetadata(fold)
      );
    }
  },

  {
    name: 'meos_finance_get_net_worth',
    title: 'Get net worth',
    description:
      'Net worth exactly as Fold reports it, with components and snapshot history. This is the external Fold view, not the owned ledger; use meos_finance_ledger_get_net_worth for derived net worth.',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      const fold = foldOrNull(await readObject<FoldData | null>(ctx, STATE_KEYS.fold, null));
      if (!fold) {
        return ok(
          { available: false, net_worth: null, components: null, history: [] },
          { note: 'Fold is not linked. MeOS will not invent a net worth figure.' }
        );
      }
      return ok(
        {
          available: true,
          currency: fold.currency || 'INR',
          net_worth: fold.netWorth,
          components: {
            liquid: fold.liquid,
            investments: fold.investments,
            debt: fold.debt
          },
          change: { value: fold.changeValue, percent: fold.changePercent, label: fold.changeLabel },
          history: Array.isArray(fold.history) ? fold.history : []
        },
        foldMetadata(fold)
      );
    }
  },

  {
    name: 'meos_finance_get_investments',
    title: 'Get investment summary',
    description:
      'Investment totals from the Fold snapshot only. Use meos_finance_ledger_get_investments for owned holdings, cost basis and dated valuations.',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      const fold = foldOrNull(await readObject<FoldData | null>(ctx, STATE_KEYS.fold, null));
      if (!fold) {
        return ok(
          { available: false, holdings_available: false, investments: null },
          { note: 'Fold is not linked.' }
        );
      }
      return ok(
        {
          available: true,
          currency: fold.currency || 'INR',
          investments_total: fold.investments,
          stocks_value: fold.stocksValue,
          mutual_funds_value: fold.mfValue,
          holdings_available: false
        },
        {
          ...foldMetadata(fold),
          limitation: 'MeOS stores totals only; it does not sync per-holding positions.'
        }
      );
    }
  },

  {
    name: 'meos_finance_get_spending',
    title: 'Get spending',
    description:
      'This month\'s category spending from the separate Fold snapshot, with non-spend categories separated. Use meos_finance_ledger_get_spending for the owned transaction ledger. Also returns the Stuff ownership-burn picture.',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      const fold = foldOrNull(await readObject<FoldData | null>(ctx, STATE_KEYS.fold, null));
      const belongings = await readObject<BelongingsState>(ctx, STATE_KEYS.belongings, DEFAULT_BELONGINGS);
      const live = (belongings.items ?? []).filter((i) => !i.retired);
      const burn = monthlyBurnPaise(live);
      const salary = belongings.salaryPaise ?? 4_000_000;

      const purchases = {
        monthly_burn_inr: burn / 100,
        salary_inr: salary / 100,
        spend_health: spendHealth(burn, salary),
        live_items: live.length
      };

      if (!fold) {
        return ok(
          { available: false, by_category: [], non_spend: [], purchases },
          { note: 'Fold is not linked, so card/bank spending is unavailable.' }
        );
      }
      const byCategory = (fold.topSpends ?? []).filter((s) => !NON_SPEND.has(String(s.category).toLowerCase()));
      const nonSpend = (fold.topSpends ?? []).filter((s) => NON_SPEND.has(String(s.category).toLowerCase()));
      return ok(
        {
          available: true,
          currency: fold.currency || 'INR',
          spent_this_month: fold.spentThisMonth,
          by_category: byCategory,
          non_spend: nonSpend,
          purchases
        },
        {
          ...foldMetadata(fold),
          note: 'Category totals come from Fold. Refunds and similar are listed separately, not subtracted from spend.'
        }
      );
    }
  },

  {
    name: 'meos_finance_list_purchases',
    title: 'List logged purchases',
    description:
      'List items in the MeOS Stuff ledger, newest purchase first, with ROI progress and true cost per day. Filter by text or category. Retired items are excluded unless asked for.',
    inputSchema: {
      query: z.string().max(200).optional().describe('Match name, note or link.'),
      category: z.string().max(60).optional().describe('Category id or name, e.g. "gadgets".'),
      include_retired: z.boolean().optional(),
      ...CursorShape
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const state = await readObject<BelongingsState>(ctx, STATE_KEYS.belongings, DEFAULT_BELONGINGS);
      const q = String(args.query ?? '').trim().toLowerCase();
      const cat = String(args.category ?? '').trim().toLowerCase();
      const includeRetired = args.include_retired === true;

      let items = (state.items ?? []).filter((i) => includeRetired || !i.retired);
      if (cat) items = items.filter((i) => i.categoryID.toLowerCase() === cat || i.kind.toLowerCase() === cat);
      if (q) {
        items = items.filter((i) =>
          [i.name, i.note, i.link].some((v) => String(v ?? '').toLowerCase().includes(q))
        );
      }
      items.sort((a, b) => (b.boughtOn ?? '').localeCompare(a.boughtOn ?? '') || a.name.localeCompare(b.name));

      const page = paginate(items, args.limit, args.cursor);
      return ok(
        {
          ...page,
          items: page.items.map((i) => purchaseForClient(i))
        },
        { ledger: 'meos.belongings', total_matching: items.length }
      );
    }
  },

  {
    name: 'meos_finance_get_purchase',
    title: 'Get a purchase',
    description: 'Read one Stuff purchase with its full ROI maths.',
    inputSchema: { id: z.string().min(1) },
    scopes: ['read'],
    async handler(args, ctx) {
      const state = await readObject<BelongingsState>(ctx, STATE_KEYS.belongings, DEFAULT_BELONGINGS);
      const item = (state.items ?? []).find((i) => i.id === String(args.id).toLowerCase());
      if (!item) throw errors.notFound('Purchase');
      return ok(purchaseForClient(item));
    }
  },

  {
    name: 'meos_finance_add_purchase',
    title: 'Add a purchase',
    description:
      'Log something bought into the MeOS Stuff ledger. Price may be passed as rupees (number or string). The payback window is months; it is converted to the 30-day months MeOS stores. This is a financially significant write: it requires the write scope and confirm=true, and it syncs to the app.',
    inputSchema: {
      name: z.string().min(1).max(120),
      price_inr: z.union([z.number(), z.string()]).describe('Price in rupees, e.g. 2499 or "₹2,499".'),
      category: z.string().max(60).optional().describe('gadgets | clothes | home | books | wheels | other, or a custom category id.'),
      bought_on: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      roi_months: z.number().int().min(1).max(600).optional(),
      note: z.string().max(2000).optional(),
      link: z.string().max(2000).optional(),
      confirm: z.boolean().optional()
    },
    scopes: ['write'],
    confirmation: true,
    async handler(args, ctx) {
      const name = cleanText(args.name, 'name', 120);
      const pricePaise = parseRupees(args.price_inr, 'price_inr');
      if (pricePaise === undefined) throw errors.invalidInput('price_inr is required');
      const boughtOn = args.bought_on ?? todayKey();
      if (boughtOn > addDays(todayKey(), 1)) throw errors.invalidInput('bought_on cannot be in the future');

      const state = await readObject<BelongingsState>(ctx, STATE_KEYS.belongings, DEFAULT_BELONGINGS);
      const allowed = categoryIds(state);
      const category = String(args.category ?? 'other').trim().toLowerCase();
      if (!allowed.includes(category)) {
        throw errors.invalidInput(`category must be one of: ${allowed.join(', ')}`);
      }
      const months = args.roi_months ?? 36;
      const item: BelongingItem = {
        id: newId(),
        name,
        kind: kindForCategory(category),
        pricePaise,
        boughtOn: boughtOn.slice(0, 10),
        lifeDays: Math.max(1, months) * 30,
        note: String(args.note ?? '').slice(0, 2000),
        retired: false,
        photoBase64: '',
        categoryID: category,
        link: parseLink(args.link) ?? ''
      };

      await ctx.services.store.update<BelongingsState>(STATE_KEYS.belongings, (current) => {
        const base = current ?? DEFAULT_BELONGINGS;
        return { ...base, items: [item, ...(base.items ?? [])] };
      });
      return ok(purchaseForClient(item), { written: STATE_KEYS.belongings });
    }
  },

  {
    name: 'meos_finance_update_purchase',
    title: 'Update a purchase',
    description:
      'Change fields on a Stuff purchase. Only supplied fields are touched. Use retired=true for something you no longer own; prefer that over deleting. Requires confirm=true because it changes a financial record.',
    inputSchema: {
      id: z.string().min(1),
      name: z.string().min(1).max(120).optional(),
      price_inr: z.union([z.number(), z.string()]).optional(),
      category: z.string().max(60).optional(),
      bought_on: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      roi_months: z.number().int().min(1).max(600).optional(),
      note: z.string().max(2000).optional(),
      link: z.string().max(2000).optional(),
      retired: z.boolean().optional(),
      confirm: z.boolean().optional()
    },
    scopes: ['write'],
    confirmation: true,
    async handler(args, ctx) {
      const id = String(args.id).toLowerCase();
      const state = await readObject<BelongingsState>(ctx, STATE_KEYS.belongings, DEFAULT_BELONGINGS);
      const existing = (state.items ?? []).find((i) => i.id === id);
      if (!existing) throw errors.notFound('Purchase');

      const patch: Partial<BelongingItem> = {};
      if (args.name !== undefined) patch.name = cleanText(args.name, 'name', 120);
      if (args.price_inr !== undefined) patch.pricePaise = parseRupees(args.price_inr, 'price_inr');
      if (args.category !== undefined) {
        const cat = String(args.category).trim().toLowerCase();
        const allowed = categoryIds(state);
        if (!allowed.includes(cat)) throw errors.invalidInput(`category must be one of: ${allowed.join(', ')}`);
        patch.categoryID = cat;
        patch.kind = kindForCategory(cat);
      }
      if (args.bought_on !== undefined) patch.boughtOn = args.bought_on;
      if (args.roi_months !== undefined) patch.lifeDays = Math.max(1, args.roi_months) * 30;
      if (args.note !== undefined) patch.note = String(args.note).slice(0, 2000);
      if (args.link !== undefined) patch.link = parseLink(args.link) ?? '';
      if (args.retired !== undefined) patch.retired = Boolean(args.retired);

      if (Object.keys(patch).length === 0) throw errors.invalidInput('Nothing to update');

      let updated: BelongingItem | undefined;
      await ctx.services.store.update<BelongingsState>(STATE_KEYS.belongings, (current) => {
        const base = current ?? DEFAULT_BELONGINGS;
        const items = (base.items ?? []).map((i) => {
          if (i.id !== id) return i;
          updated = { ...i, ...patch };
          return updated;
        });
        return { ...base, items };
      });
      return ok(purchaseForClient(updated!), { written: STATE_KEYS.belongings });
    }
  },

  {
    name: 'meos_finance_delete_purchase',
    title: 'Delete a purchase',
    description:
      'Move a Stuff purchase to the MeOS recycle bin (30 days). It is recoverable from the app. Requires the destructive scope and confirm=true. Prefer retired=true when you simply no longer own the item.',
    inputSchema: { id: z.string().min(1), confirm: z.boolean().optional() },
    scopes: ['write', 'destructive'],
    destructive: true,
    async handler(args, ctx) {
      const id = String(args.id).toLowerCase();
      const state = await readObject<BelongingsState>(ctx, STATE_KEYS.belongings, DEFAULT_BELONGINGS);
      const item = (state.items ?? []).find((i) => i.id === id);
      if (!item) throw errors.notFound('Purchase');

      const entry = trashEntry({
        kind: 'belonging',
        itemID: item.id,
        title: item.name,
        subtitle: `₹${(item.pricePaise / 100).toFixed(0)} · ${item.categoryID}`,
        payload: item
      });
      await recycleAndRemove<BelongingsState>(ctx, {
        moduleKey: STATE_KEYS.belongings,
        entry,
        fallback: DEFAULT_BELONGINGS,
        remove: (items) => ({ ...items, items: (items.items ?? []).filter((i) => i.id !== id) })
      });
      return ok(
        { deleted: true, id, recycle_bin_entry: entry.id, recoverable_until_days: 30 },
        { written: [STATE_KEYS.trash, STATE_KEYS.belongings] }
      );
    }
  },

  {
    name: 'meos_finance_list_categories',
    title: 'List purchase categories',
    description: 'List the Stuff shelves: the six built-ins plus any custom categories the owner added.',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      const state = await readObject<BelongingsState>(ctx, STATE_KEYS.belongings, DEFAULT_BELONGINGS);
      const builtIns = BUILT_IN_CATEGORIES.map((id) => ({
        id,
        name: id.charAt(0).toUpperCase() + id.slice(1),
        built_in: true
      }));
      const custom = (state.categories ?? []).map((c) => ({
        id: c.id,
        name: c.name,
        built_in: false,
        default_roi_months: Math.max(1, Math.round(c.defaultLifeDays / 30))
      }));
      return ok({ categories: [...builtIns, ...custom] });
    }
  },

  {
    name: 'meos_finance_get_purchase_summary',
    title: 'Get ownership burn summary',
    description:
      'The Stuff summary the app shows: live item count, total spent, planned monthly ownership burn against take-home pay, and per-category totals. This is not a bank balance.',
    inputSchema: {},
    scopes: ['read'],
    async handler(_args, ctx) {
      const state = await readObject<BelongingsState>(ctx, STATE_KEYS.belongings, DEFAULT_BELONGINGS);
      const live = (state.items ?? []).filter((i) => !i.retired);
      const burn = monthlyBurnPaise(live);
      const salary = state.salaryPaise ?? 4_000_000;
      const byCategory = Object.values(
        live.reduce<Record<string, { id: string; count: number; spent_inr: number }>>((acc, item) => {
          const row = (acc[item.categoryID] ??= { id: item.categoryID, count: 0, spent_inr: 0 });
          row.count += 1;
          row.spent_inr += item.pricePaise / 100;
          return acc;
        }, {})
      );
      return ok({
        today: todayKey(),
        item_count: live.length,
        retired_count: (state.items ?? []).length - live.length,
        total_spent_inr: live.reduce((s, i) => s + i.pricePaise, 0) / 100,
        monthly_burn_inr: burn / 100,
        salary_inr: salary / 100,
        spend_health: spendHealth(burn, salary),
        by_category: byCategory
      });
    }
  }
];
