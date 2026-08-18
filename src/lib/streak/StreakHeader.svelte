<script lang="ts">
	import Flame from './Flame.svelte';
	import Check from '@lucide/svelte/icons/check';

	interface Day {
		iso: string;
		done: boolean;
		isToday: boolean;
	}
	let { streak, todayDone, week }: { streak: number; todayDone: boolean; week: Day[] } = $props();

	const DOW = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
	function dow(iso: string): string {
		return DOW[new Date(`${iso}T00:00:00`).getDay()];
	}
</script>

<div class="header">
	<Flame size={108} dim={streak === 0} />
	<div class="count">{streak}</div>
	<div class="label">day streak{streak === 1 ? '' : ''}</div>

	<div class="week">
		{#each week as d, i (d.iso)}
			{@const runStart = !week[i - 1]?.done}
			{@const runEnd = !week[i + 1]?.done}
			<div class="cell">
				<span class="dow" class:today={d.isToday}>{dow(d.iso)}</span>
				<span
					class="dot"
					class:done={d.done}
					class:today={d.isToday}
					class:rl={d.done && runStart}
					class:rr={d.done && runEnd}
				>
					{#if d.done}<Check class="size-4" strokeWidth={3} />{/if}
				</span>
			</div>
		{/each}
	</div>

	{#if !todayDone}
		<p class="nudge">Write today's journal to keep your streak alive 🔥</p>
	{:else}
		<p class="nudge done">Logged today — streak safe! 🎉</p>
	{/if}
</div>

<style>
	.header {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 0.15rem;
		padding: 0.5rem 0 1rem;
	}
	.count {
		margin-top: 0.4rem;
		font-size: 3.4rem;
		font-weight: 800;
		line-height: 1;
		letter-spacing: -0.02em;
		background: linear-gradient(180deg, #ffb01f, #ff7a2f);
		-webkit-background-clip: text;
		background-clip: text;
		color: transparent;
	}
	.label {
		font-size: 1.1rem;
		font-weight: 700;
		color: #ff8a3d;
	}
	.week {
		margin-top: 1rem;
		display: flex;
		gap: 0;
	}
	.cell {
		display: flex;
		width: 2.6rem;
		flex-direction: column;
		align-items: center;
		gap: 0.4rem;
	}
	.dow {
		font-size: 0.72rem;
		font-weight: 700;
		color: var(--muted-foreground);
	}
	.dow.today {
		color: #ff8a3d;
	}
	.dot {
		display: grid;
		height: 2rem;
		width: 2.6rem;
		place-items: center;
		border-radius: 9999px;
		background: color-mix(in oklch, var(--foreground) 8%, transparent);
		color: #3a2a00;
	}
	.dot.done {
		background: linear-gradient(180deg, #ffb01f, #ff8a1e);
		border-radius: 0;
	}
	.dot.done.rl {
		border-top-left-radius: 9999px;
		border-bottom-left-radius: 9999px;
	}
	.dot.done.rr {
		border-top-right-radius: 9999px;
		border-bottom-right-radius: 9999px;
	}
	.dot.today {
		box-shadow: 0 0 0 2.5px #ffc800;
	}
	.nudge {
		margin-top: 1.1rem;
		font-size: var(--text-sm);
		color: var(--muted-foreground);
	}
	.nudge.done {
		color: #29c267;
	}
</style>
