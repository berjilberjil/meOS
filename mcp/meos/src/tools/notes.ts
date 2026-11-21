import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { STATE_KEYS, type Note } from '../schemas/models.ts';
import { hasScope } from '../auth/scopes.ts';
import { errors } from '../utils/errors.ts';
import { ok } from '../utils/result.ts';
import { paginate } from '../utils/pagination.ts';
import { nowStamp } from '../utils/dates.ts';
import { newId } from '../utils/ids.ts';
import type { ToolDefinition } from './registry.ts';
import { canReadLockedNotes, noteForClient, readArray, recycleAndRemove, trashEntry } from './shared.ts';

/* ------------------------------------------------------------------ */
/* Block document (mirrors BlockDocument.swift)                        */
/* ------------------------------------------------------------------ */

interface TextSpan {
  text: string;
  marks: unknown[];
}

interface Block {
  id: string;
  type: string;
  spans: TextSpan[];
  checked?: boolean | null;
  level?: number | null;
  language?: string | null;
  src?: string | null;
  url?: string | null;
  linkTitle?: string | null;
  linkThumb?: string | null;
  linkDomain?: string | null;
}

function blockId(): string {
  return randomUUID().replace(/-/g, '').slice(0, 8).toLowerCase();
}

function paragraph(text: string): Block {
  return { id: blockId(), type: 'paragraph', spans: text ? [{ text, marks: [] }] : [] };
}

function blockPlainText(block: Block): string {
  if (block.type === 'linkCard') return block.url ?? block.spans.map((s) => s.text).join('');
  return block.spans.map((s) => s.text).join('');
}

/**
 * Rebuild rich content from the plain-text body without deleting attachments.
 * This is the same rule as `BlockDoc.merging(plainText:keepingAttachmentsOf:)`.
 */
function mergeBlockDoc(body: string, old: unknown): { blocks: Block[] } {
  const text = body.replace(/\r\n/g, '\n');
  const blocks: Block[] = text
    ? text.split('\n').map((line) => paragraph(line))
    : [paragraph('')];

  const oldBlocks = (old as { blocks?: Block[] } | null | undefined)?.blocks;
  const attachments = Array.isArray(oldBlocks)
    ? oldBlocks.filter((b) => b && (b.type === 'image' || b.type === 'linkCard'))
    : [];
  if (attachments.length) {
    const mirrored = new Set(attachments.map(blockPlainText).filter(Boolean));
    const filtered = blocks.filter((b) => !(b.type === 'paragraph' && mirrored.has(blockPlainText(b))));
    return { blocks: [...filtered, ...attachments] };
  }
  return { blocks };
}

/* ------------------------------------------------------------------ */
/* Tools                                                               */
/* ------------------------------------------------------------------ */

function matchesQuery(note: Note, q: string): boolean {
  const needle = q.toLowerCase();
  return note.title.toLowerCase().includes(needle) || note.body.toLowerCase().includes(needle);
}

function dateInRange(value: string, from?: string, to?: string): boolean {
  const day = (value ?? '').slice(0, 10);
  if (from && day < from) return false;
  if (to && day > to) return false;
  return true;
}

const DateFilter = {
  created_from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  created_to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  updated_from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  updated_to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional()
};

