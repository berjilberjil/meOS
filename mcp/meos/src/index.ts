#!/usr/bin/env node
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { loadConfig } from './config/env.ts';
import { createLogger } from './services/logger.ts';
import { AuditLog } from './services/audit.ts';
import { IdempotencyStore } from './services/idempotency.ts';
import { ServiceRegistry } from './services/account.ts';
import { RateLimiter } from './auth/rateLimit.ts';
import { stdioClient } from './auth/authenticate.ts';
import { buildServer } from './server.ts';
import { createHttpServer } from './http.ts';

async function main(): Promise<void> {
  const config = loadConfig();
  const logger = createLogger(config.logLevel);
  const audit = new AuditLog();
  const idempotency = new IdempotencyStore();
  const registry = new ServiceRegistry(config.accounts, logger);
  const limiter = new RateLimiter(config.rateLimit.windowMs, config.rateLimit.max);

  if (config.transport === 'stdio') {
    const client = stdioClient(config);
    const services = registry.get(client.accountId);
    const server = buildServer({ client, services, logger, limiter, audit, idempotency });
    const transport = new StdioServerTransport();
    await server.connect(transport);
    logger.info('ready', { transport: 'stdio', client: client.id, scopes: client.scopes.join(','), tools: 'meos' });

    const shutdown = async () => {
      await server.close().catch(() => {});
      process.exit(0);
    };
    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);
    return;
  }

  const http = createHttpServer({ config, registry, limiter, logger, audit, idempotency });
  await new Promise<void>((resolve, reject) => {
    http.once('error', reject);
    http.listen(config.http.port, config.http.host, () => resolve());
  });
  const address = http.address();
  const port = typeof address === 'object' && address ? address.port : config.http.port;
  logger.info('ready', {
    transport: 'http',
    host: config.http.host,
    port,
    path: config.http.path,
    clients: String(config.clients.size)
  });
  if (!['127.0.0.1', '::1', 'localhost'].includes(config.http.host)) {
    logger.warn('http_remote_bind', {
      host: config.http.host,
      message: 'Bound beyond loopback. Terminate TLS in a trusted proxy and never expose this plain-HTTP listener.'
    });
  }

  const shutdown = () => {
    http.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 5000).unref();
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((err) => {
  const message = err instanceof Error ? err.message : String(err);
  process.stderr.write(`[meos-mcp] ${message}\n`);
  process.exit(1);
});
