import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import type { ClientConfig, RuntimeConfig } from './config/types.ts';
import type { ServiceRegistry } from './services/account.ts';
import type { Logger } from './services/logger.ts';
import type { RateLimiter } from './auth/rateLimit.ts';
import { AuditLog } from './services/audit.ts';
import type { IdempotencyStore } from './services/idempotency.ts';
import { authenticateRequest } from './auth/authenticate.ts';
import { DynamicClientRegistry } from './auth/dynamicClients.ts';
import { isMeosMcpError } from './utils/errors.ts';
import { buildServer } from './server.ts';
import { OAuthStore } from './oauth/store.ts';
import { handleOAuthRequest, clientIp } from './oauth/routes.ts';
import { handleAdminRequest } from './oauth/admin.ts';

export interface HttpServerOptions {
  config: RuntimeConfig;
  registry: ServiceRegistry;
  limiter: RateLimiter;
  logger: Logger;
  audit?: AuditLog;
  idempotency?: IdempotencyStore;
}

class BodyError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function readJsonBody(req: IncomingMessage, maxBytes: number): Promise<unknown> {
  return new Promise((resolve, reject) => {
    let size = 0;
    let aborted = false;
    const chunks: Buffer[] = [];

    req.on('data', (chunk: Buffer) => {
      if (aborted) return;
      size += chunk.length;
      if (size > maxBytes) {
        aborted = true;
        reject(new BodyError(413, 'Request body is too large.'));
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (aborted) return;
      if (!chunks.length) return resolve(undefined);
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        reject(new BodyError(400, 'Request body must be valid JSON.'));
      }
    });
    req.on('error', () => reject(new BodyError(400, 'Request body could not be read.')));
  });
}

function baseHeaders(): Record<string, string> {
  return {
    'Cache-Control': 'no-store',
    Pragma: 'no-cache',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'X-Robots-Tag': 'noindex, nofollow',
    'Referrer-Policy': 'no-referrer',
    'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), payment=()'
  };
}

function sendJson(res: ServerResponse, status: number, body: unknown, extra: Record<string, string> = {}): void {
  const text = JSON.stringify(body);
  res.writeHead(status, {
    ...baseHeaders(),
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(text),
    ...extra
  });
  res.end(text);
}

function sendMcpError(
  res: ServerResponse,
  status: number,
  code: string,
  message: string,
  extra: Record<string, string> = {}
): void {
  sendJson(res, status, { error: { code, message } }, extra);
}

function corsOrigin(req: IncomingMessage): string | null {
  const origin = req.headers.origin;
  if (!origin) return null;
  const allowed = (process.env.MEOS_MCP_CORS_ORIGINS ?? '')
    .split(/[\s,]+/)
    .map((s) => s.trim())
    .filter(Boolean);
  return allowed.includes(origin) ? origin : null;
}

function corsHeaders(req: IncomingMessage): Record<string, string> {
  const origin = corsOrigin(req);
  if (!origin) return {};
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, content-type, mcp-protocol-version, mcp-session-id, last-event-id',
    'Access-Control-Expose-Headers': 'www-authenticate, mcp-session-id',
    'Access-Control-Max-Age': '600',
    Vary: 'Origin'
  };
}

function authChallenge(config: RuntimeConfig): string {
  const base = 'Bearer realm="meos"';
  if (!config.oauth) return base;
  const scope = 'meos.profile.read meos.finance.read meos.health.read meos.notes.read meos.tasks.read meos.calendar.read';
  return `${base}, resource_metadata="${config.oauth.issuer}/.well-known/oauth-protected-resource", scope="${scope}"`;
}

