import { describe, it, expect } from 'vitest';
import { shouldAbortPress, MOVE_ABORT_PX } from '$lib/components/layout/navGesture';

describe('shouldAbortPress', () => {
	it('aborts only past the move threshold', () => {
		expect(shouldAbortPress(0, 0)).toBe(false);
		expect(shouldAbortPress(MOVE_ABORT_PX, 0)).toBe(false);
		expect(shouldAbortPress(MOVE_ABORT_PX + 1, 0)).toBe(true);
		expect(shouldAbortPress(8, 8)).toBe(true); // diagonal hypot > threshold
	});
});
