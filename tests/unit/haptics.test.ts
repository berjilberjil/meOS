import { describe, it, expect, vi, beforeEach } from 'vitest';

const impactFeedback = vi.fn(() => Promise.resolve());
const selectionFeedback = vi.fn(() => Promise.resolve());
const notificationFeedback = vi.fn(() => Promise.resolve());
vi.mock('@tauri-apps/plugin-haptics', () => ({
	impactFeedback,
	selectionFeedback,
	notificationFeedback
}));

beforeEach(() => {
	vi.clearAllMocks();
	// jsdom window has no __TAURI_INTERNALS__ → not native.
	delete (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__;
});

describe('haptics (non-native)', () => {
	it('is a silent no-op off-device and never throws', async () => {
		const h = await import('$lib/haptics');
		expect(() => {
			h.tick();
			h.impact();
			h.success();
			h.warning();
		}).not.toThrow();
		expect(selectionFeedback).not.toHaveBeenCalled();
		expect(impactFeedback).not.toHaveBeenCalled();
		expect(notificationFeedback).not.toHaveBeenCalled();
	});
});

describe('haptics (native)', () => {
	it('routes to the right plugin call when running in Tauri', async () => {
		(window as unknown as Record<string, unknown>).__TAURI_INTERNALS__ = {};
		const h = await import('$lib/haptics');
		h.tick();
		h.impact();
		h.success();
		h.warning();
		expect(selectionFeedback).toHaveBeenCalledTimes(1);
		expect(impactFeedback).toHaveBeenCalledWith('medium');
		expect(notificationFeedback).toHaveBeenCalledWith('success');
		expect(notificationFeedback).toHaveBeenCalledWith('warning');
	});
});
