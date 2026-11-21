import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import type { ClientConfig, RuntimeConfig } from './config/types.ts';
import type { ServiceRegistry } from './services/account.ts';
import type { Logger } from './services/logger.ts';
import type { RateLimiter } from './auth/rateLimit.ts';
import { authenticateBearer } from './auth/authenticate.ts';
import { isMeosMcpError } from './utils/errors.ts';
import { buildServer } from './server.ts';

export interface HttpServerOptions {
  config: RuntimeConfig;
  registry: ServiceRegistry;
  limiter: RateLimiter;
  logger: Logger;
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

function sendJson(res: ServerResponse, status: number, body: unknown): void {
  const text = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(text),
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff'
  });
  res.end(text);
}

function sendMcpError(res: ServerResponse, status: number, code: string, message: string): void {
  sendJson(res, status, { error: { code, message } });
}

export function createHttpServer(options: HttpServerOptions): Server {
  const { config, registry, limiter, logger } = options;

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

    try {
      const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`);

      if (url.pathname === '/healthz') {
        if (req.method !== 'GET') return sendMcpError(res, 405, 'method_not_allowed', 'Use GET.');
        return sendJson(res, 200, { ok: true, service: 'meos-mcp' });
      }

      if (url.pathname !== config.http.path) {
        return sendMcpError(res, 404, 'not_found', 'Not found.');
      }

      if (req.method === 'OPTIONS') {
        res.writeHead(204, { Allow: 'POST', 'Cache-Control': 'no-store' });
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

      client = authenticateBearer(config, req.headers.authorization);
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
        enforceRateLimit: false
      });
      const transport = new StreamableHTTPServerTransport({
        sessionIdGenerator: undefined,
        enableJsonResponse: true
      });

      res.on('close', () => {
        void mcp.close().catch(() => {});
      });

      await mcp.connect(transport);
      await transport.handleRequest(req, res, body);
    } catch (e) {
      if (res.headersSent) {
        res.destroy();
        return;
      }
      if (e instanceof BodyError) {
        return sendMcpError(res, e.status, e.status === 413 ? 'payload_too_large' : 'parse_error', e.message);
      }
      if (isMeosMcpError(e)) {
        if (e.status === 401) res.setHeader('WWW-Authenticate', 'Bearer realm="meos"');
        return sendMcpError(res, e.status ?? 400, e.code, e.message);
      }
      logger.error('http_error', { path: (req.url ?? '').split('?')[0] });
      return sendMcpError(res, 500, 'internal_error', 'The MeOS MCP server hit an unexpected error.');
    }
  });
}
