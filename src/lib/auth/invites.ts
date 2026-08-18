import { SupabaseRepository } from '$lib/data/repository';
import { generateInviteCode } from './inviteLogic';

export interface Invite {
	id: string;
	code: string;
	email: string | null;
	created_by: string;
	used_by: string | null;
	used_at: string | null;
	expires_at: string;
	revoked: boolean;
	created_at: string;
}

export const invitesRepo = new SupabaseRepository<Invite>('invites');

export function listInvites(): Promise<Invite[]> {
	return invitesRepo.list();
}

export function createInvite(opts: { email?: string; days?: number } = {}): Promise<Invite> {
	// expires_at defaults to 14 days server-side; only override when days is given.
	const patch: Partial<Invite> = { code: generateInviteCode(), email: opts.email ?? null };
	if (opts.days != null) {
		const d = new Date();
		d.setDate(d.getDate() + opts.days);
		patch.expires_at = d.toISOString();
	}
	return invitesRepo.create(patch);
}

export function revokeInvite(id: string): Promise<void> {
	return invitesRepo.update(id, { revoked: true }).then(() => undefined);
}
