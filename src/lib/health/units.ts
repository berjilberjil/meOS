// Integer-unit conversions for health/fitness. Store ints, display decimals.

export function kgToG(kg: number): number {
	return Math.round(kg * 1000);
}
export function gToKg(g: number): number {
	return g / 1000;
}
export function kmToM(km: number): number {
	return Math.round(km * 1000);
}
export function mToKm(m: number): number {
	return m / 1000;
}
export function hoursToMin(hours: number): number {
	return Math.round(hours * 60);
}
export function minToHours(min: number): number {
	return min / 60;
}
