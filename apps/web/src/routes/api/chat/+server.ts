import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';
import { generateText } from 'ai';
import { createGoogleGenerativeAI } from '@ai-sdk/google';
import { mentorChatSystem } from '$lib/mentor';

/**
 * MyOS chat — the floating mentor. The client sends the conversation plus a
 * human-readable snapshot of the user's current data (finance / fitness / journal /
 * profile). The model answers as their blunt mentor, grounded in that snapshot.
 * Read-only: it never touches the database.
 */

type Msg = { role: 'user' | 'assistant'; content: string };

export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) throw error(401, 'Not logged in');
  const apiKey = env.GEMINI_API_KEY;
  if (!apiKey) throw error(503, 'AI is not configured on the server');

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

  try {
    const google = createGoogleGenerativeAI({ apiKey });
    const { text } = await generateText({
      model: google(env.GEMINI_MODEL ?? 'gemini-2.5-flash'),
      system: mentorChatSystem(context, persona),
      messages
    });
    return json({ reply: text });
  } catch (e) {
    throw error(502, `Could not answer that: ${(e as Error)?.message ?? 'try again'}`);
  }
};
