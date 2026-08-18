export interface Point {
	x: number;
	y: number;
}

// Pure: evenly place `n` nodes on a circle, first node at top (12 o'clock).
export function radialLayout(n: number, radius: number, cx = 0, cy = 0): Point[] {
	const pts: Point[] = [];
	for (let i = 0; i < n; i++) {
		const angle = ((-90 + (360 / n) * i) * Math.PI) / 180;
		pts.push({ x: cx + radius * Math.cos(angle), y: cy + radius * Math.sin(angle) });
	}
	return pts;
}

// Round a point for stable rendering / test assertions.
export function round(p: Point): Point {
	return { x: Math.round(p.x), y: Math.round(p.y) };
}
