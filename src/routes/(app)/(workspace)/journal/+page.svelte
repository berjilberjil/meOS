<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { toCsv, downloadCsv } from '$lib/export/csv';
	import { toast } from 'svelte-sonner';
	import Download from '@lucide/svelte/icons/download';
	import { listByMonth } from '$lib/journal/entries';
	import {
		computeStreak,
		monthDayStates,
		daysPracticed,
		lastSevenDays,
		localToday
	} from '$lib/streak/streak';
	import { loggedJournalDates, getStreakSettings, entryIdForDate } from '$lib/streak/data';
	import StreakHeader from '$lib/streak/StreakHeader.svelte';
	import StreakCalendar from '$lib/streak/StreakCalendar.svelte';
	import StreakStats from '$lib/streak/StreakStats.svelte';

	const today = localToday(new Date());
	let y = $state(Number(today.slice(0, 4)));
	let m = $state(Number(today.slice(5, 7)));
	const monthStr = $derived(`${y}-${String(m).padStart(2, '0')}`);
	const monthLabel = $derived(
		new Date(Date.UTC(y, m - 1, 1)).toLocaleDateString('en-US', { month: 'long', year: 'numeric' })
	);

	const streakQ = createQuery(() => ({
		queryKey: ['streak'],
		queryFn: async () => {
			const [logged, settings] = await Promise.all([loggedJournalDates(today), getStreakSettings()]);
			return { logged, settings };
		}
	}));
	const logged = $derived(streakQ.data?.logged ?? new Set<string>());
	const settings = $derived(streakQ.data?.settings ?? { freezes_total: 3, streak_goal: 150 });
	const result = $derived(computeStreak(logged, today, settings.freezes_total));
	const states = $derived(monthDayStates(y, m, logged, result.frozen, today));
	const practiced = $derived(daysPracticed(y, m, logged));
	const week = $derived(lastSevenDays(logged, today));

	function prevMonth() {
		if (m === 1) {
			m = 12;
			y -= 1;
		} else m -= 1;
	}
	function nextMonth() {
		if (m === 12) {
			m = 1;
			y += 1;
		} else m += 1;
	}
	async function pickDay(iso: string) {
		if (iso > today) return;
		const id = await entryIdForDate(iso);
		goto(id ? `/journal/${id}` : `/journal/new?date=${iso}`);
	}

	const entries = createQuery(() => ({ queryKey: ['journal', monthStr], queryFn: () => listByMonth(monthStr) }));
	let selected = $state<Set<string>>(new Set());
	function toggleSel(id: string) {
		const s = new Set(selected);
		s.has(id) ? s.delete(id) : s.add(id);
		selected = s;
	}
	function exportCsv() {
		const rows = (entries.data ?? [])
			.filter((e) => selected.has(e.id))
			.map((e) => [e.title || 'Untitled', e.occurred_on, e.mood ?? '', e.body_text]);
		downloadCsv(`journal-${monthStr}.csv`, toCsv(['Title', 'Date', 'Mood', 'Body'], rows));
		toast.success(`Exported ${rows.length} entr${rows.length === 1 ? 'y' : 'ies'} to CSV`);
	}
</script>

<div class="kn-stagger flex w-full flex-col gap-5">
	<div class="grid items-center gap-5 lg:grid-cols-2">
		<StreakHeader streak={result.current} todayDone={result.todayDone} {week} />
		<StreakCalendar
			year={y}
			month1={m}
			label={monthLabel}
			{states}
			onPrev={prevMonth}
			onNext={nextMonth}
			onPick={pickDay}
		/>
	</div>

	<StreakStats
		daysPracticed={practiced}
		freezesUsed={result.freezesUsed}
		streak={result.current}
		streakGoal={settings.streak_goal}
	/>

	<div class="flex items-center justify-between gap-2 pt-1">
		<span class="text-sm font-semibold tracking-tight">Entries · {monthLabel}</span>
		<div class="flex items-center gap-2">
			{#if selected.size}
				<Button variant="outline" size="sm" class="gap-1.5" onclick={exportCsv}>
					<Download class="size-3.5" /> Export {selected.size}
				</Button>
			{/if}
			<Button size="sm" onclick={() => pickDay(today)}>Today's entry</Button>
		</div>
	</div>

	<div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
		{#each entries.data ?? [] as e (e.id)}
			<div class="relative">
				<input
					type="checkbox"
					class="absolute left-3 top-4 z-10 size-4 cursor-pointer"
					style="accent-color: var(--primary);"
					checked={selected.has(e.id)}
					onclick={(ev) => ev.stopPropagation()}
					onchange={() => toggleSel(e.id)}
					aria-label="Select entry"
				/>
				<a href="/journal/{e.id}">
					<Card.Root class="h-full transition-colors hover:bg-secondary/40">
						<Card.Header>
							<Card.Title class="pl-7 text-base">
								{e.title || 'Untitled'}
								{#if e.mood}<span class="ml-2 text-xs capitalize text-muted-foreground">· {e.mood}</span>{/if}
							</Card.Title>
							<Card.Description class="pl-7">{e.occurred_on}</Card.Description>
						</Card.Header>
						{#if e.body_text}
							<Card.Content><p class="line-clamp-2 text-sm text-muted-foreground">{e.body_text}</p></Card.Content>
						{/if}
					</Card.Root>
				</a>
			</div>
		{:else}
			<p class="col-span-full py-6 text-center text-sm text-muted-foreground">No entries this month. Tap a day to start.</p>
		{/each}
	</div>
</div>
