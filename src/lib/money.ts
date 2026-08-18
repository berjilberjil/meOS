// Money is stored as integer paise everywhere. Convert at the edges only.

export function toPaise(rupees: number): number {
	return Math.round(rupees * 100);
}

export function fromPaise(paise: number): number {
	return paise / 100;
}

const inr = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR' });

export function formatINR(paise: number): string {
	return inr.format(fromPaise(paise));
}

export function sumPaise(values: number[]): number {
	return values.reduce((total, v) => total + v, 0);
}
