<script lang="ts">
	interface Seg {
		label: string;
		value: number;
		color: string;
	}
	let {
		segments,
		centerTop = '',
		centerBottom = ''
	}: { segments: Seg[]; centerTop?: string; centerBottom?: string } = $props();

	const R = 58;
	const SW = 20;
	const C = 2 * Math.PI * R;
	const total = $derived(segments.reduce((s, x) => s + x.value, 0));
	const arcs = $derived.by(() => {
		let off = 0;
		return segments
			.filter((s) => s.value > 0)
			.map((s) => {
				const frac = total ? s.value / total : 0;
				const len = frac * C;
				const arc = { ...s, dash: `${len} ${C - len}`, offset: -off };
				off += len;
				return arc;
			});
	});
</script>

<div class="donut">
	<svg viewBox="0 0 160 160" class="ring">
		<circle cx="80" cy="80" r={R} fill="none" stroke="var(--muted)" stroke-width={SW} opacity="0.35" />
		<g transform="rotate(-90 80 80)">
			{#each arcs as a (a.label)}
				<circle
					cx="80"
					cy="80"
					r={R}
					fill="none"
					stroke={a.color}
					stroke-width={SW}
					stroke-dasharray={a.dash}
					stroke-dashoffset={a.offset}
					stroke-linecap="butt"
				/>
			{/each}
		</g>
		<text x="80" y="74" text-anchor="middle" class="c-top">{centerTop}</text>
		<text x="80" y="94" text-anchor="middle" class="c-bot">{centerBottom}</text>
	</svg>
</div>

<style>
	.donut {
		display: grid;
		place-items: center;
	}
	.ring {
		width: 160px;
		height: 160px;
	}
	.c-top {
		fill: var(--foreground);
		font-size: 22px;
		font-weight: 800;
	}
	.c-bot {
		fill: var(--muted-foreground);
		font-size: 11px;
	}
</style>
