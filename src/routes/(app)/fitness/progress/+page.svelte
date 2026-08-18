<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { todayIso } from '$lib/finance/dates';
	import { gToKg } from '$lib/health/units';
	import { listSessions, listAllSets, listExercises } from '$lib/gym/gym';
	import { best1RM, bestWeight, muscleFrequency, sessionStreak, volumeSeries } from '$lib/gym/progress';
	import type { SessionSet } from '$lib/gym/types';

	const today = todayIso();
	const sessionsQ = createQuery(() => ({ queryKey: ['sessions'], queryFn: () => listSessions() }));
	const setsQ = createQuery(() => ({ queryKey: ['all_sets'], queryFn: () => listAllSets() }));
	const exQ = createQuery(() => ({ queryKey: ['exercises'], queryFn: () => listExercises(), staleTime: 60 * 60_000 }));

	const exById = $derived(new Map((exQ.data ?? []).map((e) => [e.id, e])));
	const dateBySession = $derived(new Map((sessionsQ.data ?? []).map((s) => [s.id, s.logged_on])));

	const setsWithDate = $derived(
		(setsQ.data ?? [])
			.map((s) => ({ ...s, logged_on: dateBySession.get(s.session_id) ?? '' }))
			.filter((s) => s.logged_on)
	);

	// streak from distinct session dates
	const streak = $derived(sessionStreak([...new Set((sessionsQ.data ?? []).map((s) => s.logged_on))], today));

	// weekly muscle frequency
	const muscleFreq = $derived(
		muscleFrequency(
			setsWithDate.map((s) => ({ logged_on: s.logged_on, muscle_group: exById.get(s.exercise_id)?.muscle_group ?? 'other' })),
			today
		)
	);

	// exercises that have logged sets, most recent first
	const trainedExerciseIds = $derived.by(() => {
		const seen: string[] = [];
		for (const s of [...setsWithDate].sort((a, b) => b.logged_on.localeCompare(a.logged_on)))
			if (!seen.includes(s.exercise_id)) seen.push(s.exercise_id);
		return seen;
	});

	let picked = $state<string>('');
	$effect(() => {
		if (!picked && trainedExerciseIds.length) picked = trainedExerciseIds[0];
	});

	const pickedSets = $derived(setsWithDate.filter((s) => s.exercise_id === picked) as (SessionSet & { logged_on: string })[]);
	const series = $derived(volumeSeries(pickedSets, picked));
	const maxVol = $derived(Math.max(1, ...series.map((p) => p.volume)));
</script>

<div class="flex flex-col gap-4">
	<div>
		<h1 class="text-xl font-semibold tracking-tight">Progress</h1>
		<p class="text-sm text-muted-foreground">Strength over time, PRs, and how often you hit each muscle.</p>
	</div>

	<div class="grid grid-cols-2 gap-3">
		<Card.Root>
			<Card.Content class="pt-6">
				<div class="text-3xl font-bold">{streak}🔥</div>
				<div class="text-xs text-muted-foreground">day workout streak</div>
			</Card.Content>
		</Card.Root>
		<Card.Root>
			<Card.Content class="pt-6">
				<div class="text-3xl font-bold">{Object.values(muscleFreq).reduce((a, b) => a + b, 0)}</div>
				<div class="text-xs text-muted-foreground">muscle-days this week</div>
			</Card.Content>
		</Card.Root>
	</div>

	<Card.Root>
		<Card.Header class="pb-2"><Card.Title class="text-base">This week by muscle</Card.Title></Card.Header>
		<Card.Content class="flex flex-wrap gap-2">
			{#each Object.entries(muscleFreq) as [m, n] (m)}
				<span class="rounded-full bg-secondary px-2.5 py-1 text-sm capitalize">{m} <span class="font-semibold">{n}×</span></span>
			{:else}
				<p class="text-sm text-muted-foreground">No sets logged this week yet.</p>
			{/each}
		</Card.Content>
	</Card.Root>

	<Card.Root>
		<Card.Header class="pb-2"><Card.Title class="text-base">Exercise progress</Card.Title></Card.Header>
		<Card.Content class="flex flex-col gap-3">
			{#if trainedExerciseIds.length}
				<select bind:value={picked} class="h-9 w-fit rounded-md border border-border bg-background px-2 text-sm">
					{#each trainedExerciseIds as id (id)}<option value={id}>{exById.get(id)?.name ?? '—'}</option>{/each}
				</select>
				<div class="flex gap-4 text-sm">
					<div><span class="text-muted-foreground">Best set </span><span class="font-semibold">{gToKg(bestWeight(pickedSets))} kg</span></div>
					<div><span class="text-muted-foreground">Est. 1RM </span><span class="font-semibold">{gToKg(best1RM(pickedSets))} kg</span></div>
				</div>
				<div class="flex items-end gap-1.5" style="height: 96px">
					{#each series as p (p.date)}
						<div class="flex flex-1 flex-col items-center justify-end gap-1" title="{p.date}: {Math.round(p.volume / 1000)} kg">
							<div class="w-full rounded-t bg-primary" style="height: {Math.max(4, Math.round((p.volume / maxVol) * 80))}px"></div>
							<span class="text-[9px] text-muted-foreground">{p.date.slice(5)}</span>
						</div>
					{/each}
				</div>
				<p class="text-xs text-muted-foreground">Daily training volume (weight × reps) for this exercise.</p>
			{:else}
				<p class="text-sm text-muted-foreground">Log a few workouts and your strength trends show up here.</p>
			{/if}
		</Card.Content>
	</Card.Root>
</div>
