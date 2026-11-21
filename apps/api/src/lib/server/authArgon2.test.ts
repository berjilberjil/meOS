import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: process.env }));

const PEPPER = Buffer.alloc(32, 9).toString('base64');

async function loadAuth() {
  vi.resetModules();
  return await import('./auth');
}

describe('Argon2id login hashing (opt-in)', () => {
  afterEach(() => {
    delete process.env.MEOS_PASSWORD_KDF;
    delete process.env.MEOS_ARGON2_MEMORY_KIB;
    delete process.env.MEOS_ARGON2_ITERATIONS;
    delete process.env.MEOS_PASSWORD_PEPPER;
  });

  it('writes v4 Argon2id with the configured parameters and verifies it', async () => {
    process.env.MEOS_PASSWORD_KDF = 'argon2id';
    process.env.MEOS_ARGON2_MEMORY_KIB = '19456';
    process.env.MEOS_ARGON2_ITERATIONS = '2';
    process.env.MEOS_PASSWORD_PEPPER = PEPPER;
    const auth = await loadAuth();

    const stored = await auth.hashPassword('correct horse battery staple');
    expect(stored.startsWith('v4:2:19456:1:')).toBe(true);
    expect(await auth.verifyPassword('correct horse battery staple', stored)).toBe(true);
    expect(await auth.verifyPassword('wrong', stored)).toBe(false);
  });

  it('still verifies a v3 PBKDF2 hash after switching KDF', async () => {
    process.env.MEOS_PASSWORD_PEPPER = PEPPER;
    const first = await loadAuth();
    const v3 = await first.hashPassword('upgrade-me');
    expect(v3.startsWith('v3:')).toBe(true);

    process.env.MEOS_PASSWORD_KDF = 'argon2id';
    process.env.MEOS_ARGON2_MEMORY_KIB = '19456';
    const second = await loadAuth();
    expect(await second.verifyPassword('upgrade-me', v3)).toBe(true);
    expect((await second.hashPassword('upgrade-me')).startsWith('v4:')).toBe(true);
  });
});
