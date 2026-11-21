import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js';

export type ResponseMetadata = Record<string, unknown>;

/**
 * Every tool answers with the same envelope. `structuredContent` is what an
 * agent should branch on; the text block is the same document for clients that
 * only render text. `metadata.source` is always MeOS, so multi-server agents can
 * attribute a fact without guessing.
 */
export function ok(data: unknown, metadata: ResponseMetadata = {}): CallToolResult {
  const payload = {
    success: true as const,
    data,
    metadata: {
      source: 'MeOS' as const,
      retrieved_at: new Date().toISOString(),
      ...metadata
    }
  };
  return {
    structuredContent: payload,
    content: [{ type: 'text' as const, text: JSON.stringify(payload, null, 2) }]
  };
}

export function fail(code: string, message: string, hint?: string, metadata: ResponseMetadata = {}): CallToolResult {
  const payload = {
    success: false as const,
    error: { code, message, ...(hint ? { hint } : {}) },
    metadata: {
      source: 'MeOS' as const,
      retrieved_at: new Date().toISOString(),
      ...metadata
    }
  };
  return {
    isError: true,
    structuredContent: payload,
    content: [{ type: 'text' as const, text: JSON.stringify(payload, null, 2) }]
  };
}

export function unsupported(feature: string, reason: string): CallToolResult {
  return fail('unsupported', `${feature} is not available in this MeOS build.`, reason);
}
