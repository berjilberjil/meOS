<script lang="ts">
	import { onMount } from 'svelte';
	import { goto, preloadData } from '$app/navigation';
	import { page } from '$app/state';
	import { NAV_LEFT, NAV_RIGHT, DASHBOARD, type NavItem } from '$lib/nav';
	import * as haptics from '$lib/haptics';
	import { LONG_PRESS_MS, shouldAbortPress } from './navGesture';

	function isActive(item: { href: string; match?: string[] }): boolean {
		const p = page.url.pathname;
		if (item.href === '/dashboard') return p === '/dashboard';
		if (item.href === '/scan') return p === '/scan' || p.startsWith('/scan/');
		const paths = item.match ?? [item.href];
		return paths.some((h) => p === h || p.startsWith(h + '/'));
	}

	function tabTap(item: NavItem) {
		haptics.tick();
		goto(item.href);
	}

	// These are <button>s driven by goto (for the long-press fan menu), so
	// SvelteKit's `data-sveltekit-preload-data="hover"` (anchors only) never fires
	// for them — every tab switch used to cold-load the route chunk + data, and the
	// View Transition froze the page until it finished. Warm the route on intent
	// (hover / press) so navigation is already cached by the time goto runs.
	function warm(item: NavItem) {
		preloadData(item.href).catch(() => {});
	}

	// ---- Long-press fan menu (any nav button with a `menu`) ----
	// Hold a button → its quick-actions fan up; keep holding and slide onto one to
	// highlight it (haptic tick); release to open it. A plain tap just navigates.
	let openKey = $state<string | null>(null);
	let hoverIndex = $state(-1);
	let pressItem: NavItem | null = null;
	let startX = 0;
	let startY = 0;
	let timer: ReturnType<typeof setTimeout> | undefined;
	let capturedEl: HTMLElement | null = null;
	let capturedId: number | null = null;

	function releaseCapture() {
		try {
			if (capturedEl && capturedId !== null) capturedEl.releasePointerCapture?.(capturedId);
		} catch {
			/* already released */
		}
		capturedEl = null;
		capturedId = null;
	}

	function navDown(item: NavItem, e: PointerEvent) {
		warm(item); // head start for touch (no hover): press → preload → release navigates
		pressItem = item;
		startX = e.clientX;
		startY = e.clientY;
		capturedEl = e.currentTarget as HTMLElement;
		capturedId = e.pointerId;
		if (!item.menu) return; // plain tab — handled on pointerup
		timer = setTimeout(() => {
			openKey = item.key;
			hoverIndex = -1;
			haptics.impact();
			try {
				capturedEl?.setPointerCapture?.(capturedId as number);
			} catch {
				/* ignore */
			}
		}, LONG_PRESS_MS);
	}

	function navMove(e: PointerEvent) {
		if (openKey === null) {
			if (pressItem?.menu && shouldAbortPress(e.clientX - startX, e.clientY - startY)) {
				clearTimeout(timer); // a scroll, not a hold
			}
			return;
		}
		const el = document.elementFromPoint(e.clientX, e.clientY);
		const mi = el?.closest('[data-menu-index]') as HTMLElement | null;
		const idx = mi ? Number(mi.dataset.menuIndex) : -1;
		if (idx !== hoverIndex) {
			hoverIndex = idx;
			if (idx >= 0) haptics.tick();
		}
	}

	function navUp(item: NavItem) {
		clearTimeout(timer);
		if (openKey === null) {
			releaseCapture();
			tabTap(item); // plain tap
			return;
		}
		const chosen = hoverIndex >= 0 ? item.menu?.[hoverIndex] : null;
		openKey = null;
		hoverIndex = -1;
		releaseCapture();
		if (chosen) {
			haptics.success();
			goto(chosen.href);
		}
	}

	function navCancel() {
		clearTimeout(timer);
		openKey = null;
		hoverIndex = -1;
		releaseCapture();
	}

	const LEFT = NAV_LEFT;
	const RIGHT = NAV_RIGHT;

	// ---- Desktop auto-hide (web/hover devices only; touch stays pinned) ----
	let autoHide = $state(false);
	let revealed = $state(true);
	let hideTimer: ReturnType<typeof setTimeout> | undefined;

	function scheduleHide(delay = 2200) {
		clearTimeout(hideTimer);
		hideTimer = setTimeout(() => (revealed = false), delay);
	}
	function keepOpen() {
		clearTimeout(hideTimer);
		revealed = true;
	}
	function leave() {
		if (autoHide && openKey === null) scheduleHide(1200);
	}

	onMount(() => {
		const mq = window.matchMedia('(hover: hover) and (pointer: fine)');
		if (!mq.matches) return; // touch/iOS → always shown
		autoHide = true;
		revealed = false;
		const onMove = (e: MouseEvent) => {
			if (e.clientY >= window.innerHeight - 110) {
				revealed = true;
				scheduleHide();
			}
		};
		window.addEventListener('mousemove', onMove);
		return () => {
			window.removeEventListener('mousemove', onMove);
			clearTimeout(hideTimer);
		};
	});
