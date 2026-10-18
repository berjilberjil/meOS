import { describe, it, expect } from 'vitest';
import { etagMatches } from './etag';

describe('etagMatches', () => {
  const etag = '"v5815-1792296911246"';

  it('matches the exact strong tag', () => {
    expect(etagMatches('"v5815-1792296911246"', etag)).toBe(true);
  });

  it('matches the weak form Cloudflare hands the client', () => {
    expect(etagMatches('W/"v5815-1792296911246"', etag)).toBe(true);
  });

  it('does not match a stale version', () => {
    expect(etagMatches('W/"v5810-1792296911246"', etag)).toBe(false);
  });

  it('matches one entry of a list, and *', () => {
    expect(etagMatches('"a", W/"v5815-1792296911246"', etag)).toBe(true);
    expect(etagMatches('*', etag)).toBe(true);
  });

  it('does not match a missing header', () => {
    expect(etagMatches(null, etag)).toBe(false);
    expect(etagMatches('', etag)).toBe(false);
  });
});
