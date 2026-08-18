/**
 * Lists the models a given API key can actually reach, by hitting each provider's
 * own /models endpoint. This is what the Settings "Check" button calls: a 200 with
 * a non-empty list means the key is valid; a 4xx means it isn't. Server-side so the
 * mac app never handles the raw key or three providers' request quirks.
 */

export type ProviderId = 'gemini' | 'anthropic' | 'openai';
export const PROVIDERS: ProviderId[] = ['gemini', 'anthropic', 'openai'];

export interface CatalogResult {
  ok: boolean;
  models: string[];
  error?: string;
}

// Gemini returns many non-chat models (embeddings, tts, image, robotics, …).
const GEMINI_DROP = /embedding|aqa|tts|imagen|-image|robotics|computer-use/i;
// OpenAI's list is huge and mixed; keep chat/reasoning models only.
const OPENAI_KEEP = /^(gpt-|o\d|chatgpt)/i;
const OPENAI_DROP = /embedding|audio|realtime|image|tts|whisper|moderation|dall-e|transcribe|search|codex/i;

export async function listModels(provider: ProviderId, apiKey: string): Promise<CatalogResult> {
  try {
    switch (provider) {
      case 'gemini':
        return await gemini(apiKey);
      case 'anthropic':
        return await anthropic(apiKey);
      case 'openai':
        return await openai(apiKey);
      default:
        return { ok: false, models: [], error: 'Unknown provider' };
    }
  } catch (e) {
    return { ok: false, models: [], error: (e as Error)?.message ?? 'Network error' };
  }
}

async function gemini(key: string): Promise<CatalogResult> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key=${encodeURIComponent(key)}`;
  const res = await fetch(url);
  if (!res.ok) return { ok: false, models: [], error: await errText(res) };
  const data: any = await res.json();
  const models = (data.models ?? [])
    .filter((m: any) => (m.supportedGenerationMethods ?? []).includes('generateContent'))
    .map((m: any) => String(m.name).replace(/^models\//, ''))
    .filter((n: string) => n.startsWith('gemini') && !GEMINI_DROP.test(n));
  return { ok: true, models: dedupeSort(models) };
}

async function anthropic(key: string): Promise<CatalogResult> {
  const res = await fetch('https://api.anthropic.com/v1/models?limit=1000', {
    headers: { 'x-api-key': key, 'anthropic-version': '2023-06-01' }
  });
  if (!res.ok) return { ok: false, models: [], error: await errText(res) };
  const data: any = await res.json();
  const models = (data.data ?? []).map((m: any) => String(m.id));
  return { ok: true, models: dedupeSort(models) };
}

async function openai(key: string): Promise<CatalogResult> {
  const res = await fetch('https://api.openai.com/v1/models', {
    headers: { Authorization: `Bearer ${key}` }
  });
  if (!res.ok) return { ok: false, models: [], error: await errText(res) };
  const data: any = await res.json();
  const models = (data.data ?? [])
    .map((m: any) => String(m.id))
    .filter((id: string) => OPENAI_KEEP.test(id) && !OPENAI_DROP.test(id));
  return { ok: true, models: dedupeSort(models) };
}

async function errText(res: Response): Promise<string> {
  const t = await res.text().catch(() => '');
  try {
    const j = JSON.parse(t);
    return j?.error?.message ?? j?.message ?? `HTTP ${res.status}`;
  } catch {
    return `HTTP ${res.status}`;
  }
}

function dedupeSort(a: string[]): string[] {
  return Array.from(new Set(a)).sort();
}
