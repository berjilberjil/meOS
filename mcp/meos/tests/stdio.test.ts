import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHarness } from './support/harness.ts';

interface Pending {
  resolve: (value: any) => void;
  reject: (error: Error) => void;
}

test('the real stdio entry point initializes and lists tools', async () => {
  const h = await createHarness();
  const child = spawn(process.execPath, ['src/index.ts'], {
    cwd: new URL('..', import.meta.url),
    env: {
      ...process.env,
      MEOS_MCP_TRANSPORT: 'stdio',
      MEOS_BASE_URL: h.baseUrl,
      MEOS_USERNAME: h.accounts.a.username,
      MEOS_PASSWORD: h.accounts.a.password,
      MEOS_VAULT_PASSPHRASE: h.accounts.a.passphrase,
      MEOS_MCP_SCOPES: 'read,health',
      MEOS_MCP_LOG_LEVEL: 'error'
    },
    stdio: ['pipe', 'pipe', 'pipe']
  });

  const pending = new Map<number, Pending>();
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', (chunk: string) => {
    stderr += chunk;
  });
  child.stdout.on('data', (chunk: string) => {
    stdout += chunk;
    for (;;) {
      const newline = stdout.indexOf('\n');
      if (newline < 0) break;
      const line = stdout.slice(0, newline).trim();
      stdout = stdout.slice(newline + 1);
      if (!line) continue;
      const message = JSON.parse(line);
      if (message.id != null && pending.has(message.id)) {
        pending.get(message.id)!.resolve(message);
        pending.delete(message.id);
      }
    }
  });

  let nextId = 1;
  const request = (method: string, params: unknown) =>
    new Promise<any>((resolve, reject) => {
      const id = nextId++;
      pending.set(id, { resolve, reject });
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
      setTimeout(() => {
        if (!pending.has(id)) return;
        pending.delete(id);
        reject(new Error(`timed out waiting for ${method}\n${stderr}`));
      }, 5000).unref();
    });

  try {
    const init = await request('initialize', {
      protocolVersion: '2025-06-18',
      capabilities: {},
      clientInfo: { name: 'stdio-test', version: '1.0.0' }
    });
    assert.equal(init.result.serverInfo.name, 'meos');
    assert.match(init.result.instructions, /MeOS/i);

    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');

    const listed = await request('tools/list', {});
    assert.ok(listed.result.tools.length >= 50);
    assert.ok(listed.result.tools.some((t: any) => t.name === 'meos_health_get_summary'));

    const call = await request('tools/call', { name: 'meos_get_profile', arguments: {} });
    assert.equal(call.result.structuredContent.data.name, 'Berjil');
  } finally {
    child.kill('SIGTERM');
    await h.close();
  }
});
