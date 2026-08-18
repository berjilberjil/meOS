import { describe, it, expect } from 'vitest';
import { formatInviteCode, generateInviteCode, inviteStatus } from '$lib/auth/inviteLogic';

describe('formatInviteCode', () => {
	it('formats 8 chars grouped XXXX-XXXX, uppercase, no ambiguous I/O chars', () => {
		const code = formatInviteCode(new Uint8Array([0, 1, 2, 3, 250, 200, 150, 100]));
		expect(code).toMatch(/^[0-9A-HJ-NP-Z]{4}-[0-9A-HJ-NP-Z]{4}$/);
		expect(code).toBe(code.toUpperCase());
	});
	it('is deterministic for the same bytes', () => {
		const b = new Uint8Array([5, 9, 17, 33, 65, 129, 200, 240]);
		expect(formatInviteCode(b)).toBe(formatInviteCode(b));
	});
});

describe('generateInviteCode', () => {
	it('produces a well-formed code', () => {
		expect(generateInviteCode()).toMatch(/^[0-9A-HJ-NP-Z]{4}-[0-9A-HJ-NP-Z]{4}$/);
	});
});

describe('inviteStatus', () => {
	const base = { used_by: null as string | null, expires_at: '2026-08-01T00:00:00Z', revoked: false };
	const now = '2026-07-11T00:00:00Z';
	it('active when unused, unexpired, not revoked', () => {
		expect(inviteStatus(base, now)).toBe('active');
	});
	it('revoked wins over everything', () => {
		expect(inviteStatus({ ...base, revoked: true, used_by: 'u' }, now)).toBe('revoked');
	});
	it('used when used_by set and not revoked', () => {
		expect(inviteStatus({ ...base, used_by: 'u' }, now)).toBe('used');
	});
	it('expired when past expiry, unused, not revoked', () => {
		expect(inviteStatus({ ...base, expires_at: '2026-07-01T00:00:00Z' }, now)).toBe('expired');
	});
});
