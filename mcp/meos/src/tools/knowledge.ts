import { z } from 'zod';
import { STATE_KEYS, type WatchItem } from '../schemas/models.ts';
import { errors } from '../utils/errors.ts';
import { ok } from '../utils/result.ts';
import { paginate } from '../utils/pagination.ts';
import { nowStamp } from '../utils/dates.ts';
import { newId } from '../utils/ids.ts';
import type { ToolDefinition } from './registry.ts';
import { cleanText, readArray, recycleAndRemove, trashEntry } from './shared.ts';

const CATEGORIES = ['finance', 'business', 'investing', 'economy', 'content', 'mindset', 'tech', 'other'] as const;

function parseUrl(raw: string): { url: string; videoId: string } {
  let url: URL;
  try {
    url = new URL(raw.trim());
  } catch {
    throw errors.invalidInput('url must be a valid http(s) URL');
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') throw errors.invalidInput('url must be http(s)');
  let videoId = '';
  if (/(^|\.)youtu\.be$/i.test(url.hostname)) videoId = url.pathname.slice(1).split('/')[0] ?? '';
  else if (/youtube\.com$/i.test(url.hostname.replace(/^www\./, ''))) videoId = url.searchParams.get('v') ?? '';
  return { url: url.toString(), videoId };
}

function view(item: WatchItem) {
  return {
    id: item.id,
    url: item.url,
    video_id: item.videoId,
    title: item.title,
    channel: item.channel,
    category: item.category,
    takeaway: item.takeaway,
    watched: item.watched,
    added_at: item.addedAt
  };
}

export const knowledgeTools: ToolDefinition[] = [
  {
    name: 'meos_knowledge_list_videos',
    title: 'List learning videos',
    description:
      'List the MeOS learning log (YouTube links plus the owner\'s takeaway). Filter by category, watched state or text.',
    inputSchema: {
      query: z.string().max(200).optional(),
      category: z.enum(CATEGORIES).optional(),
      watched: z.boolean().optional(),
      limit: z.number().int().min(1).max(100).optional(),
      cursor: z.string().optional()
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const items = await readArray<WatchItem>(ctx, STATE_KEYS.watch);
      const q = String(args.query ?? '').toLowerCase();
      const rows = items
        .filter((i) => (args.category ? i.category === args.category : true))
        .filter((i) => (args.watched === undefined ? true : Boolean(i.watched) === args.watched))
        .filter((i) => !q || [i.title, i.channel, i.takeaway].some((v) => String(v ?? '').toLowerCase().includes(q)))
        .sort((a, b) => (b.addedAt ?? '').localeCompare(a.addedAt ?? ''));
      const page = paginate(rows, args.limit, args.cursor);
      return ok({ ...page, items: page.items.map(view), total_matching: rows.length });
    }
  },

  {
    name: 'meos_knowledge_add_video',
    title: 'Add a learning video',
    description:
      'Add a YouTube link to the learning log with an optional takeaway. MeOS does not fetch metadata server-side here, so title is required.',
    inputSchema: {
      url: z.string().min(1).max(2000),
      title: z.string().min(1).max(300),
      channel: z.string().max(120).optional(),
      category: z.enum(CATEGORIES).optional(),
      takeaway: z.string().max(5000).optional(),
      watched: z.boolean().optional()
    },
    scopes: ['write'],
    async handler(args, ctx) {
      const { url, videoId } = parseUrl(args.url);
      const item: WatchItem = {
        id: newId(),
        url,
        videoId,
        title: cleanText(args.title, 'title', 300),
        channel: String(args.channel ?? '').slice(0, 120),
        thumbUrl: videoId ? `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg` : '',
        addedAt: nowStamp(),
        category: args.category ?? 'other',
        takeaway: String(args.takeaway ?? '').slice(0, 5000),
        watched: args.watched === true
      };
      await ctx.services.store.update<WatchItem[]>(STATE_KEYS.watch, (current) => [item, ...(current ?? [])]);
      return ok(view(item), { written: STATE_KEYS.watch });
    }
  },

  {
    name: 'meos_knowledge_update_video',
    title: 'Update a learning video',
    description: 'Mark a video watched, edit the takeaway, or change its category. Only supplied fields change.',
    inputSchema: {
      id: z.string().min(1),
      watched: z.boolean().optional(),
      takeaway: z.string().max(5000).optional(),
      category: z.enum(CATEGORIES).optional(),
      title: z.string().min(1).max(300).optional()
    },
    scopes: ['write'],
    async handler(args, ctx) {
      const id = String(args.id).toLowerCase();
      if (args.watched === undefined && args.takeaway === undefined && args.category === undefined && args.title === undefined) {
        throw errors.invalidInput('Nothing to update');
      }
      let updated: WatchItem | null = null;
      await ctx.services.store.update<WatchItem[]>(STATE_KEYS.watch, (current) =>
        (current ?? []).map((i) => {
          if (i.id !== id) return i;
          updated = {
            ...i,
            watched: args.watched !== undefined ? Boolean(args.watched) : i.watched,
            takeaway: args.takeaway !== undefined ? String(args.takeaway).slice(0, 5000) : i.takeaway,
            category: args.category ?? i.category,
            title: args.title !== undefined ? cleanText(args.title, 'title', 300) : i.title
          };
          return updated;
        })
      );
      if (!updated) throw errors.notFound('Video');
      return ok(view(updated), { written: STATE_KEYS.watch });
    }
  },

  {
    name: 'meos_knowledge_delete_video',
    title: 'Delete a learning video',
    description: 'Move a learning-log video to the recycle bin (30 days). Requires destructive scope and confirm=true.',
    inputSchema: { id: z.string().min(1), confirm: z.boolean().optional() },
    scopes: ['write', 'destructive'],
    destructive: true,
    async handler(args, ctx) {
      const id = String(args.id).toLowerCase();
      const items = await readArray<WatchItem>(ctx, STATE_KEYS.watch);
      const item = items.find((i) => i.id === id);
      if (!item) throw errors.notFound('Video');
      const entry = trashEntry({ kind: 'watch', itemID: item.id, title: item.title, subtitle: item.channel, payload: item });
      await recycleAndRemove<WatchItem[]>(ctx, {
        moduleKey: STATE_KEYS.watch,
        entry,
        fallback: [],
        remove: (all) => all.filter((i) => i.id !== id)
      });
      return ok({ deleted: true, id, recycle_bin_entry: entry.id, recoverable_until_days: 30 }, {
        written: [STATE_KEYS.trash, STATE_KEYS.watch]
      });
    }
  }
];
