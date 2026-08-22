import { error, json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { reserveVoiceChars } from '$lib/server/voiceBudget';

/**
 * Catrine's voice.
 *
 * The client sends ONE sentence at a time and plays each clip as it arrives —
 * Aura synthesises a whole string before returning, so speaking a long reply in
 * one call would leave her silent for seconds.
 *
 * Audio only ever travels DOWN. Her ears are on-device (SFSpeechRecognizer with
 * `requiresOnDeviceRecognition`), so the microphone stream never reaches this
 * server, and this route is the only part of voice that touches the network.
 *
 * A 429 here is normal, not an error: the client falls back to the on-device
 * AVSpeechSynthesizer voice and keeps the conversation going.
 */

/** One sentence. Longer than this means the client failed to chunk. */
const MAX_TEXT = 400;

/**
 * Aura-2's speakers, verbatim from the model schema. Note this is NOT Aura-1's
 * list — `angus`, `perseus`, `helios` and `stella` do not exist here, and
 * passing one would fail synthesis and silently drop Catrine to the fallback
 * voice. Catrine defaults to `athena`.
 */
const SPEAKERS = new Set([
  'amalthea', 'andromeda', 'apollo', 'arcas', 'aries', 'asteria', 'athena',
  'atlas', 'aurora', 'callista', 'cora', 'cordelia', 'delia', 'draco',
  'electra', 'harmonia', 'helena', 'hera', 'hermes', 'hyperion', 'iris',
  'janus', 'juno', 'jupiter', 'luna', 'mars', 'minerva', 'neptune',
  'odysseus', 'ophelia', 'orion', 'orpheus', 'pandora', 'phoebe', 'pluto',
  'saturn', 'thalia', 'theia', 'vesta', 'zeus'
]);

/** The Workers AI binding, cast at the call site the way `hooks.server.ts` casts DB. */
type WorkersAI = {
  run: (
    model: string,
    input: Record<string, unknown>,
    opts?: { returnRawResponse?: boolean }
  ) => Promise<Response>;
};

export const POST: RequestHandler = async ({ request, locals, platform }) => {
  if (!locals.user) throw error(401, 'Not logged in');

  const body = await request.json().catch(() => ({}));
  const text = String(body.text ?? '').trim().slice(0, MAX_TEXT);
  if (!text) throw error(400, 'Nothing to say');

  const rawSpeaker = String(body.speaker ?? 'athena');
  const speaker = SPEAKERS.has(rawSpeaker) ? rawSpeaker : 'athena';

  const budget = await reserveVoiceChars(locals.user.id, text.length);
  if (!budget.allowed) {
    return json({ code: 'voice_budget_exhausted', remaining: budget.remaining }, { status: 429 });
  }

  const ai = (platform as { env?: { AI?: WorkersAI } } | undefined)?.env?.AI;
  if (!ai) throw error(503, 'Voice is not configured on the server');

  try {
    const resp = await ai.run(
      '@cf/deepgram/aura-2-en',
      { text, speaker, encoding: 'mp3' },
      { returnRawResponse: true }
    );
    return new Response(resp.body, {
      status: 200,
      headers: {
        'Content-Type': 'audio/mpeg',
        'Cache-Control': 'no-store',
        'X-Voice-Remaining': String(budget.remaining)
      }
    });
  } catch (e) {
    // Cloudflare's own neuron allowance ran out (3036) or capacity is short
    // (3040). Either way the client should fall back, not show an error.
    return json({ code: 'voice_unavailable', detail: (e as Error)?.message ?? '' }, { status: 429 });
  }
};
