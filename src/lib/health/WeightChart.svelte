<script lang="ts">
	interface Point {
		iso: string;
		kg: number;
	}
	let { points, goal = null }: { points: Point[]; goal?: number | null } = $props();

	const W = 600;
	const H = 150;
	const padL = 10;
	const padR = 10;
	const padT = 16;
	const padB = 22;

	const view = $derived.by(() => {
		if (!points.length) return null;
		const vals = points.map((p) => p.kg);
		let min = Math.min(...vals);
		let max = Math.max(...vals);
		if (goal != null) {
			min = Math.min(min, goal);
			max = Math.max(max, goal);
		}
		if (max - min < 1) {
			max += 1;
			min -= 1;
		}
		const pad = (max - min) * 0.15;
		min -= pad;
		max += pad;
		const n = points.length;
		const x = (i: number) => padL + (n === 1 ? 0.5 : i / (n - 1)) * (W - padL - padR);
		const y = (v: number) => padT + (1 - (v - min) / (max - min)) * (H - padT - padB);
		const line = points.map((p, i) => `${x(i)},${y(p.kg)}`).join(' ');
		const area = `${padL},${H - padB} ${line} ${x(n - 1)},${H - padB}`;
		return { x, y, line, area, min, max, n };
	});
</script>

{#if view}
	<svg viewBox="0 0 {W} {H}" class="chart" preserveAspectRatio="none" role="img" aria-label="Weight trend">
		<defs>
			<linearGradient id="wfill" x1="0" y1="0" x2="0" y2="1">
				<stop offset="0" stop-color="var(--primary)" stop-opacity="0.28" />
				<stop offset="1" stop-color="var(--primary)" stop-opacity="0" />
			</linearGradient>
		</defs>
		{#if goal != null}
			<line x1={padL} x2={W - padR} y1={view.y(goal)} y2={view.y(goal)} stroke="#22c55e" stroke-width="1.5" stroke-dasharray="5 5" opacity="0.8" />
		{/if}
		<polygon points={view.area} fill="url(#wfill)" />
		<polyline points={view.line} fill="none" stroke="var(--primary)" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round" />
		{#each points as p, i (p.iso)}
			<circle cx={view.x(i)} cy={view.y(p.kg)} r="3.5" fill="var(--primary)" />
		{/each}
	</svg>
{:else}
	<p class="empty">Log your weight to see the trend.</p>
{/if}

<style>
	.chart {
		width: 100%;
		height: 150px;
	}
	.empty {
		padding: 2rem 0;
		text-align: center;
		font-size: var(--text-sm);
		color: var(--muted-foreground);
	}
</style>