export function createHttpServer(options: HttpServerOptions): Server {
  const { config, registry, limiter, logger } = options;
  const oauthStore = config.oauth ? new OAuthStore(config.oauth.storePath || undefined) : undefined;
  // If OAuth is configured, an audit sink is mandatory. Never silently run
  // OAuth without the trail that the dashboard and incident response need.
  const audit = options.audit ?? (config.oauth ? new AuditLog() : undefined);
  // App-managed tokens are stored (hashed) in the encrypted `meos.mcp`
  // document. The registry keeps a 10s cache so revocation lands quickly
  // without a state fetch on every request.
  const dynamicClients = new DynamicClientRegistry(config, registry, logger);

  return createServer(async (req, res) => {
    const started = Date.now();
    let client: ClientConfig | null = null;
    const finish = () => {
      logger.info('http_request', {
        method: req.method,
        path: (req.url ?? '').split('?')[0],
        status: res.statusCode,
        ms: Date.now() - started,
        client: client?.id ?? 'anonymous'
      });
    };
    res.on('finish', finish);

    if (config.oauth?.issuer.startsWith('https://')) {
      res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
    }

    try {
      const url = new URL(req.url ?? '/', config.oauth?.issuer ?? `http://${req.headers.host ?? 'localhost'}`);

      if (url.pathname === '/healthz') {
        if (req.method !== 'GET') return sendMcpError(res, 405, 'method_not_allowed', 'Use GET.');
        return sendJson(res, 200, { ok: true, service: 'meos-mcp', oauth: Boolean(config.oauth) });
      }

      // OAuth metadata, consent, token, registration + admin dashboard.
      if (config.oauth && oauthStore && audit) {
        const deps = { config: config.oauth, store: oauthStore, audit, rateLimit: (key: string, max: number, windowMs: number) => limiter.takeN(key, max, windowMs) };
        if (await handleOAuthRequest(req, res, url, deps)) return;
        if (await handleAdminRequest(req, res, url, deps)) return;
      }

      if (url.pathname !== config.http.path) {
        return sendMcpError(res, 404, 'not_found', 'Not found.');
      }

      if (req.method === 'OPTIONS') {
        res.writeHead(204, {
          ...baseHeaders(),
          ...corsHeaders(req),
          Allow: 'POST, OPTIONS'
        });
        return res.end();
      }
      if (req.method !== 'POST') {
        res.setHeader('Allow', 'POST');
        return sendMcpError(
          res,
          405,
          'method_not_allowed',
          'This gateway is stateless: use POST for MCP requests. Server-sent GET streams are disabled.'
        );
      }

      if (corsOrigin(req) === null && req.headers.origin) {
        return sendMcpError(res, 403, 'origin_not_allowed', 'This browser origin is not allowed to call the MCP endpoint.');
      }

      try {
        client = await authenticateRequest(config, req.headers.authorization, oauthStore, dynamicClients);
      } catch (e) {
        const message = isMeosMcpError(e) ? e.message : 'The MCP request is not authenticated.';
        audit?.record({
          event: 'mcp_auth',
          outcome: 'denied',
          ip: clientIp(req),
          userAgent: req.headers['user-agent'],
          meta: { reason: 'bearer' }
        });
        return sendMcpError(res, 401, 'unauthenticated', message, {
          'WWW-Authenticate': authChallenge(config),
          ...corsHeaders(req)
        });
      }

      limiter.take(client.id);

      const body = await readJsonBody(req, config.http.maxBodyBytes);
      if (body == null) {
        return sendMcpError(res, 400, 'invalid_request', 'An MCP JSON-RPC request body is required.');
      }

      const services = registry.get(client.accountId);
      const mcp = buildServer({
        client,
        services,
        logger,
        limiter,
        enforceRateLimit: false,
        audit,
        idempotency: options.idempotency
      });
      const transport = new StreamableHTTPServerTransport({
        sessionIdGenerator: undefined,
        enableJsonResponse: true
      });

      res.on('close', () => {
        void mcp.close().catch(() => {});
      });

      // Set before the SDK writes its response; writeHead merges these.
      for (const [k, v] of Object.entries({ ...baseHeaders(), ...corsHeaders(req) })) {
        res.setHeader(k, v);
      }

      await mcp.connect(transport);
      await transport.handleRequest(req, res, body);
    } catch (e) {
      if (res.headersSent) {
        res.destroy();
        return;
      }
      if (e instanceof BodyError) {
        return sendMcpError(res, e.status, e.status === 413 ? 'payload_too_large' : 'parse_error', e.message, corsHeaders(req));
      }
      if (isMeosMcpError(e)) {
        const extra: Record<string, string> = { ...corsHeaders(req) };
        if (e.status === 401) extra['WWW-Authenticate'] = authChallenge(config);
        return sendMcpError(res, e.status ?? 400, e.code, e.message, extra);
      }
      logger.error('http_error', { path: (req.url ?? '').split('?')[0] });
      return sendMcpError(res, 500, 'internal_error', 'The MeOS MCP server hit an unexpected error.', corsHeaders(req));
    }
  });
}
