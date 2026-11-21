import { describe, expect, it } from 'vitest';
import { stateETag } from './stateVersion';

describe('state ETag', () => {
  it('encodes the newest write and the row count', () => {
    expect(stateETag(null, 0)).toBe('"0-0"');
    expect(stateETag('2026-08-20T10:00:00.000Z', 21)).toBe(`"${Date.parse('2026-08-20T10:00:00.000Z')}-21"`);
  });
});
