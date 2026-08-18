<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { moduleNodes, MODULE_CHILDREN } from '$lib/mindmap/graph';
	import { radialLayout } from '$lib/mindmap/layout';
	import { MODULE_ICONS } from '$lib/nav';
	import ZoomIn from '@lucide/svelte/icons/zoom-in';
	import ZoomOut from '@lucide/svelte/icons/zoom-out';
	import Maximize from '@lucide/svelte/icons/maximize';
	import ArrowUpRight from '@lucide/svelte/icons/arrow-up-right';

	const STAGE_W = 1120;
	const STAGE_H = 760;
	const CX = STAGE_W / 2;
	const CY = STAGE_H / 2;
	const R1 = 244;
	const R2 = 134;
	const REACH = R1 + R2 + 56;

	const nodesQ = createQuery(() => ({ queryKey: ['mindmap', 'modules'], queryFn: () => moduleNodes() }));

	let expanded = $state<Set<string>>(new Set());
	let tx = $state(0);
	let ty = $state(0);
	let k = $state(1);

	const modules = $derived.by(() => {
		const data = nodesQ.data ?? [];
		const pts = radialLayout(data.length, R1, 0, 0);
		return data.map((n, i) => ({
			...n,
			x: pts[i].x,
			y: pts[i].y,
			angle: Math.atan2(pts[i].y, pts[i].x)
		}));
	});
	const total = $derived(modules.reduce((a, m) => a + m.count, 0));

	// Default to the fully-expanded view once the modules load.
	let autoExpanded = false;
	$effect(() => {
		if (!autoExpanded && modules.length) {
			autoExpanded = true;
			expanded = new Set(modules.map((m) => m.key));
		}
	});

	const children = $derived.by(() => {
		const out: { id: string; parent: string; label: string; href: string; x: number; y: number }[] = [];
		for (const m of modules) {
			if (!expanded.has(m.key)) continue;
			const kids = MODULE_CHILDREN[m.key] ?? [];
			const n = kids.length;
			if (!n) continue;
			const spread = Math.min(Math.PI * 0.92, 0.46 * n);
			const start = m.angle - spread / 2;
			kids.forEach((c, i) => {
				const a = n === 1 ? m.angle : start + (spread * i) / (n - 1);
				out.push({
					id: `${m.key}:${i}`,
					parent: m.key,
					label: c.label,
					href: c.href,
					x: m.x + R2 * Math.cos(a),
					y: m.y + R2 * Math.sin(a)
				});
			});
		}
		return out;
	});

	function toggle(key: string) {
		const s = new Set(expanded);
		s.has(key) ? s.delete(key) : s.add(key);
		expanded = s;
	}
	function clampK(v: number) {
		return Math.min(2, Math.max(0.5, Math.round(v * 100) / 100));
	}
	function zoom(d: number) {
		k = clampK(k + d);
	}
	function reset() {
		tx = 0;
		ty = 0;
		k = fitK;
		expanded = new Set();
	}

	// Pan with one finger, pinch-zoom with two. Tracks every active pointer so
	// touch never gets stuck mid-gesture.
	let dragging = $state(false);
	let sx = 0;
	let sy = 0;
	let stx = 0;
	let sty = 0;
	let pinchDist = 0;
	let pinchK = 1;
	const pointers = new Map<number, { x: number; y: number }>();

	function twoFingerDist() {
		const p = [...pointers.values()];
		if (p.length < 2) return 0;
		return Math.hypot(p[0].x - p[1].x, p[0].y - p[1].y);
	}
	function onPointerDown(e: PointerEvent) {
		const el = e.target as HTMLElement;
		if (el.closest('.controls')) return; // never fight the zoom buttons
		// Track every finger so a two-finger pinch works even when fingers land on
		// nodes (the map is dense). Only pan/capture when a lone finger is on empty space.
		pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
		if (pointers.size >= 2) {
			dragging = false; // hand off to pinch
			pinchDist = twoFingerDist();
			pinchK = k;
			return;
		}
		if (el.closest('[data-node]')) return; // lone finger on a node → let it tap
		dragging = true;
		sx = e.clientX;
		sy = e.clientY;
		stx = tx;
		sty = ty;
		(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
	}
	function onPointerMove(e: PointerEvent) {
		if (!pointers.has(e.pointerId)) return;
		pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
		if (pointers.size >= 2) {
			if (pinchDist > 0) k = clampK(pinchK * (twoFingerDist() / pinchDist));
		} else if (dragging) {
			tx = stx + (e.clientX - sx);
			ty = sty + (e.clientY - sy);
		}
	}
	function onPointerUp(e: PointerEvent) {
		pointers.delete(e.pointerId);
		if (pointers.size < 2) pinchDist = 0;
		if (pointers.size === 1) {
			// resume panning with the finger that's still down
			const [p] = [...pointers.values()];
			dragging = true;
			sx = p.x;
			sy = p.y;
			stx = tx;
			sty = ty;
		} else if (pointers.size === 0) {
			dragging = false;
		}
	}
	function onWheel(e: WheelEvent) {
		e.preventDefault();
		zoom(e.deltaY > 0 ? -0.12 : 0.12);
	}

	let cw = $state(0);
	let ch = $state(0);
	let fitted = false;
	let fitK = $state(1);
	$effect(() => {
		if (!cw || !ch) return;
		const f = clampK((Math.min(cw, ch) - 24) / (2 * REACH));
		fitK = f;
		if (!fitted) {
			fitted = true;
			k = f;
		}
	});
</script>

<div
	class="canvas"
	class:dragging
	role="application"
	aria-label="Life map — drag to pan, scroll to zoom, click a node to expand"
	bind:clientWidth={cw}
	bind:clientHeight={ch}
	onpointerdown={onPointerDown}
	onpointermove={onPointerMove}
	onpointerup={onPointerUp}
	onpointerleave={onPointerUp}
	onwheel={onWheel}
>
	<div
		class="viewport"
		style="transform: translate(-50%, -50%) translate({tx}px, {ty}px) scale({k});"
	>
		<div class="stage" style="width: {STAGE_W}px; height: {STAGE_H}px;">
			<svg class="edges" width={STAGE_W} height={STAGE_H} aria-hidden="true">
				{#each modules as m (m.key)}
					<line class="edge" x1={CX} y1={CY} x2={CX + m.x} y2={CY + m.y} />
				{/each}
				{#each children as c (c.id)}
					{@const p = modules.find((m) => m.key === c.parent)}
					{#if p}
						<line class="edge edge-child" x1={CX + p.x} y1={CY + p.y} x2={CX + c.x} y2={CY + c.y} />
					{/if}
				{/each}
			</svg>

			<div class="node center" data-node style="left: {CX}px; top: {CY}px;">
				<span class="center-title">You</span>
				<span class="center-sub">{total} items</span>
			</div>

			{#each modules as m (m.key)}
				{@const Icon = MODULE_ICONS[m.key]}
				{@const isOpen = expanded.has(m.key)}
				<button
					class="node module"
					class:expanded={isOpen}
					data-node
					aria-expanded={isOpen}
					aria-label="{m.label}, {m.count} items"
					style="left: {CX + m.x}px; top: {CY + m.y}px;"
					onclick={() => toggle(m.key)}
				>
					{#if Icon}<Icon class="m-ic" />{/if}
					<span class="m-label">{m.label}</span>
					<span class="m-count">{m.count}</span>
					<a
						class="m-open"
						href={m.href}
						aria-label="Open {m.label}"
						onclick={(e) => e.stopPropagation()}
						onpointerdown={(e) => e.stopPropagation()}
					>
						<ArrowUpRight class="size-3" />
					</a>
				</button>
			{/each}

			{#each children as c (c.id)}
				<a class="node child" data-node href={c.href} style="left: {CX + c.x}px; top: {CY + c.y}px;">
					{c.label}
				</a>
			{/each}
		</div>
	</div>

	<div class="controls">
		<button class="ctl" aria-label="Zoom in" onclick={() => zoom(0.15)}><ZoomIn class="size-4" /></button>
		<button class="ctl" aria-label="Zoom out" onclick={() => zoom(-0.15)}><ZoomOut class="size-4" /></button>
		<button class="ctl" aria-label="Reset view" onclick={reset}><Maximize class="size-4" /></button>
	</div>

	<p class="hint">Drag to pan · pinch or scroll to zoom · tap a node to expand</p>
</div>

<style>
	.canvas {
		position: relative;
		height: 100%;
		width: 100%;
		overflow: hidden;
		border-radius: var(--radius-lg);
		border: 1px solid var(--border);
		background:
			radial-gradient(circle at 50% 45%, color-mix(in oklch, var(--primary) 7%, transparent), transparent 60%),
			var(--card);
		cursor: grab;
		touch-action: none;
	}
	.canvas.dragging {
		cursor: grabbing;
	}

	.viewport {
		position: absolute;
		left: 50%;
		top: 50%;
		transform-origin: center;
		will-change: transform;
	}
	.stage {
		position: relative;
	}

	.edges {
		position: absolute;
		inset: 0;
		overflow: visible;
		pointer-events: none;
	}
	.edge {
		stroke: var(--border);
		stroke-width: 1.5;
	}
	.edge-child {
		stroke: var(--primary);
		opacity: 0.4;
		animation: edge-in var(--duration-slow) var(--ease-entrance) backwards;
	}

	.node {
		position: absolute;
		display: flex;
		transform: translate(-50%, -50%);
		transition: transform var(--duration-normal) var(--ease-entrance);
		will-change: transform;
	}

	.center {
		flex-direction: column;
		align-items: center;
		justify-content: center;
		height: 92px;
		width: 92px;
		border-radius: 9999px;
		background: var(--primary);
		color: var(--primary-foreground);
		box-shadow: 0 8px 24px -8px color-mix(in oklch, var(--primary) 60%, transparent);
		pointer-events: none;
	}
	.center-title {
		font-size: var(--text-base);
		font-weight: 600;
		line-height: 1;
	}
	.center-sub {
		margin-top: 3px;
		font-size: var(--text-xs);
		opacity: 0.8;
	}

	.module {
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 2px;
		height: 104px;
		width: 104px;
		border-radius: 9999px;
		border: 1.5px solid var(--border);
		background: var(--secondary);
		color: var(--foreground);
		cursor: pointer;
		text-align: center;
	}
	.module:hover {
		transform: translate(-50%, -50%) scale(1.06);
		border-color: var(--primary);
		box-shadow: 0 10px 26px -10px color-mix(in oklch, var(--primary) 50%, transparent);
	}
	.module:focus-visible {
		outline: 2px solid var(--ring);
		outline-offset: 2px;
	}
	.module.expanded {
		border-color: var(--primary);
		background: color-mix(in oklch, var(--primary) 12%, var(--secondary));
	}
	.module :global(.m-ic) {
		height: 20px;
		width: 20px;
		color: var(--muted-foreground);
		transition: color var(--duration-fast) ease;
	}
	.module:hover :global(.m-ic),
	.module.expanded :global(.m-ic) {
		color: var(--primary);
	}
	.m-label {
		font-size: var(--text-xs);
		font-weight: 500;
		line-height: 1.1;
	}
	.m-count {
		font-size: 10px;
		color: var(--muted-foreground);
		line-height: 1;
	}
	.m-open {
		position: absolute;
		top: 8px;
		right: 8px;
		display: grid;
		height: 18px;
		width: 18px;
		place-items: center;
		border-radius: 9999px;
		background: var(--primary);
		color: var(--primary-foreground);
		opacity: 0;
		transform: scale(0.7);
		transition:
			opacity var(--duration-fast) ease,
			transform var(--duration-fast) var(--ease-entrance);
	}
	.module:hover .m-open,
	.m-open:focus-visible {
		opacity: 1;
		transform: scale(1);
	}

	.child {
		align-items: center;
		justify-content: center;
		padding: 5px 11px;
		border-radius: 9999px;
		border: 1px solid var(--border);
		background: var(--card);
		color: var(--foreground);
		font-size: var(--text-xs);
		white-space: nowrap;
		text-decoration: none;
		animation: node-pop var(--duration-slow) var(--ease-entrance) backwards;
	}
	.child:hover {
		transform: translate(-50%, -50%) scale(1.08);
		border-color: var(--primary);
		color: var(--primary);
	}
	.child:focus-visible {
		outline: 2px solid var(--ring);
		outline-offset: 2px;
	}

	.controls {
		position: absolute;
		top: 12px;
		right: 12px;
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.ctl {
		display: grid;
		height: 30px;
		width: 30px;
		place-items: center;
		border-radius: var(--radius-md);
		border: 1px solid var(--border);
		background: color-mix(in oklch, var(--card) 80%, transparent);
		color: var(--muted-foreground);
		backdrop-filter: blur(6px);
		transition:
			color var(--duration-fast) ease,
			border-color var(--duration-fast) ease;
	}
	.ctl:hover {
		color: var(--primary);
		border-color: var(--primary);
	}
	.ctl:focus-visible {
		outline: 2px solid var(--ring);
		outline-offset: 2px;
	}

	.hint {
		position: absolute;
		bottom: 12px;
		left: 14px;
		font-size: var(--text-xs);
		color: var(--muted-foreground);
		pointer-events: none;
		user-select: none;
	}

	@keyframes node-pop {
		from {
			opacity: 0;
			transform: translate(-50%, -50%) scale(0.4);
		}
		to {
			opacity: 1;
			transform: translate(-50%, -50%) scale(1);
		}
	}
	@keyframes edge-in {
		from {
			opacity: 0;
		}
		to {
			opacity: 0.4;
		}
	}
</style>
