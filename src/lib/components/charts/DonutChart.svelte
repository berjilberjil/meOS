<script lang="ts">
	import { donutDashArray } from './ring';
	type Segment = { label: string; value: number; color: string };
	let { segments, size = 160 }: { segments: Segment[]; size?: number } = $props();

	const stroke = 18;
	const r = $derived((size - stroke) / 2);
	const c = $derived(2 * Math.PI * r);
	const dashes = $derived(donutDashArray(segments.map((s) => s.value), c));
</script>

<div class="flex items-center gap-4">
	<svg width={size} height={size} viewBox="0 0 {size} {size}">
		<g transform="rotate(-90 {size / 2} {size / 2})">
			{#each segments as s, i (s.label)}
				<circle
					cx={size / 2}
					cy={size / 2}
					r={r}
					fill="none"
					stroke={s.color}
					stroke-width={stroke}
					stroke-dasharray="{dashes[i].dash} {dashes[i].gap}"
					stroke-dashoffset={dashes[i].offset}
				/>
			{/each}
		</g>
	</svg>
	<ul class="flex flex-col gap-1 text-xs">
		{#each segments as s (s.label)}
			<li class="flex items-center gap-2">
				<span class="inline-block h-2 w-2 rounded-full" style="background:{s.color}"></span>{s.label}
			</li>
		{/each}
	</ul>
</div>
