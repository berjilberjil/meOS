import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: process.env }));

const PEPPER = Buffer.alloc(32, 5).toString('base64');

async function loadAuth() {
  vi.resetModules();
  return await import('./auth');
}

describe('peppered password hashing', () => {
  afterEach(() => {
    delete process.env.MEOS_PASSWORD_PEPPER;
    delete process.env.MEOS_PBKDF2_ITERATIONS;
  });

  it('writes v3 when a dedicated pepper is configured and verifies it', async () => {
    process.env.MEOS_PASSWORD_PEPPER = PEPPER;
    process.env.MEOS_PBKDF2_ITERATIONS = '10000';
    const auth = await loadAuth();
    const stored = await auth.hashPassword('correct horse battery staple');
    expect(stored.startsWith('v3:')).toBe(true);
    expect(await auth.verifyPassword('correct horse battery staple', stored)).toBe(true);
    expect(await auth.verifyPassword('wrong', stored)).toBe(false);
  });

  it('fails closed on a v3 hash when the pepper is missing', async () => {
    process.env.MEOS_PASSWORD_PEPPER = PEPPER;
    const first = await loadAuth();
    const stored = await first.hashPassword('a long password');
    delete process.env.MEOS_PASSWORD_PEPPER;
    const second = await loadAuth();
    expect(await second.verifyPassword('a long password', stored)).toBe(false);
  });

  it('still verifies a v2 hash when a pepper exists (upgrade path)', async () => {
    const plain = await loadAuth();
    const v2 = await plain.hashPassword('legacy v2 password');
    expect(v2.startsWith('v2:')).toBe(true);

    process.env.MEOS_PASSWORD_PEPPER = PEPPER;
    const peppered = await loadAuth();
    expect(await peppered.verifyPassword('legacy v2 password', v2)).toBe(true);
  });
});
