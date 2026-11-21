import test from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig, hashToken } from '../src/config/env.ts';

const baseEnv = {
  MEOS_BASE_URL: 'https://meos-api.example.com',
  MEOS_USERNAME: 'owner',
  MEOS_PASSWORD: 'password',
  MEOS_VAULT_PASSPHRASE: 'vault-pass'
};

test('stdio config creates a local client with read scopes by default', () => {
  const config = loadConfig({ ...baseEnv } as NodeJS.ProcessEnv);
  assert.equal(config.transport, 'stdio');
  const client = config.clients.get('stdio');
  assert.ok(client);
  assert.deepEqual(client!.scopes, ['read']);
  assert.equal(client!.tokenHash, null);
  assert.equal(client!.accountId, 'owner');
});

test('HTTP refuses to start without a token', () => {
  assert.throws(
    () => loadConfig({ ...baseEnv, MEOS_MCP_TRANSPORT: 'http' } as NodeJS.ProcessEnv),
    /refuses to start without credentials/
  );
});

test('HTTP client tokens are hashed, never retained in plaintext', () => {
  const config = loadConfig({
    ...baseEnv,
    MEOS_MCP_TRANSPORT: 'http',
    MEOS_MCP_CLIENTS_JSON: JSON.stringify([
      { id: 'claude', token: 'super-secret-token', scopes: ['read', 'health'], account: 'owner' },
      { id: 'cursor', token_sha256: hashToken('another-token'), scopes: ['read'], account: 'owner' }
    ])
  } as NodeJS.ProcessEnv);
  const claude = config.clients.get('claude')!;
  assert.equal(claude.tokenHash, hashToken('super-secret-token'));
  assert.notEqual(claude.tokenHash, 'super-secret-token');
  assert.deepEqual(claude.scopes, ['read', 'health']);
  assert.equal(config.clients.get('cursor')!.tokenHash, hashToken('another-token'));
});

test('non-loopback HTTP binding requires an explicit opt-in', () => {
  assert.throws(
    () =>
      loadConfig({
        ...baseEnv,
        MEOS_MCP_TRANSPORT: 'http',
        MEOS_MCP_HTTP_TOKEN: 't',
        MEOS_MCP_HTTP_HOST: '0.0.0.0'
      } as NodeJS.ProcessEnv),
    /Refusing to bind/
  );
  const allowed = loadConfig({
    ...baseEnv,
    MEOS_MCP_TRANSPORT: 'http',
    MEOS_MCP_HTTP_TOKEN: 't',
    MEOS_MCP_HTTP_HOST: '0.0.0.0',
    MEOS_MCP_ALLOW_REMOTE: 'true'
  } as NodeJS.ProcessEnv);
  assert.equal(allowed.http.host, '0.0.0.0');
});

test('base URLs must be HTTPS except on localhost', () => {
  assert.throws(
    () => loadConfig({ ...baseEnv, MEOS_BASE_URL: 'http://example.com' } as NodeJS.ProcessEnv),
    /https/
  );
  const local = loadConfig({ ...baseEnv, MEOS_BASE_URL: 'http://127.0.0.1:8787' } as NodeJS.ProcessEnv);
  assert.equal(local.accounts.get('owner')!.baseUrl, 'http://127.0.0.1:8787');
});

test('an invalid expires_at is rejected', () => {
  assert.throws(
    () =>
      loadConfig({
        ...baseEnv,
        MEOS_MCP_TRANSPORT: 'http',
        MEOS_MCP_CLIENTS_JSON: JSON.stringify([
          { id: 'x', token: 't', scopes: ['read'], account: 'owner', expires_at: 'next tuesday' }
        ])
      } as NodeJS.ProcessEnv),
    /invalid expires_at/
  );
});

test('unknown scopes are rejected', () => {
  assert.throws(
    () => loadConfig({ ...baseEnv, MEOS_MCP_SCOPES: 'read,admin' } as NodeJS.ProcessEnv),
    /Unknown scope/
  );
});

test('multi-account configuration is supported and isolated by client', () => {
  const config = loadConfig({
    ...baseEnv,
    MEOS_MCP_TRANSPORT: 'http',
    MEOS_MCP_ACCOUNTS_JSON: JSON.stringify([
      { id: 'second', username: 'other', password: 'p2', vaultPassphrase: 'v2' }
    ]),
    MEOS_MCP_CLIENTS_JSON: JSON.stringify([
      { id: 'a-client', token: 'ta', scopes: ['read'], account: 'owner' },
      { id: 'b-client', token: 'tb', scopes: ['read'], account: 'second' }
    ])
  } as NodeJS.ProcessEnv);
  assert.equal(config.accounts.get('second')!.username, 'other');
  assert.equal(config.clients.get('b-client')!.accountId, 'second');
  assert.equal(config.clients.get('a-client')!.accountId, 'owner');
});

test('two clients may not share a bearer token', () => {
  assert.throws(
    () =>
      loadConfig({
        ...baseEnv,
        MEOS_MCP_TRANSPORT: 'http',
        MEOS_MCP_CLIENTS_JSON: JSON.stringify([
          { id: 'one', token: 'same', scopes: ['read'], account: 'owner' },
          { id: 'two', token: 'same', scopes: ['write'], account: 'owner' }
        ])
      } as NodeJS.ProcessEnv),
    /share the same bearer token/
  );
});

test('an unknown account reference fails closed', () => {
  assert.throws(
    () =>
      loadConfig({
        ...baseEnv,
        MEOS_MCP_TRANSPORT: 'http',
        MEOS_MCP_CLIENTS_JSON: JSON.stringify([{ id: 'x', token: 't', scopes: ['read'], account: 'ghost' }])
      } as NodeJS.ProcessEnv),
    /unknown account/
  );
});

test('credentials with line breaks are rejected', () => {
  assert.throws(
    () => loadConfig({ ...baseEnv, MEOS_PASSWORD: 'a\nb' } as NodeJS.ProcessEnv),
    /line breaks/
  );
});