</script>

{#snippet navButton(item: NavItem)}
	{@const active = isActive(item)}
	{@const isOpen = openKey === item.key}
	<button
		type="button"
		class="item"
		class:active
		class:menuopen={isOpen}
		aria-current={active ? 'page' : undefined}
		aria-label={item.menu
			? `${item.label} — tap to open, hold for quick actions`
			: item.label}
		onpointerenter={() => warm(item)}
		onpointerdown={(e) => navDown(item, e)}
		onpointermove={navMove}
		onpointerup={() => navUp(item)}
		onpointercancel={navCancel}
	>
		<span class="bar" aria-hidden="true"></span>
		<item.icon class="ic" />
		<span class="lbl">{item.label}</span>

		{#if isOpen && item.menu}
			<div class="menu" role="menu">
				{#each item.menu as mi, i (mi.href)}
					<span
						class="menu-item"
						class:on={hoverIndex === i}
						data-menu-index={i}
						style="--i: {item.menu.length - 1 - i}"
						role="menuitem"
					>
						{mi.label}
					</span>
				{/each}
			</div>
		{/if}
	</button>
{/snippet}

{#if autoHide && !revealed}
	<button class="peek" onmouseenter={keepOpen} aria-label="Show navigation">
		<span></span>
	</button>
{/if}

<nav
	class="mnav"
	class:menuing={openKey !== null}
	class:autohide={autoHide}
	class:revealed
	onmouseenter={keepOpen}
	onmouseleave={leave}
	aria-label="Primary"
>
	{#each LEFT as item (item.key)}
		{@render navButton(item)}
	{/each}

	<!-- elevated center: Today (no menu) -->
	<a
		href={DASHBOARD.href}
		class="center"
		class:active={isActive(DASHBOARD)}
		aria-current={isActive(DASHBOARD) ? 'page' : undefined}
		aria-label={DASHBOARD.label}
		onclick={(e) => {
			e.preventDefault();
			haptics.impact();
			goto(DASHBOARD.href);
		}}
	>
		<DASHBOARD.icon class="ic" />
	</a>

	{#each RIGHT as item (item.key)}
		{@render navButton(item)}
	{/each}
</nav>

<style>
	.mnav {
		position: fixed;
		bottom: 0;
		left: 0;
		right: 0;
		z-index: 40;
		box-sizing: border-box;
		max-width: 100vw;
		display: flex;
		align-items: stretch;
		justify-content: space-around;
		gap: 1px;
		border-top: 1px solid var(--border);
		background: color-mix(in oklch, var(--card) 88%, transparent);
		backdrop-filter: blur(8px);
		padding: 5px 2px calc(5px + env(safe-area-inset-bottom));
		overflow: visible; /* let the elevated button + menus escape upward */
	}
	/* Desktop only: a floating, centered, rounded pill that tucks away until the
	   pointer nears the bottom edge. Touch/iOS keeps the full-width bar above. */
	.mnav.autohide {
		left: 50%;
		right: auto;
		bottom: 16px;
		width: min(640px, calc(100% - 2rem));
		gap: 4px;
		padding: 6px 12px;
		border: 1px solid var(--border);
		border-radius: 9999px;
		box-shadow: 0 18px 40px -16px rgb(0 0 0 / 0.55);
		transform: translateX(-50%);
		transition:
			transform 0.32s var(--ease-entrance),
			opacity 0.28s ease;
	}
	.mnav.autohide:not(.revealed) {
		transform: translate(-50%, calc(100% + 32px));
		opacity: 0;
		pointer-events: none;
	}
	.mnav.autohide .item {
		border-radius: 9999px;
		padding: 6px 8px;
	}
	.mnav.autohide .item.active {
		background: color-mix(in oklch, var(--primary) 12%, transparent);
	}
	.mnav.autohide .bar {
		display: none;
	}
	.mnav.autohide .center {
		margin-top: -18px;
		height: 50px;
		width: 50px;
		max-width: 50px;
	}
	/* Hover affordance shown while the desktop bar is tucked away. */
	.peek {
		position: fixed;
		bottom: 0;
		left: 50%;
		z-index: 39;
		display: grid;
		height: 22px;
		width: 140px;
		transform: translateX(-50%);
		place-items: center;
		background: transparent;
		border: none;
		cursor: pointer;
	}
	.peek span {
		height: 4px;
		width: 48px;
		border-radius: 9999px;
		background: color-mix(in oklch, var(--foreground) 22%, transparent);
		transition: background-color var(--duration-fast) ease;
	}
	.peek:hover span {
		background: var(--primary);
	}

	.item {
		position: relative;
		display: flex;
		min-width: 0;
		flex: 1;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		border: 0;
		background: none;
		border-radius: var(--radius-md);
		padding: 5px 2px 3px;
		font-size: 10px;
		line-height: 1;
		color: var(--muted-foreground);
		text-decoration: none;
		cursor: pointer;
		touch-action: none; /* own the long-press; never scroll from the nav */
		-webkit-tap-highlight-color: transparent;
		-webkit-user-select: none;
		user-select: none;
		-webkit-touch-callout: none;
		transition: opacity var(--duration-fast) ease;
	}
	.item.active {
		color: var(--primary);
	}
	.item:active {
		background: var(--accent);
	}
	/* dim everything except the open menu's button */
	.mnav.menuing .item:not(.menuopen),
	.mnav.menuing .center {
		opacity: 0.35;
	}
	.bar {
		position: absolute;
		top: -1px;
		left: 50%;
		height: 2.5px;
		width: 0;
		transform: translateX(-50%);
		border-radius: 9999px;
		background: var(--primary);
		transition: width var(--duration-normal) var(--ease-entrance);
	}
	.item.active .bar {
		width: 26px;
	}
	.item :global(.ic) {
		height: 21px;
		width: 21px;
		transition: transform var(--duration-fast) var(--ease-entrance);
	}
	.item.menuopen :global(.ic) {
		transform: scale(1.12);
	}
	.item.active :global(.ic) {
		color: var(--primary);
	}
	.lbl {
		max-width: 100%;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	@media (max-width: 380px) {
		.lbl {
			font-size: 9px;
		}
		.item {
			padding-inline: 0;
		}
	}

	/* Elevated center Dashboard button */
	.center {
		position: relative;
		flex: 1;
		display: grid;
		place-items: center;
		align-self: center;
		justify-self: center;
		height: 54px;
		width: 54px;
		max-width: 54px;
		margin-top: -22px;
		border-radius: 9999px;
		background: var(--primary);
		color: var(--primary-foreground);
		text-decoration: none;
		box-shadow: 0 10px 24px -8px color-mix(in oklch, var(--primary) 70%, transparent);
		transition:
			transform var(--duration-fast) var(--ease-entrance),
			box-shadow var(--duration-fast) ease;
		touch-action: manipulation;
		-webkit-tap-highlight-color: transparent;
	}
	.center :global(.ic) {
		height: 24px;
		width: 24px;
	}
	.center:active {
		transform: scale(0.92);
	}
	.center.active {
		box-shadow:
			0 0 0 3px color-mix(in oklch, var(--primary) 30%, transparent),
			0 10px 24px -8px color-mix(in oklch, var(--primary) 70%, transparent);
	}

	/* Long-press fan menu: pills stacked upward from the pressed button. */
	.menu {
		position: absolute;
		bottom: calc(100% + 12px);
		left: 50%;
		transform: translateX(-50%);
		display: flex;
		flex-direction: column-reverse;
		align-items: center;
		gap: 7px;
		pointer-events: none; /* the captured pointer drives selection via hit-test */
		z-index: 1;
	}
	.menu-item {
		pointer-events: auto; /* must be hit-testable by elementFromPoint during the drag */
		white-space: nowrap;
		border-radius: 9999px;
		padding: 8px 14px;
		font-size: 12px;
		font-weight: 600;
		color: var(--foreground);
		background: color-mix(in oklch, var(--card) 96%, transparent);
		border: 1px solid var(--border);
		box-shadow: 0 10px 24px -12px rgb(0 0 0 / 0.5);
		transform-origin: bottom center;
		animation: menu-pop var(--duration-normal) var(--ease-entrance) backwards;
		animation-delay: calc(var(--i) * 28ms);
		transition:
			background-color var(--duration-fast) ease,
			color var(--duration-fast) ease,
			transform var(--duration-fast) var(--ease-entrance);
	}
	.menu-item.on {
		background: var(--primary);
		color: var(--primary-foreground);
		border-color: var(--primary);
		transform: scale(1.06);
	}
	@keyframes menu-pop {
		from {
			opacity: 0;
			transform: translateY(10px) scale(0.85);
		}
		to {
			opacity: 1;
			transform: translateY(0) scale(1);
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.menu-item,
		.bar,
		.center,
		.item :global(.ic) {
			animation: none;
			transition: none;
		}
	}
</style>
