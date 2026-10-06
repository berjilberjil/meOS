import { error, json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { generateText, jsonSchema, tool } from 'ai';
import { resolveModel } from '$lib/server/ai';
import { mentorChatSystem } from '$lib/mentor';

/**
 * MeOS chat — the floating mentor. The client sends the conversation plus a
 * human-readable snapshot of the user's current data (fitness / journal /
 * profile). The model answers as their blunt mentor, grounded in that snapshot.
 * Read-only: it never touches the database.
 *
 * Returns JSON `{ reply }` (not a token stream). Netlify's function gateway
 * was 502-ing streamed responses; Flash-Lite is fast enough that a single
 * buffered reply stays well under the function timeout.
 */

type Msg = { role: 'user' | 'assistant'; content: string };

/** A tool declaration as the client sends it. */
interface ToolDecl {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
}

/**
 * Tools are declared by the CLIENT, not here.
 *
 * MeOS state is end-to-end encrypted, so this server cannot read a note even if
 * it wanted to — every tool has to run on the device that holds the key. Letting
 * the client ship the declarations alongside the request means the two halves
 * can never drift apart, and the tool set can change without a redeploy.
 *
 * None of these get an `execute`: the SDK therefore stops at the tool call and
 * hands it back, the app runs it locally, and the results come back as context
 * on the next turn. That keeps the whole loop inside one plain JSON round-trip —
 * no streaming, which is what was 502-ing on Netlify's gateway.
 */
function buildTools(raw: unknown) {
  if (!Array.isArray(raw) || !raw.length) return undefined;
  const entries = (raw as ToolDecl[])
    .filter((t) => t && typeof t.name === 'string' && t.name.length < 64)
    .slice(0, 24)
    .map((t) => [
      t.name,
      tool({
        description: String(t.description ?? '').slice(0, 800),
        inputSchema: jsonSchema(
          (t.parameters ?? { type: 'object', properties: {} }) as Parameters<typeof jsonSchema>[0]
        )
      })
    ]);
  return entries.length ? Object.fromEntries(entries) : undefined;
}

export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');

  const body = await request.json().catch(() => ({}));
  const rawMessages = Array.isArray(body.messages) ? body.messages : [];
  const context = String(body.context ?? '').slice(0, 8000);

  // Who the assistant should be (name / tone / style) — client-editable, bounded.
  const rawAgent = body.agent && typeof body.agent === 'object' ? body.agent : {};
  const persona = {
    name: typeof rawAgent.name === 'string' ? rawAgent.name.slice(0, 40) : undefined,
    tone: typeof rawAgent.tone === 'string' ? rawAgent.tone.slice(0, 400) : undefined,
    custom: typeof rawAgent.custom === 'string' ? rawAgent.custom.slice(0, 600) : undefined
  };

  // Keep only well-formed messages, cap history so the prompt stays bounded.
  const messages: Msg[] = rawMessages
    .filter((m: any) => (m?.role === 'user' || m?.role === 'assistant') && typeof m?.content === 'string')
    .slice(-24)
    .map((m: any) => ({ role: m.role, content: String(m.content).slice(0, 4000) }));

  if (!messages.length || messages[messages.length - 1].role !== 'user') {
    throw error(400, 'Nothing to answer');
  }

  let resolved;
  try {
    resolved = await resolveModel('chat', locals.user.id);
  } catch (e) {
    throw error(503, (e as Error)?.message ?? 'AI is not configured on the server');
  }

  const tools = buildTools(body.tools);
  const system = mentorChatSystem(context, persona, Boolean(tools));

  try {
    const result = await generateText({
      model: resolved.model,
      system,
      messages,
      ...(tools ? { tools } : {})
    });

    // The model wants to look something up. Hand the calls back; the app runs
    // them against the unlocked vault and posts again with the results.
    const calls = (result.toolCalls ?? []).map((c: Record<string, unknown>) => ({
      id: String(c.toolCallId ?? ''),
      name: String(c.toolName ?? ''),
      // v5 calls it `input`; tolerate `args` so an SDK bump can't silently
      // start sending empty arguments.
      args: (c.input ?? c.args ?? {}) as Record<string, unknown>
    }));

    return json({
      reply: result.text ?? '',
      toolCalls: calls,
      model: resolved.providerId
    });
  } catch (e) {
    throw error(502, `Could not answer that: ${(e as Error)?.message ?? 'try again'}`);
  }
};
