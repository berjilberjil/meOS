import { describe, expect, it } from 'vitest';
import { parseDeviceName, parseDeviceRegistration } from './devices';

describe('parseDeviceRegistration', () => {
  it('accepts a Mac heartbeat', () => {
    const parsed = parseDeviceRegistration({
      id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
      systemName: "Berjil's MacBook Pro",
      platform: 'macOS 26.1',
      kind: 'mac',
      appVersion: '1.0 (1)'
    });
    expect(parsed).toEqual({
      ok: true,
      value: {
        id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        systemName: "Berjil's MacBook Pro",
        platform: 'macOS 26.1',
        kind: 'mac',
        appVersion: '1.0 (1)'
      }
    });
  });

  it('rejects a missing or oversized id', () => {
    expect(parseDeviceRegistration({ kind: 'mac' }).ok).toBe(false);
    expect(parseDeviceRegistration({ id: 'short', kind: 'mac' }).ok).toBe(false);
    expect(parseDeviceRegistration({ id: 'x'.repeat(65), kind: 'mac' }).ok).toBe(false);
  });

  it('rejects an id with characters that do not belong in a path', () => {
    const parsed = parseDeviceRegistration({ id: '../../etc/passwd', kind: 'mac' });
    expect(parsed.ok).toBe(false);
  });

  it('rejects an unknown device kind', () => {
    expect(parseDeviceRegistration({ id: 'abcdefgh', kind: 'toaster' }).ok).toBe(false);
    expect(parseDeviceRegistration({ id: 'abcdefgh' }).ok).toBe(false);
  });

  it('falls back to sensible names instead of storing blanks', () => {
    const parsed = parseDeviceRegistration({ id: 'abcdefgh', kind: 'iphone' });
    expect(parsed).toEqual({
      ok: true,
      value: {
        id: 'abcdefgh',
        systemName: 'iPhone',
        platform: 'iOS',
        kind: 'iphone',
        appVersion: ''
      }
    });
  });

  it('strips control characters and caps every field', () => {
    const parsed = parseDeviceRegistration({
      id: 'abcdefgh',
      kind: 'mac',
      systemName: `  Mac\u0000Book ${'x'.repeat(200)}  `,
      platform: 'p'.repeat(200),
      appVersion: 'v'.repeat(200)
    });
    if (!parsed.ok) throw new Error('expected a valid registration');
    expect(parsed.value.systemName.startsWith('MacBook ')).toBe(true);
    expect(parsed.value.systemName.length).toBe(80);
    expect(parsed.value.platform.length).toBe(80);
    expect(parsed.value.appVersion.length).toBe(40);
  });
});

describe('parseDeviceName', () => {
  it('trims and keeps a normal name', () => {
    expect(parseDeviceName('  Office Mac  ')).toBe('Office Mac');
  });

  it('caps the name so a list row cannot be flooded', () => {
    expect(parseDeviceName('m'.repeat(100))?.length).toBe(60);
  });

  it('rejects blanks and non-strings', () => {
    expect(parseDeviceName('   ')).toBeNull();
    expect(parseDeviceName('')).toBeNull();
    expect(parseDeviceName(42)).toBeNull();
    expect(parseDeviceName(undefined)).toBeNull();
  });
});
