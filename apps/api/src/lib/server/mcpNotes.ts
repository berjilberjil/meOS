/**
 * A read-only MCP server over a user's notes, as plain JSON-RPC.
 *
 * Hand-rolled rather than @modelcontextprotocol/sdk: the stateless subset of
 * Streamable HTTP is four methods, and the SDK (plus zod) would be parsed on
 * every cold isolate against a 10ms CPU budget. Every response is a single
 * JSON body; there is no session and no SSE stream.
 *
 * Read-only on purpose. Notes sync as one blob per user, so a write from here
 * racing an edit on the phone would let one silently overwrite the other.
 *
 * Locked notes are never exposed. Locking is the owner saying "not without me",
 * and an AI assistant is not them.
 */

export interface NoteRecord {
  id: string;
  title: string;
  body: string;
  pinned?: boolean;
  locked?: boolean;
  createdAt: string;
  updatedAt: string;
}

type Json = Record<string, unknown>;
interface RpcRequest {
  jsonrpc?: string;
  id?: string | number | null;
  method?: string;
  params?: Json;
}

const PROTOCOL_VERSIONS = ['2025-06-18', '2025-03-26', '2024-11-05'];

const TOOLS = [
  {
    name: 'list_notes',
    title: 'List notes',
    description:
      'List the user\'s MeOS notes, newest first (pinned on top), with a short preview. Use read_note for the full text.',
    inputSchema: {
      type: 'object',
      properties: {
        limit: { type: 'integer', minimum: 1, maximum: 100, description: 'How many to return (default 30).' },
        offset: { type: 'integer', minimum: 0, description: 'How many to skip, for paging.' }
      }
    },
    annotations: { readOnlyHint: true, openWorldHint: false }
  },
  {
    name: 'search_notes',
    title: 'Search notes',
    description:
      'Find MeOS notes whose title or text contains every word of the query (case-insensitive). Returns ids, titles and a snippet around the match.',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Words to look for.' },
        limit: { type: 'integer', minimum: 1, maximum: 50, description: 'Max results (default 15).' }
      },
      required: ['query']
    },
    annotations: { readOnlyHint: true, openWorldHint: false }
  },
  {
    name: 'read_note',
    title: 'Read a note',
    description: 'Return the full title and text of one MeOS note by its id.',
    inputSchema: {
      type: 'object',
      properties: { id: { type: 'string', description: 'The note id from list_notes or search_notes.' } },
      required: ['id']
    },
    annotations: { readOnlyHint: true, openWorldHint: false }
  }
];

/** What the tools may see: never locked notes, in the app's display order. */
export function visibleNotes(raw: unknown): NoteRecord[] {
  if (!Array.isArray(raw)) return [];
  return (raw as NoteRecord[])
    .filter((n) => n && typeof n.id === 'string' && !n.locked)
    .sort((a, b) => (a.pinned === b.pinned ? (a.updatedAt < b.updatedAt ? 1 : -1) : a.pinned ? -1 : 1));
}

function clampInt(v: unknown, def: number, min: number, max: number): number {
  const n = typeof v === 'number' && Number.isFinite(v) ? Math.floor(v) : def;
  return Math.min(max, Math.max(min, n));
}

function oneLine(s: string, max: number): string {
  const flat = s.replace(/\s+/g, ' ').trim();
  return flat.length > max ? flat.slice(0, max - 1) + '…' : flat;
}

function header(n: NoteRecord): string {
  return `- ${n.title.trim() || 'Untitled'}  (id: ${n.id}${n.pinned ? ', pinned' : ''}, updated ${n.updatedAt.slice(0, 10)})`;
}

function text(t: string, isError = false) {
  return { content: [{ type: 'text', text: t }], ...(isError ? { isError: true } : {}) };
}

function callTool(name: string, args: Json, notes: NoteRecord[]) {
  switch (name) {
    case 'list_notes': {
      const limit = clampInt(args.limit, 30, 1, 100);
      const offset = clampInt(args.offset, 0, 0, Number.MAX_SAFE_INTEGER);
      const page = notes.slice(offset, offset + limit);
      if (!page.length) return text(notes.length ? 'No more notes.' : 'No notes yet.');
      const lines = page.map((n) => `${header(n)}\n  ${oneLine(n.body, 140)}`);
      const more = offset + page.length < notes.length ? `\n\n${notes.length - offset - page.length} more — pass offset ${offset + page.length}.` : '';
      return text(`${notes.length} note${notes.length === 1 ? '' : 's'}.\n\n${lines.join('\n')}${more}`);
    }
    case 'search_notes': {
      const words = String(args.query ?? '').toLowerCase().split(/\s+/).filter(Boolean);
      if (!words.length) return text('Give a query to search for.', true);
      const limit = clampInt(args.limit, 15, 1, 50);
      const hits = notes.filter((n) => {
        const hay = `${n.title}\n${n.body}`.toLowerCase();
        return words.every((w) => hay.includes(w));
      });
      if (!hits.length) return text(`No notes match "${words.join(' ')}".`);
      const lines = hits.slice(0, limit).map((n) => {
        const at = n.body.toLowerCase().indexOf(words[0]);
        const from = Math.max(0, at - 60);
        const snip = at < 0 ? n.body.slice(0, 160) : (from ? '…' : '') + n.body.slice(from, at + 100);
        return `${header(n)}\n  ${oneLine(snip, 180)}`;
      });
      return text(`${hits.length} match${hits.length === 1 ? '' : 'es'}.\n\n${lines.join('\n')}`);
    }
    case 'read_note': {
      const id = String(args.id ?? '');
      const n = notes.find((x) => x.id === id);
      if (!n) return text(`No note with id ${id}.`, true);
      return text(`# ${n.title.trim() || 'Untitled'}\n(created ${n.createdAt.slice(0, 10)}, updated ${n.updatedAt.slice(0, 10)})\n\n${n.body}`);
    }
    default:
      return null;
  }
}

/**
 * Answer one JSON-RPC message. Returns null for notifications, which get no
 * reply. `loadNotes` is only called for tool calls, so `initialize` and
 * `tools/list` never pay for a decrypt.
 */
export async function handleRpc(msg: RpcRequest, loadNotes: () => Promise<NoteRecord[]>): Promise<Json | null> {
  if (msg.id === undefined || msg.id === null) return null; // notification
  const ok = (result: unknown) => ({ jsonrpc: '2.0', id: msg.id, result });
  const fail = (code: number, message: string) => ({ jsonrpc: '2.0', id: msg.id, error: { code, message } });

  switch (msg.method) {
    case 'initialize': {
      const asked = String(msg.params?.protocolVersion ?? '');
      return ok({
        protocolVersion: PROTOCOL_VERSIONS.includes(asked) ? asked : PROTOCOL_VERSIONS[0],
        capabilities: { tools: {} },
        serverInfo: { name: 'meos-notes', title: 'MeOS Notes', version: '1.0.0' },
        instructions:
          "Read-only access to the user's MeOS notes. Use search_notes to find something, list_notes to browse, read_note for full text. Locked notes are not available."
      });
    }
    case 'ping':
      return ok({});
    case 'tools/list':
      return ok({ tools: TOOLS });
    case 'tools/call': {
      const name = String(msg.params?.name ?? '');
      if (!TOOLS.some((t) => t.name === name)) return fail(-32602, `Unknown tool: ${name}`);
      const args = (msg.params?.arguments ?? {}) as Json;
      return ok(callTool(name, args, await loadNotes()));
    }
    default:
      return fail(-32601, `Method not found: ${msg.method}`);
  }
}
