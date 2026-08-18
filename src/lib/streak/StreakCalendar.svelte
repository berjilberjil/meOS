<script lang="ts">
	import type { DayState } from './streak';
	import ChevronLeft from '@lucide/svelte/icons/chevron-left';
	import ChevronRight from '@lucide/svelte/icons/chevron-right';
	import Snowflake from '@lucide/svelte/icons/snowflake';

	interface Props {
		year: number;
		month1: number;
		label: string;
		states: Map<string, DayState>;
		onPrev: () => void;
		onNext: () => void;
		onPick: (iso: string) => void;
	}
	let { year, month1, label, states, onPrev, onNext, onPick }: Props = $props();

	interface Cell {
		iso: string | null;
		day: number;
		state: DayState | null;
	}

	const weeks = $derived.by(() => {
		const first = new Date(Date.UTC(year, month1 - 1, 1));
		const lead = first.getUTCDay(); // 0=Sun
		const total = new Date(Date.UTC(year, month1, 0)).getUTCDate();
		const cells: Cell[] = [];
		for (let i = 0; i < lead; i++) cells.push({ iso: null, day: 0, state: null });
		for (let d = 1; d <= total; d++) {
			const iso = `${year}-${String(month1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
			cells.push({ iso, day: d, state: states.get(iso) ?? null });
		}
		while (cells.length % 7 !== 0) cells.push({ iso: null, day: 0, state: null });
		const rows: Cell[][] = [];
		for (let i = 0; i < cells.length; i += 7) rows.push(cells.slice(i, i + 7));
		return rows;
	});

	const DOW = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
</script>

<div class="cal">
	<div class="bar">
		<button class="nav" onclick={onPrev} aria-label="Previous month"><ChevronLeft class="size-5" /></button>
		<span class="month">{label}</span>
		<button class="nav" onclick={onNext} aria-label="Next month"><ChevronRight class="size-5" /></button>
	</div>

	<div class="grid head">
		{#each DOW as d}<span class="dow">{d}</span>{/each}
	</div>

	{#each weeks as week, wi (wi)}
		<div class="grid">
			{#each week as c, ci (ci)}
				{@const logged = c.state === 'logged'}
				{@const lrun = logged && week[ci - 1]?.state === 'logged'}
				{@const rrun = logged && week[ci + 1]?.state === 'logged'}
				{#if !c.iso}
					<span class="cell empty"></span>
				{:else if c.state === 'future'}
					<span class="cell future">{c.day}</span>
				{:else}
					<button
						class="cell {c.state}"
						class:lrun
						class:rrun
						onclick={() => onPick(c.iso!)}
						aria-label="Open {c.iso}"
					>
						{#if c.state === 'frozen'}
							<Snowflake class="freeze-ic" />
						{:else}
							{c.day}
						{/if}
					</button>
				{/if}
			{/each}
		</div>
	{/each}
</div>

<style>
	.cal {
		border-radius: var(--radius-lg);
		border: 1px solid var(--border);
		background: color-mix(in oklch, var(--foreground) 3%, var(--card));
		padding: 0.85rem 0.75rem 1rem;
	}
	.bar {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0 0.25rem 0.6rem;
	}
	.month {
		font-size: 1.05rem;
		font-weight: 700;
	}
	.nav {
		display: grid;
		height: 2rem;
		width: 2rem;
		place-items: center;
		border-radius: var(--radius-md);
		color: var(--muted-foreground);
	}
	.nav:hover {
		background: var(--accent);
		color: var(--foreground);
	}
	.grid {
		display: grid;
		grid-template-columns: repeat(7, 1fr);
	}
	.head {
		margin-bottom: 0.35rem;
	}
	.dow {
		text-align: center;
		font-size: 0.72rem;
		font-weight: 700;
		color: var(--muted-foreground);
	}
	.cell {
		display: grid;
		height: 2.4rem;
		place-items: center;
		font-size: 0.85rem;
		font-weight: 700;
		color: var(--foreground);
		background: none;
		border: none;
	}
	.cell.empty {
		visibility: hidden;
	}
	.cell.future {
		color: color-mix(in oklch, var(--muted-foreground) 55%, transparent);
		font-weight: 600;
	}
	.cell.missed {
		color: color-mix(in oklch, var(--muted-foreground) 70%, transparent);
		font-weight: 600;
		cursor: pointer;
	}
	.cell.missed:hover {
		color: var(--foreground);
	}
	/* Logged — connected fire pill across consecutive days. */
	.cell.logged {
		color: #3a2300;
		background: linear-gradient(180deg, #ffb01f, #ff881e);
		border-radius: 9999px;
		cursor: pointer;
	}
	.cell.logged.lrun {
		border-top-left-radius: 0;
		border-bottom-left-radius: 0;
	}
	.cell.logged.rrun {
		border-top-right-radius: 0;
		border-bottom-right-radius: 0;
	}
	/* today (not yet logged) — ring */
	.cell.today {
		border-radius: 9999px;
		box-shadow: inset 0 0 0 2.5px #ffc800;
		color: #ff9a2f;
		cursor: pointer;
	}
	/* freeze — blue gem circle */
	.cell.frozen {
		border-radius: 9999px;
		background: linear-gradient(180deg, #5cc8ff, #1c9eef);
		color: #fff;
		cursor: pointer;
		margin: 2px;
		height: calc(2.4rem - 4px);
	}
	.cell :global(.freeze-ic) {
		height: 1.05rem;
		width: 1.05rem;
	}
</style>