export const noteTools: ToolDefinition[] = [
  {
    name: 'meos_notes_list',
    title: 'List notes',
    description:
      'List notes newest-edited first, pinned first when asked. Locked notes appear as redacted unless the client has the secret scope. Filter by text and by created/updated dates.',
    inputSchema: {
      query: z.string().max(200).optional(),
      pinned_only: z.boolean().optional(),
      include_redacted: z.boolean().optional().describe('Include locked notes as redacted rows (default true).'),
      ...DateFilter,
      limit: z.number().int().min(1).max(100).optional(),
      cursor: z.string().optional()
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const notes = await readArray<Note>(ctx, STATE_KEYS.notes);
      const canLocked = canReadLockedNotes(ctx);
      const q = String(args.query ?? '').trim();
      let rows = notes.filter((n) => {
        if (n.locked && !canLocked && args.include_redacted === false) return false;
        if (args.pinned_only === true && !n.pinned) return false;
        if (!dateInRange(n.createdAt ?? '', args.created_from, args.created_to)) return false;
        if (!dateInRange(n.updatedAt ?? '', args.updated_from, args.updated_to)) return false;
        return !q || matchesQuery(n, q);
      });
      rows = rows.sort((a, b) => {
        if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
        return (b.updatedAt ?? '').localeCompare(a.updatedAt ?? '');
      });
      const page = paginate(rows, args.limit, args.cursor);
      return ok(
        {
          ...page,
          items: page.items.map((n) => noteForClient(n, canLocked)),
          total_matching: rows.length
        },
        {
          locked_notes: canLocked ? 'visible' : 'redacted (grant the secret scope to read them)',
          tags: 'MeOS notes have no tag model; search covers title and body.'
        }
      );
    }
  },

  {
    name: 'meos_notes_search',
    title: 'Search notes',
    description:
      'Search note title and body text, optionally within created/updated date ranges. Pinned notes are ranked first. Locked notes are never searched unless the client has the secret scope.',
    inputSchema: {
      query: z.string().min(1).max(200),
      ...DateFilter,
      limit: z.number().int().min(1).max(100).optional(),
      cursor: z.string().optional()
    },
    scopes: ['read'],
    async handler(args, ctx) {
      const notes = await readArray<Note>(ctx, STATE_KEYS.notes);
      const canLocked = canReadLockedNotes(ctx);
      const q = args.query.trim();
      const rows = notes
        .filter((n) => (!n.locked || canLocked) && (!q || matchesQuery(n, q)))
        .filter((n) => dateInRange(n.createdAt ?? '', args.created_from, args.created_to))
        .filter((n) => dateInRange(n.updatedAt ?? '', args.updated_from, args.updated_to))
        .sort((a, b) => {
          if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
          return (b.updatedAt ?? '').localeCompare(a.updatedAt ?? '');
        });
      const page = paginate(rows, args.limit, args.cursor);
      return ok({
        query: q,
        ...page,
        items: page.items.map((n) => noteForClient(n, canLocked)),
        total_matching: rows.length
      });
    }
  },

  {
    name: 'meos_notes_get',
    title: 'Get a note',
    description: 'Read one note by id. A locked note requires the secret scope; without it the note is returned redacted, never silently treated as missing.',
    inputSchema: { id: z.string().min(1) },
    scopes: ['read'],
    async handler(args, ctx) {
      const notes = await readArray<Note>(ctx, STATE_KEYS.notes);
      const note = notes.find((n) => n.id === String(args.id).toLowerCase());
      if (!note) throw errors.notFound('Note');
      return ok(noteForClient(note, canReadLockedNotes(ctx)));
    }
  },

  {
    name: 'meos_notes_create',
    title: 'Create a note',
    description:
      'Create a note. The plain-text body is mirrored into rich blocks exactly as the app does on a plain-text save. Set locked=true only with the secret scope, otherwise the creator could not read what it wrote.',
    inputSchema: {
      title: z.string().max(300).optional(),
      body: z.string().max(100000).optional(),
      pinned: z.boolean().optional(),
      locked: z.boolean().optional()
    },
    scopes: ['write'],
    async handler(args, ctx) {
      if (args.locked === true && !hasScope(ctx.client.scopes, 'secret')) {
        throw errors.forbidden('secret', 'Creating a locked note requires the secret scope.');
      }
      const title = String(args.title ?? '').slice(0, 300);
      const body = String(args.body ?? '');
      const stamp = nowStamp();
      const note: Note = {
        id: newId(),
        createdAt: stamp,
        updatedAt: stamp,
        title,
        body,
        pinned: args.pinned === true,
        locked: args.locked === true,
        content: mergeBlockDoc(body, null)
      };
      await ctx.services.store.update<Note[]>(STATE_KEYS.notes, (current) => [note, ...(current ?? [])]);
      return ok(noteForClient(note, true), { written: STATE_KEYS.notes });
    }
  },

  {
    name: 'meos_notes_update',
    title: 'Update a note',
    description:
      'Change a note\'s title and/or plain-text body. Rich attachments (images, link cards) are preserved; paragraph styling is rebuilt from the text, matching the app\'s own plain-text save path. Locked notes require the secret scope.',
    inputSchema: {
      id: z.string().min(1),
      title: z.string().max(300).optional(),
      body: z.string().max(100000).optional(),
      pinned: z.boolean().optional()
    },
    scopes: ['write'],
    async handler(args, ctx) {
      const id = String(args.id).toLowerCase();
      const canLocked = canReadLockedNotes(ctx);
      const notes = await readArray<Note>(ctx, STATE_KEYS.notes);
      const existing = notes.find((n) => n.id === id);
      if (!existing) throw errors.notFound('Note');
      if (existing.locked && !canLocked) throw errors.forbidden('secret', 'This note is locked.');

      const title = args.title !== undefined ? String(args.title).slice(0, 300) : existing.title;
      const body = args.body !== undefined ? String(args.body) : existing.body;
      if (title === existing.title && body === existing.body && args.pinned === undefined) {
        return ok(noteForClient(existing, canLocked), { unchanged: true });
      }

      let updated: Note | null = null;
      await ctx.services.store.update<Note[]>(STATE_KEYS.notes, (current) => {
        return (current ?? []).map((n) => {
          if (n.id !== id) return n;
          updated = {
            ...n,
            title,
            body,
            pinned: args.pinned !== undefined ? Boolean(args.pinned) : n.pinned,
            updatedAt: nowStamp(),
            content: args.body !== undefined ? mergeBlockDoc(body, n.content) : n.content
          };
          return updated;
        });
      });
      return ok(noteForClient(updated!, canLocked), { written: STATE_KEYS.notes });
    }
  },

  {
    name: 'meos_notes_pin',
    title: 'Pin or unpin a note',
    description: 'Pin or unpin a note. Pinned notes sort above unpinned ones in MeOS.',
    inputSchema: { id: z.string().min(1), pinned: z.boolean().optional() },
    scopes: ['write'],
    async handler(args, ctx) {
      const id = String(args.id).toLowerCase();
      let updated: Note | null = null;
      await ctx.services.store.update<Note[]>(STATE_KEYS.notes, (current) =>
        (current ?? []).map((n) => {
          if (n.id !== id) return n;
          updated = { ...n, pinned: args.pinned === undefined ? !n.pinned : Boolean(args.pinned) };
          return updated;
        })
      );
      if (!updated) throw errors.notFound('Note');
      return ok({ id, pinned: (updated as Note).pinned }, { written: STATE_KEYS.notes });
    }
  },

  {
    name: 'meos_notes_lock',
    title: 'Lock or unlock a note',
    description:
      'Toggle a note\'s locked flag. Locked notes hide their body in lists and from clients without the secret scope. Requires the secret scope because the operation itself reveals the note exists.',
    inputSchema: { id: z.string().min(1), locked: z.boolean().optional() },
    scopes: ['write', 'secret'],
    async handler(args, ctx) {
      const id = String(args.id).toLowerCase();
      let updated: Note | null = null;
      await ctx.services.store.update<Note[]>(STATE_KEYS.notes, (current) =>
        (current ?? []).map((n) => {
          if (n.id !== id) return n;
          updated = { ...n, locked: args.locked === undefined ? !n.locked : Boolean(args.locked) };
          return updated;
        })
      );
      if (!updated) throw errors.notFound('Note');
      return ok({ id, locked: (updated as Note).locked }, { written: STATE_KEYS.notes });
    }
  },

  {
    name: 'meos_notes_delete',
    title: 'Delete a note',
    description:
      'Move a note to the MeOS recycle bin (30 days), recoverable from the app. Requires destructive scope and confirm=true. The note is not destroyed here, and a locked note\'s payload stays in the bin.',
    inputSchema: { id: z.string().min(1), confirm: z.boolean().optional() },
    scopes: ['write', 'destructive'],
    destructive: true,
    async handler(args, ctx) {
      const id = String(args.id).toLowerCase();
      const notes = await readArray<Note>(ctx, STATE_KEYS.notes);
      const note = notes.find((n) => n.id === id);
      if (!note) throw errors.notFound('Note');
      const entry = trashEntry({
        kind: 'note',
        itemID: note.id,
        title: note.title,
        subtitle: note.locked ? 'Locked' : note.body.split(/\r?\n/).find((l) => l.trim())?.slice(0, 60) ?? '',
        payload: note
      });
      await recycleAndRemove<Note[]>(ctx, {
        moduleKey: STATE_KEYS.notes,
        entry,
        fallback: [],
        remove: (items) => items.filter((n) => n.id !== id)
      });
      return ok({ deleted: true, id, recycle_bin_entry: entry.id, recoverable_until_days: 30 }, { written: [STATE_KEYS.trash, STATE_KEYS.notes] });
    }
  }
];
