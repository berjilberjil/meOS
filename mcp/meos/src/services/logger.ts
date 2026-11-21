/**
 * Structured logs go to stderr only. stdout belongs to the stdio MCP transport.
 *
 * Nothing here accepts a request body, a token, a vault passphrase or a record's
 * values. Tool handlers pass only metadata (tool name, client id, duration,
 * outcome, and the *names* of arguments) — never the arguments themselves.
 */
export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

const RANK: Record<LogLevel, number> = { debug: 10, info: 20, warn: 30, error: 40 };

export interface Logger {
  debug(event: string, fields?: Record<string, unknown>): void;
  info(event: string, fields?: Record<string, unknown>): void;
  warn(event: string, fields?: Record<string, unknown>): void;
  error(event: string, fields?: Record<string, unknown>): void;
}

const FORBIDDEN_FIELD = /^(args|arguments|params|payload)$|token|authorization|cookie|password|passphrase|secret|key|body|content|note|transaction|health|ciphertext|ct$/i;

/** Drop anything that could carry a secret or personal data. */
export function sanitizeFields(fields: Record<string, unknown> = {}): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(fields)) {
    if (FORBIDDEN_FIELD.test(k)) continue;
    if (v == null || ['string', 'number', 'boolean'].includes(typeof v)) out[k] = v;
    else if (Array.isArray(v)) out[k] = `[${v.length} items]`;
    else out[k] = '[object]';
  }
  return out;
}

export function createLogger(level: LogLevel = 'info'): Logger {
  const emit = (lvl: LogLevel, event: string, fields?: Record<string, unknown>) => {
    if (RANK[lvl] < RANK[level]) return;
    const line = JSON.stringify({
      ts: new Date().toISOString(),
      level: lvl,
      event,
      ...sanitizeFields(fields)
    });
    process.stderr.write(line + '\n');
  };
  return {
    debug: (e, f) => emit('debug', e, f),
    info: (e, f) => emit('info', e, f),
    warn: (e, f) => emit('warn', e, f),
    error: (e, f) => emit('error', e, f)
  };
}

export const silentLogger: Logger = {
  debug() {},
  info() {},
  warn() {},
  error() {}
};
