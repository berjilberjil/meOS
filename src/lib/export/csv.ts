// Tiny client-side CSV builder + download (no deps).

function esc(value: unknown): string {
	const s = value == null ? '' : String(value);
	return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export function toCsv(headers: string[], rows: unknown[][]): string {
	const lines = [headers.map(esc).join(','), ...rows.map((r) => r.map(esc).join(','))];
	// Prepend BOM so Excel reads UTF-8 correctly.
	return '﻿' + lines.join('\r\n');
}

export function downloadCsv(filename: string, csv: string): void {
	const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
	const url = URL.createObjectURL(blob);
	const a = document.createElement('a');
	a.href = url;
	a.download = filename;
	a.click();
	URL.revokeObjectURL(url);
}
