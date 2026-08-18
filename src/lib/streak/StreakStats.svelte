<script lang="ts">
	import Check from '@lucide/svelte/icons/check';
	import Snowflake from '@lucide/svelte/icons/snowflake';
	import CalendarDays from '@lucide/svelte/icons/calendar-days';

	interface Props {
		daysPracticed: number;
		freezesUsed: number;
		streak: number;
		streakGoal: number;
	}
	let { daysPracticed, freezesUsed, streak, streakGoal }: Props = $props();

	const pct = $derived(Math.min(100, Math.round((streak / Math.max(1, streakGoal)) * 100)));
</script>

<div class="stats">
	<div class="row">
		<div class="stat">
			<span class="ic check"><Check class="size-4" strokeWidth={3} /></span>
			<div class="meta">
				<span class="val">{daysPracticed}</span>
				<span class="lbl">Days practiced</span>
			</div>
		</div>
		<div class="stat">
			<span class="ic freeze"><Snowflake class="size-4" /></span>
			<div class="meta">
				<span class="val">{freezesUsed}</span>
				<span class="lbl">Freezes used</span>
			</div>
		</div>
	</div>

	<div class="goal">
		<div class="goal-head">
			<span class="goal-title">Streak Goal</span>
			<span class="goal-num">{streak} / {streakGoal}</span>
		</div>
		<div class="track">
			<div class="fill" style="width: {pct}%"></div>
			<span class="cap"><CalendarDays class="size-4" /></span>
		</div>
	</div>
</div>

<style>
	.stats {
		display: flex;
		flex-direction: column;
		gap: 0.85rem;
	}
	.row {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 0.75rem;
	}
	.stat {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		border-radius: var(--radius-lg);
		border: 1px solid var(--border);
		background: var(--card);
		padding: 0.7rem 0.85rem;
	}
	.ic {
		display: grid;
		height: 28px;
		width: 28px;
		flex-shrink: 0;
		place-items: center;
		border-radius: 9999px;
		color: #fff;
	}
	.ic.check {
		background: #ff9a1e;
	}
	.ic.freeze {
		background: #1c9eef;
	}
	.meta {
		display: flex;
		flex-direction: column;
		line-height: 1.1;
	}
	.val {
		font-size: 1.3rem;
		font-weight: 800;
	}
	.lbl {
		font-size: var(--text-xs);
		color: var(--muted-foreground);
	}

	.goal {
		border-radius: var(--radius-lg);
		border: 1px solid var(--border);
		background: var(--card);
		padding: 0.8rem 0.9rem 1rem;
	}
	.goal-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		margin-bottom: 0.6rem;
	}
	.goal-title {
		font-size: var(--text-base);
		font-weight: 700;
	}
	.goal-num {
		font-size: var(--text-sm);
		font-weight: 700;
		color: #ff8a3d;
	}
	.track {
		position: relative;
		height: 16px;
		border-radius: 9999px;
		background: color-mix(in oklch, var(--foreground) 10%, transparent);
		overflow: visible;
	}
	.fill {
		height: 100%;
		border-radius: 9999px;
		background: linear-gradient(90deg, #ffb01f, #ff881e);
		transition: width 0.8s var(--ease-entrance);
		min-width: 16px;
	}
	.cap {
		position: absolute;
		right: -6px;
		top: 50%;
		display: grid;
		height: 26px;
		width: 26px;
		transform: translateY(-50%);
		place-items: center;
		border-radius: 6px;
		background: #ff881e;
		color: #fff;
		box-shadow: 0 0 0 3px var(--card);
	}
</style>
