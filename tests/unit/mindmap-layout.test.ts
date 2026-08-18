import { describe, it, expect } from 'vitest';
import { radialLayout, round } from '$lib/mindmap/layout';

describe('radialLayout', () => {
	it('places 4 nodes at top/right/bottom/left', () => {
		const pts = radialLayout(4, 100, 0, 0).map(round);
		expect(pts).toEqual([
			{ x: 0, y: -100 }, // top
			{ x: 100, y: 0 }, // right
			{ x: 0, y: 100 }, // bottom
			{ x: -100, y: 0 } // left
		]);
	});
	it('offsets by centre', () => {
		const pts = radialLayout(1, 50, 200, 200).map(round);
		expect(pts).toEqual([{ x: 200, y: 150 }]);
	});
});
