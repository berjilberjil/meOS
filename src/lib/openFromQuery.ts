// Quick-action deep links from the bottom-nav long-press menus.
// A page calls openSectionFromQuery on mount; when the URL carries ?add=<key>,
// the matching handler runs after the DOM has settled (scroll to + focus a form).

export function openSectionFromQuery(add: string | null, map: Record<string, () => void>): void {
	if (!add) return;
	const fn = map[add];
	if (!fn) return;
	// Two frames so query-driven content + layout have painted before we scroll.
	requestAnimationFrame(() => requestAnimationFrame(() => fn()));
}

/** Scroll a section into view and focus its first field (or click it). */
export function focusSection(id: string, opts: { click?: boolean } = {}): void {
	const el = document.getElementById(id);
	if (!el) return;
	el.scrollIntoView({ behavior: 'smooth', block: 'center' });
	// Prefer the meaningful first field — skip date/file inputs that tend to come first.
	const target = el.querySelector(
		'input:not([type=date]):not([type=file]):not([type=hidden]), textarea, button'
	) as HTMLElement | null;
	if (!target) return;
	if (opts.click) target.click();
	else target.focus();
}
