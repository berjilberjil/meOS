import { error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { streamText } from 'ai';
import { resolveModel } from '$lib/server/ai';
import { mentorChatSystem } from '$lib/mentor';

/**
 * MyOS chat — the floating mentor. The client sends the conversation plus a
 * human-readable snapshot of the user's current data (fitness / journal /
 * profile). The model answers as their blunt mentor, grounded in that snapshot.
 * Read-only: it never touches the database.
 */

type Msg = { role: 'user' | 'assistant'; content: string };

export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');

  const body = await request.json().catch(() => ({}));
  const rawMessages = Array.isArray(body.messages) ? body.messages : [];
  const context = String(body.context ?? '');

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

  try {
    const result = streamText({
      model: resolved.model,
      system: mentorChatSystem(context, persona),
      messages
    });
    // Stream the reply as plain text so the native client renders tokens as they
    // arrive. Streaming keeps the connection alive, so long replies no longer hit
    // the serverless function's response timeout (the old intermittent 502).
    return result.toTextStreamResponse();
  } catch (e) {
    throw error(502, `Could not answer that: ${(e as Error)?.message ?? 'try again'}`);
  }
};
