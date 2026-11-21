import test from 'node:test';
import assert from 'node:assert/strict';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { createHarness, testConfig } from './support/harness.ts';
import { createHttpServer } from '../src/http.ts';
import { ServiceRegistry } from '../src/services/account.ts';
import { RateLimiter } from '../src/auth/rateLimit.ts';
import { silentLogger } from '../src/services/logger.ts';
import { hashToken } from '../src/config/env.ts';
import type { AccountConfig, ClientConfig } from '../src/config/types.ts';

test('Streamable HTTP supports initialize, tool discovery and a tool call', async () => {
  const h = await createHarness();
  const account: AccountConfig = {
    id: 'a',
    baseUrl: h.baseUrl,
    username: h.accounts.a.username,
    password: h.accounts.a.password,
    vaultPassphrase: h.accounts.a.passphrase,
    requestTimeoutMs: 5000
  };
  const clientConfig: ClientConfig = {
    id: 'http-client',
    tokenHash: hashToken('http-secret'),
    scopes: ['read', 'health'],
    accountId: 'a'
  };
  const config = testConfig({
    accounts: new Map([['a', account]]),
    clients: new Map([[clientConfig.id, clientConfig]])
  });
  const http = createHttpServer({
    config,
    registry: new ServiceRegistry(config.accounts, silentLogger),
    limiter: new RateLimiter(60_000, 1000),
    logger: silentLogger
  });
  await new Promise<void>((resolve) => http.listen(0, '127.0.0.1', resolve));
  const address = http.address();
  const port = typeof address === 'object' && address ? address.port : 0;
  const base = `http://127.0.0.1:${port}`;

  try {
    const transport = new StreamableHTTPClientTransport(new URL(`${base}/mcp`), {
      requestInit: { headers: { Authorization: 'Bearer http-secret' } }
    });
    const client = new Client({ name: 'meos-test', version: '1.0.0' });
    await client.connect(transport);

    const tools = await client.listTools();
    assert.ok(tools.tools.length > 40);
    assert.ok(tools.tools.some((t) => t.name === 'meos_get_profile'));
    assert.ok(tools.tools.some((t) => t.name === 'meos_finance_get_summary'));
    assert.ok(tools.tools.some((t) => t.name === 'meos_diet_get_context'));

    const result: any = await client.callTool({ name: 'meos_get_profile', arguments: {} });
    assert.equal(result.structuredContent.success, true);
    assert.equal(result.structuredContent.data.name, 'Berjil');

    const resources = await client.listResources();
    assert.ok(resources.resources.some((r) => r.uri === 'meos://profile'));
    const read = await client.readResource({ uri: 'meos://profile' });
    assert.equal(read.contents.length, 1);

    const prompts = await client.listPrompts();
    assert.ok(prompts.prompts.some((p) => p.name === 'meos_daily_briefing'));

    await client.close();
  } finally {
    await new Promise<void>((resolve) => http.close(() => resolve()));
    await h.close();
  }
});

test('HTTP rejects unauthenticated requests and non-POST MCP requests', async () => {
  const h = await createHarness();
  const account: AccountConfig = {
    id: 'a',
    baseUrl: h.baseUrl,
    username: h.accounts.a.username,
    password: h.accounts.a.password,
    vaultPassphrase: h.accounts.a.passphrase,
    requestTimeoutMs: 5000
  };
  const clientConfig: ClientConfig = {
    id: 'http-client',
    tokenHash: hashToken('http-secret'),
    scopes: ['read'],
    accountId: 'a'
  };
  const config = testConfig({
    accounts: new Map([['a', account]]),
    clients: new Map([[clientConfig.id, clientConfig]])
  });
  const http = createHttpServer({
    config,
    registry: new ServiceRegistry(config.accounts, silentLogger),
    limiter: new RateLimiter(60_000, 1000),
    logger: silentLogger
  });
  await new Promise<void>((resolve) => http.listen(0, '127.0.0.1', resolve));
  const address = http.address();
  const port = typeof address === 'object' && address ? address.port : 0;
  const base = `http://127.0.0.1:${port}`;

  try {
    const health = await fetch(`${base}/healthz`);
    assert.equal(health.status, 200);

    const noAuth = await fetch(`${base}/mcp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} })
    });
    assert.equal(noAuth.status, 401);

    const badToken = await fetch(`${base}/mcp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer nope' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} })
    });
    assert.equal(badToken.status, 401);

    const get = await fetch(`${base}/mcp`, { headers: { Authorization: 'Bearer http-secret' } });
    assert.equal(get.status, 405);

    const wrongPath = await fetch(`${base}/other`, { headers: { Authorization: 'Bearer http-secret' } });
    assert.equal(wrongPath.status, 404);
  } finally {
    await new Promise<void>((resolve) => http.close(() => resolve()));
    await h.close();
  }
});

test('HTTP caps request bodies', async () => {
  const h = await createHarness();
  const account: AccountConfig = {
    id: 'a',
    baseUrl: h.baseUrl,
    username: h.accounts.a.username,
    password: h.accounts.a.password,
    vaultPassphrase: h.accounts.a.passphrase,
    requestTimeoutMs: 5000
  };
  const clientConfig: ClientConfig = {
    id: 'http-client',
    tokenHash: hashToken('http-secret'),
    scopes: ['read'],
    accountId: 'a'
  };
  const config = testConfig({
    accounts: new Map([['a', account]]),
    clients: new Map([[clientConfig.id, clientConfig]]),
    http: { host: '127.0.0.1', port: 0, path: '/mcp', maxBodyBytes: 1024 }
  });
  const http = createHttpServer({
    config,
    registry: new ServiceRegistry(config.accounts, silentLogger),
    limiter: new RateLimiter(60_000, 1000),
    logger: silentLogger
  });
  await new Promise<void>((resolve) => http.listen(0, '127.0.0.1', resolve));
  const address = http.address();
  const port = typeof address === 'object' && address ? address.port : 0;

  try {
    const res = await fetch(`http://127.0.0.1:${port}/mcp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer http-secret' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'x', params: { pad: 'a'.repeat(5000) } })
    });
    assert.equal(res.status, 413);
  } finally {
    await new Promise<void>((resolve) => http.close(() => resolve()));
    await h.close();
  }
});
