import { describe, it, expect } from 'vitest';
import { tokenHash, unwrapDek, openState } from './mcpVault';
import { handleRpc, visibleNotes, type NoteRecord } from './mcpNotes';

// Produced by Swift CryptoKit with the same calls MCPToken.wrap and the vault
// use (HKDF<SHA256>, AES.GCM combined boxes), on fixed inputs. If the server
// opens these, it opens what the app makes.
const SWIFT = {
  token: 'meos_AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
  hash: '1898363596cbb8a7eaa981e21553f5db6b22599f19a98d28b23f94c342bb53b1',
  wrapped: 'VLBc4tgaKelaC8W+msaHa77tHuckPY+QqTFzrO77lXahCDFrkS8sTV0H0Uo39xKFRfD1CAkSVNazI3r8',
  notesCt:
    'IbGPxYSPOaH2aRLHckJMOafNpUa+4TXaE4HIFcU0xg6RGQ6vCtHovMBWS2/11X8KncemiwEIwwB4IRwIEuojM+ef4eG9cq5F6G7OBNS5dmD9fEzWcBn3IeMMOUlbvnAfTXh+OZtXhB5fGrIfLb9pVCZ/wwGV1+Bknt3RcGt8PBNpLGaJhTyk8zakNmh5ggWih6B2QMw3SSwd6rGYeJAuuzT0v+oyWrm58SXSLV9U/KHHwlJO8tQrkPiYdyRksR9UDYpIPMBo0Tu/oZdeVW8Ai5tz8x6y+AZlLPlMMtKM8frXvb1qCmU/+gzlPAipyLNukE4KLq2g5zHgouF2aKxgS9wO+HIF/81EJjO+gVVocJNe'
};

describe('mcpVault (against Swift output)', () => {
  it('hashes the token the way the app does', async () => {
    expect(await tokenHash(SWIFT.token)).toBe(SWIFT.hash);
  });

  it('unwraps the DEK and opens the notes envelope', async () => {
    const dek = await unwrapDek(SWIFT.token, SWIFT.wrapped);
    expect(dek).not.toBeNull();
    const notes = (await openState({ v: 1, ct: SWIFT.notesCt }, dek!, 'meos.notes')) as NoteRecord[];
    expect(notes.map((n) => n.id)).toEqual(['n1', 'n2']);
  });

  it('refuses a wrong token, a malformed token and a wrong state key', async () => {
    const other = 'meos_' + 'A'.repeat(43);
    expect(await unwrapDek(other, SWIFT.wrapped)).toBeNull();
    expect(await unwrapDek('not-a-token', SWIFT.wrapped)).toBeNull();
    const dek = (await unwrapDek(SWIFT.token, SWIFT.wrapped))!;
    await expect(openState({ v: 1, ct: SWIFT.notesCt }, dek, 'meos.journal')).rejects.toThrow();
  });
});

const NOTES: NoteRecord[] = visibleNotes([
  { id: 'a', title: 'Groceries', body: 'buy milk and eggs', createdAt: '2026-10-01', updatedAt: '2026-10-05' },
  { id: 'b', title: 'Ideas', body: 'Video about SIP and index funds', pinned: true, createdAt: '2026-10-01', updatedAt: '2026-10-02' },
  { id: 'c', title: 'Diary', body: 'private milk thoughts', locked: true, createdAt: '2026-10-01', updatedAt: '2026-10-09' }
]);
const load = async () => NOTES;
const call = (name: string, args: object = {}) =>
  handleRpc({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args } }, load);
const textOf = (r: unknown) => ((r as { result: { content: { text: string }[] } }).result.content[0].text);

describe('mcpNotes', () => {
  it('never exposes locked notes, and puts pinned first', () => {
    expect(NOTES.map((n) => n.id)).toEqual(['b', 'a']);
  });

  it('negotiates initialize without touching the notes', async () => {
    let loaded = false;
    const r = await handleRpc(
      { jsonrpc: '2.0', id: 0, method: 'initialize', params: { protocolVersion: '2025-03-26' } },
      async () => ((loaded = true), [])
    );
    expect((r as { result: { protocolVersion: string } }).result.protocolVersion).toBe('2025-03-26');
    expect(loaded).toBe(false);
  });

  it('answers notifications with nothing', async () => {
    expect(await handleRpc({ jsonrpc: '2.0', method: 'notifications/initialized' }, load)).toBeNull();
  });

  it('lists only read-only tools', async () => {
    const r = (await handleRpc({ jsonrpc: '2.0', id: 2, method: 'tools/list' }, load)) as {
      result: { tools: { name: string; annotations: { readOnlyHint: boolean } }[] };
    };
    expect(r.result.tools.map((t) => t.name)).toEqual(['list_notes', 'search_notes', 'read_note']);
    expect(r.result.tools.every((t) => t.annotations.readOnlyHint)).toBe(true);
  });

  it('searches every word, case-insensitively, and skips locked notes', async () => {
    expect(textOf(await call('search_notes', { query: 'MILK eggs' }))).toContain('Groceries');
    const milk = textOf(await call('search_notes', { query: 'milk' }));
    expect(milk).toContain('1 match.');
    expect(milk).not.toContain('Diary');
  });

  it('reads a note, but not a locked one', async () => {
    expect(textOf(await call('read_note', { id: 'b' }))).toContain('Video about SIP');
    const locked = (await call('read_note', { id: 'c' })) as { result: { isError?: boolean } };
    expect(locked.result.isError).toBe(true);
  });

  it('rejects unknown tools and methods', async () => {
    expect(await call('delete_note', { id: 'a' })).toHaveProperty('error.code', -32602);
    expect(await handleRpc({ jsonrpc: '2.0', id: 3, method: 'resources/list' }, load)).toHaveProperty('error.code', -32601);
  });
});
