// Shared constants for the bottom-nav long-press menus. The menu selection
// itself is hit-tested in the component (elementFromPoint), so only the
// long-press timing + the "this was a scroll, abort" check live here.

export const LONG_PRESS_MS = 350;
/** Movement (px) before the long-press engages that is treated as a scroll → abort. */
export const MOVE_ABORT_PX = 10;

/** True if movement before engagement is large enough to abort the long-press. */
export function shouldAbortPress(dx: number, dy: number): boolean {
	return Math.hypot(dx, dy) > MOVE_ABORT_PX;
}
