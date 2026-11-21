import { beforeEach, describe, expect, it, vi } from 'vitest';

// Vitest does not run SvelteKit's env plugin, so point the dynamic env at the
// live process environment. This is the same object production reads.
vi.mock('$env/dynamic/private', () => ({ env: process.env }));

const KEY_A = Buffer.alloc(32, 1).toString('base64');
const KEY_B = Buffer.alloc(32, 2).toString('base64');

async function loadSecrets() {
  vi.resetModules();
  return await import('./secrets');
}

describe('server secret encryption', () => {
  beforeEach(() => {
    delete process.env.MEOS_SECRETS_KEYS;
    delete process.env.MEOS_SECRETS_KEY_ID;
    delete process.env.MEOS_SECRETS_KEY;
    delete process.env.MYOS_SECRETS_KEY;
    delete process.env.MEOS_ALLOW_WEAK_SECRETS_KEY;
  });

  it('round-trips a v2 ciphertext and binds it to the active key id', async () => {
    process.env.MEOS_SECRETS_KEY = KEY_A;
    const { encryptSecret, decryptSecret, activeSecretsKeyId } = await loadSecrets();
    const enc = await encryptSecret('sk-test-123456789');
    expect(enc.startsWith('v2:v1:')).toBe(true);
    expect(activeSecretsKeyId()).toBe('v1');
    expect(await decryptSecret(enc)).toBe('sk-test-123456789');
  });

  it('decrypts a key-ring ciphertext after the active key changes', async () => {
    process.env.MEOS_SECRETS_KEYS = JSON.stringify({ v1: KEY_A, v2: KEY_B });
    process.env.MEOS_SECRETS_KEY_ID = 'v2';
    const first = await loadSecrets();
    const enc = await first.encryptSecret('rotate-me');
    expect(enc.startsWith('v2:v2:')).toBe(true);

    vi.resetModules();
    process.env.MEOS_SECRETS_KEY_ID = 'v1';
    const second = await import('./secrets');
    expect(await second.decryptSecret(enc)).toBe('rotate-me');
  });

  it('fails closed on a weak new-encryption key unless explicitly allowed', async () => {
    process.env.MEOS_SECRETS_KEY = 'a short passphrase';
    const { encryptSecret } = await loadSecrets();
    await expect(encryptSecret('x')).rejects.toThrow(/32 bytes/);

    vi.resetModules();
    process.env.MEOS_ALLOW_WEAK_SECRETS_KEY = 'true';
    const allowed = await import('./secrets');
    await expect(allowed.encryptSecret('x')).resolves.toMatch(/^v2:/);
  });

  it('still decrypts legacy raw base64 ciphertext (no key id, no AAD)', async () => {
    process.env.MEOS_SECRETS_KEY = 'legacy-passphrase';
    const { createCipheriv, createHash, randomBytes } = await import('node:crypto');
    const key = createHash('sha256').update('legacy-passphrase').digest();
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', key, iv);
    const ct = Buffer.concat([cipher.update('legacy-secret', 'utf8'), cipher.final()]);
    const blob = Buffer.concat([iv, ct, cipher.getAuthTag()]).toString('base64');

    const { decryptSecret } = await loadSecrets();
    expect(await decryptSecret(blob)).toBe('legacy-secret');
  });
});
