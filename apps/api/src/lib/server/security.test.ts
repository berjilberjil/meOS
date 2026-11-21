import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: process.env }));
import { originAllowed, SlidingWindowLimiter, applySecurityHeaders } from './security';
import { cleanMeta, hashIp } from './audit';

describe('CSRF / origin checks', () => {
  const url = new URL('https://meos-api.example.workers.dev/api/state/x');

  it('allows native requests with no browser origin headers', () => {
    expect(originAllowed(new Request(url, { method: 'PUT' }), url)).toBe(true);
  });

  it('allows the exact same origin', () => {
    const req = new Request(url, { method: 'PUT', headers: { origin: url.origin } });
    expect(originAllowed(req, url)).toBe(true);
  });

  it('refuses a cross-site origin and a null origin', () => {
    expect(
      originAllowed(new Request(url, { method: 'PUT', headers: { origin: 'https://evil.example' } }), url)
    ).toBe(false);
    expect(originAllowed(new Request(url, { method: 'PUT', headers: { origin: 'null' } }), url)).toBe(false);
    expect(
      originAllowed(new Request(url, { method: 'PUT', headers: { 'sec-fetch-site': 'cross-site' } }), url)
    ).toBe(false);
  });

  it('allows an operator-trusted extra origin only when configured', () => {
    process.env.MEOS_TRUSTED_ORIGINS = 'https://app.example';
    const req = new Request(url, { method: 'PUT', headers: { origin: 'https://app.example' } });
    expect(originAllowed(req, url)).toBe(true);
    delete process.env.MEOS_TRUSTED_ORIGINS;
  });
});

describe('security headers', () => {
  it('sets transport, framing and cache protections', () => {
    const response = new Response('{}');
    applySecurityHeaders(response, new URL('https://meos.example/api/me'));
    expect(response.headers.get('x-frame-options')).toBe('DENY');
    expect(response.headers.get('x-content-type-options')).toBe('nosniff');
    expect(response.headers.get('referrer-policy')).toBe('no-referrer');
    expect(response.headers.get('strict-transport-security')).toContain('max-age=');
    expect(response.headers.get('permissions-policy')).toContain('camera=()');
  });
});

describe('burst limiter', () => {
  it('refuses over-budget requests and recovers after the window', () => {
    let now = 0;
    const limiter = new SlidingWindowLimiter(() => now);
    expect(limiter.take('k', 2, 1000).ok).toBe(true);
    expect(limiter.take('k', 2, 1000).ok).toBe(true);
    const denied = limiter.take('k', 2, 1000);
    expect(denied.ok).toBe(false);
    now = 1001;
    expect(limiter.take('k', 2, 1000).ok).toBe(true);
  });
});

describe('audit redaction', () => {
  afterEach(() => {
    delete process.env.MEOS_AUDIT_SALT;
  });

  it('drops secret-bearing keys and keeps bounded metadata', () => {
    const meta = cleanMeta({
      module: 'notes',
      rows: 2,
      token: 'x',
      password: 'x',
      note: 'private',
      api_key: 'x',
      huge: 'x'.repeat(500)
    });
    expect(meta).toContain('"module":"notes"');
    expect(meta).toContain('"rows":2');
    expect(meta).not.toContain('"token"');
    expect(meta).not.toContain('"note"');
    expect(meta).not.toContain('"api_key"');
  });

  it('hashes an IP with a stable, non-reversible salted digest', async () => {
    process.env.MEOS_AUDIT_SALT = 'test-salt';
    const a = await hashIp('203.0.113.9');
    const b = await hashIp('203.0.113.9');
    const c = await hashIp('203.0.113.10');
    expect(a).toBe(b);
    expect(a).not.toBe(c);
    expect(a).toMatch(/^[a-f0-9]{32}$/);
    expect(a).not.toContain('203.0.113');
  });
});
