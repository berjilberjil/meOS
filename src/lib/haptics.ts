// Curated haptic feedback. Native only (iOS/Android via the Tauri haptics
// plugin); silent no-op on web/desktop. Every call is fire-and-forget and must
// never throw — feedback is a nicety, not a dependency.
import { impactFeedback, notificationFeedback, selectionFeedback } from '@tauri-apps/plugin-haptics';

function isTauri(): boolean {
	return typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
}

function safe(run: () => Promise<unknown>): void {
	if (!isTauri()) return;
	try {
		run().catch(() => {});
	} catch {
		/* ignore — haptics are best-effort */
	}
}

/** Light selection change — nav tabs, toggles, gesture target crossings. */
export function tick(): void {
	safe(() => selectionFeedback());
}

/** Medium impact — primary buttons, the elevated Dashboard, long-press trigger. */
export function impact(): void {
	safe(() => impactFeedback('medium'));
}

/** Success notification — a create/save completed, a gesture fired. */
export function success(): void {
	safe(() => notificationFeedback('success'));
}

/** Warning notification — deletes, validation errors. */
export function warning(): void {
	safe(() => notificationFeedback('warning'));
}
