/**
 * Pure helpers for turning what's on a receipt into what MeOS stores.
 *
 * All of this is string wrangling with no I/O, which is exactly the part worth
 * testing: an assistant reading an Amazon screenshot will hand over prices as
 * "₹2,499.00", dates as "19 August 2026", and links with forty characters of
 * tracking on the end.
 */

/** A product link with the tracking stripped off. */
export function canonicalLink(raw: string): string {
	const s = (raw ?? '').trim();
	if (!s) return '';
	let url: URL;
	try {
		url = new URL(s);
	} catch {
		return s; // not a URL — hand it back untouched rather than losing it
	}
	const host = url.hostname.toLowerCase();

	// Amazon: /dp/<ASIN> is the whole identity. The slug and the ref/tracking
	// tail change per session and make two links to one product look different.
	if (host.includes('amazon.')) {
		const asin = asinFrom(url.pathname);
		if (asin) return `https://${url.hostname}/dp/${asin}`;
	}

	// Everything else: keep the path, drop the usual tracking params.
	const drop = /^(utm_|ref_?$|ref$|tag$|gclid$|fbclid$|_encoding$|psc$|th$|pd_rd_|pf_rd_|sr$|qid$|smid$|linkCode$|creative)/i;
	for (const key of [...url.searchParams.keys()]) {
		if (drop.test(key)) url.searchParams.delete(key);
	}
	url.hash = '';
	return url.toString().replace(/\?$/, '');
}

/** The 10-character Amazon product id out of a path, if there is one. */
export function asinFrom(path: string): string | null {
	const m = path.match(/\/(?:dp|gp\/product|gp\/aw\/d|product)\/([A-Z0-9]{10})(?:[/?]|$)/i);
	return m ? m[1]!.toUpperCase() : null;
}

/**
 * Rupees, as a whole number, out of whatever the receipt said.
 * Paise are dropped on purpose — the Stuff tab shows whole rupees.
 */
export function parseInr(raw: string | number | null | undefined): number | null {
	if (typeof raw === 'number') return Number.isFinite(raw) ? Math.round(raw) : null;
	const s = (raw ?? '').trim();
	if (!s) return null;
	// The first run of digits, allowing grouping commas and at most a two-digit
	// paise tail. Matching the number rather than stripping the rest is what
	// keeps the full stop in "Rs. 1,09,999" from reading as a decimal point.
	const m = s.match(/\d[\d,]*(?:\.\d{1,2})?/);
	if (!m) return null;
	const digits = m[0].split('.')[0]!.replace(/[^\d]/g, '');
	if (!digits) return null;
	const n = Number(digits);
	return Number.isFinite(n) ? n : null;
}

const MONTHS: Record<string, number> = {
	jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
	jul: 7, aug: 8, sep: 9, sept: 9, oct: 10, nov: 11, dec: 12
};

/**
 * A `YYYY-MM-DD` key out of the date shapes receipts actually use.
 *
 * Numeric `a/b/c` is read DAY first — Amazon.in, and every Indian invoice,
 * writes 08/09 as the 8th of September. Returns null rather than guessing when
 * the string isn't a date at all, so the caller can fall back to today.
 */
export function parseDate(raw: string | null | undefined): string | null {
	const s = (raw ?? '').trim();
	if (!s) return null;

	const iso = s.match(/(\d{4})-(\d{2})-(\d{2})/);
	if (iso) return ymd(+iso[1]!, +iso[2]!, +iso[3]!);

	// "19 August 2026" / "19 Aug 2026" / "19th Aug, 2026"
	const dmy = s.match(/(\d{1,2})(?:st|nd|rd|th)?[\s-]+([A-Za-z]{3,9})\.?,?[\s-]+(\d{4})/);
	if (dmy) {
		const m = MONTHS[dmy[2]!.slice(0, 4).toLowerCase()] ?? MONTHS[dmy[2]!.slice(0, 3).toLowerCase()];
		if (m) return ymd(+dmy[3]!, m, +dmy[1]!);
	}

	// "August 19, 2026" / "Aug 19 2026"
	const mdy = s.match(/([A-Za-z]{3,9})\.?[\s-]+(\d{1,2})(?:st|nd|rd|th)?,?[\s-]+(\d{4})/);
	if (mdy) {
		const m = MONTHS[mdy[1]!.slice(0, 4).toLowerCase()] ?? MONTHS[mdy[1]!.slice(0, 3).toLowerCase()];
		if (m) return ymd(+mdy[3]!, m, +mdy[2]!);
	}

	// "19/08/2026" or "19-08-26" — day first.
	const num = s.match(/(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})/);
	if (num) {
		const year = +num[3]! < 100 ? 2000 + +num[3]! : +num[3]!;
		return ymd(year, +num[2]!, +num[1]!);
	}
	return null;
}

function ymd(y: number, m: number, d: number): string | null {
	if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1970 || y > 2999) return null;
	return `${String(y).padStart(4, '0')}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

/** Today, in the app's key format, on this machine's clock. */
export function todayIso(): string {
	const d = new Date();
	return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** The default payback window for anything bought, in months. */
export const DEFAULT_ROI_MONTHS = 36;
