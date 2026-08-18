export function ringFraction(value: number, max: number): number {
	if (max <= 0) return 0;
	const f = value / max;
	if (f < 0) return 0;
	if (f > 1) return 1;
	return f;
}

export function donutDashArray(
	values: number[],
	circumference: number
): { dash: number; gap: number; offset: number }[] {
	const total = values.reduce((s, v) => s + v, 0);
	let acc = 0;
	return values.map((v) => {
		const dash = total > 0 ? (v / total) * circumference : 0;
		const seg = { dash, gap: circumference - dash, offset: acc === 0 ? 0 : -acc };
		acc += dash;
		return seg;
	});
}
