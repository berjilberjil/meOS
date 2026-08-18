// Pure invite helpers — no DB. Code generation (format) + status computation.
// This is the unit-testable core of the invite flow.

const ALPHABET = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ'; // 34 chars, no I/O to avoid confusion

/** Deterministic 8-char code from >=5 random bytes, grouped XXXX-XXXX, uppercase. */
export function formatInviteCode(bytes: Uint8Array): string {
	let out = '';
	for (let i = 0; i < 8; i++) {
		out += ALPHABET[bytes[i % bytes.length] % ALPHABET.length];
	}
	return `${out.slice(0, 4)}-${out.slice(4)}`;
}

export function generateInviteCode(): string {
	const bytes = new Uint8Array(8);
	crypto.getRandomValues(bytes);
	return formatInviteCode(bytes);
}

export type InviteStatus = 'active' | 'used' | 'expired' | 'revoked';

export function inviteStatus(
	inv: { used_by: string | null; expires_at: string; revoked: boolean },
	nowIso: string
): InviteStatus {
	if (inv.revoked) return 'revoked';
	if (inv.used_by) return 'used';
	if (inv.expires_at < nowIso) return 'expired';
	return 'active';
}
