<script lang="ts">
	import { ringFraction } from './ring';
	let {
		value,
		max,
		size = 56,
		color = 'oklch(0.72 0.15 150)',
		label = ''
	}: { value: number; max: number; size?: number; color?: string; label?: string } = $props();

	const stroke = 6;
	const r = $derived((size - stroke) / 2);
	const c = $derived(2 * Math.PI * r);
	const frac = $derived(ringFraction(value, max));
	const over = $derived(max > 0 && value > max);
</script>

<div class="flex flex-col items-center gap-1">
	<svg width={size} height={size} viewBox="0 0 {size} {size}">
		<circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--muted)" stroke-width={stroke} />
		<circle
			cx={size / 2}
			cy={size / 2}
			r={r}
			fill="none"
			stroke={over ? 'oklch(0.65 0.16 25)' : color}
			stroke-width={stroke}
			stroke-linecap="round"
			stroke-dasharray="{c * frac} {c * (1 - frac)}"
			stroke-dashoffset={c * 0.25}
			transform="rotate(-90 {size / 2} {size / 2})"
		/>
	</svg>
	{#if label}<span class="text-xs text-muted-foreground">{label}</span>{/if}
</div>
