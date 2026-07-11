<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { todayIso } from '$lib/finance/dates';
	import { gToKg, kgToG } from '$lib/health/units';
	import {
		listSessions, startSession, finishSession, removeSession,
		listSetsFor, addSet, removeSet,
		listPlans, listPlanDays, listPlanExercises, listExercises
	} from '$lib/gym/gym';
	import { sessionVolume } from '$lib/gym/progress';
	import { WEEKDAYS, type Exercise } from '$lib/gym/types';
	import { toast } from 'svelte-sonner';
	import Trash2 from '@lucide/svelte/icons/trash-2';
	import Check from '@lucide/svelte/icons/check';

	const qc = useQueryClient();
	const today = todayIso();
	const weekday = new Date().getDay();

	const sessionsQ = createQuery(() => ({ queryKey: ['sessions'], queryFn: () => listSessions() }));
	const plansQ = createQuery(() => ({ queryKey: ['plans'], queryFn: () => listPlans() }));
	const daysQ = createQuery(() => ({ queryKey: ['plan_days'], queryFn: () => listPlanDays() }));
	const pexQ = createQuery(() => ({ queryKey: ['plan_exercises'], queryFn: () => listPlanExercises() }));
	const exQ = createQuery(() => ({ queryKey: ['exercises'], queryFn: () => listExercises(), staleTime: 60 * 60_000 }));

	const exercises = $derived(exQ.data ?? []);
	const exById = $derived(new Map(exercises.map((e) => [e.id, e])));

	const current = $derived((sessionsQ.data ?? []).find((s) => s.logged_on === today && !s.ended_at) ?? null);

	const setsQ = createQuery(() => ({
		queryKey: ['session_sets', current?.id],
		queryFn: () => (current ? listSetsFor(current.id) : Promise.resolve([])),
		enabled: !!current
	}));
	const sessionSets = $derived(setsQ.data ?? []);

	function inv(...keys: (string | undefined)[]) {
		for (const k of keys) if (k) qc.invalidateQueries({ queryKey: [k] });
	}
	function invSets() {
		qc.invalidateQueries({ queryKey: ['session_sets', current?.id] });
	}

	// active plan + today's planned day
	const activePlan = $derived((plansQ.data ?? []).find((p) => p.active) ?? (plansQ.data ?? [])[0] ?? null);
	const todayDay = $derived((daysQ.data ?? []).find((d) => d.plan_id === activePlan?.id && d.weekday === weekday) ?? null);

	const startM = createMutation(() => ({
		mutationFn: (planDayId: string | null) => startSession(today, planDayId),
		onSuccess: () => inv('sessions')
	}));
	const finishM = createMutation(() => ({
		mutationFn: (id: string) => finishSession(id),
		onSuccess: () => { inv('sessions'); toast.success('Workout finished 💪'); }
	}));
	const cancelM = createMutation(() => ({ mutationFn: (id: string) => removeSession(id), onSuccess: () => inv('sessions') }));

	// exercises shown in the current session: planned + already-logged + manually added
	let addedIds = $state<string[]>([]);
	const activeExerciseIds = $derived.by(() => {
		const ids: string[] = [];
		if (current?.plan_day_id) {
			for (const pe of (pexQ.data ?? []).filter((p) => p.plan_day_id === current.plan_day_id).sort((a, b) => a.sort_order - b.sort_order))
				ids.push(pe.exercise_id);
		}
		for (const s of sessionSets) if (!ids.includes(s.exercise_id)) ids.push(s.exercise_id);
		for (const id of addedIds) if (!ids.includes(id)) ids.push(id);
		return ids;
	});

	function setsForEx(exId: string) {
		return sessionSets.filter((s) => s.exercise_id === exId).sort((a, b) => a.set_number - b.set_number);
	}
	function targetFor(exId: string): string {
		const pe = (pexQ.data ?? []).find((p) => p.plan_day_id === current?.plan_day_id && p.exercise_id === exId);
		return pe ? `${pe.target_sets} × ${pe.target_reps_low}-${pe.target_reps_high}` : '';
	}

	// per-exercise quick set entry (reps + kg), weight pre-fills from the last set
	let logging = $state<string | null>(null);
	let reps = $state(8);
	let kg = $state(20);
	function openLog(exId: string) {
		logging = exId;
		const last = setsForEx(exId).at(-1);
		reps = last?.reps ?? 8;
		kg = last ? gToKg(last.weight_g) : 20;
	}
	const setM = createMutation(() => ({
		mutationFn: (exId: string) =>
			addSet({ session_id: current!.id, exercise_id: exId, set_number: setsForEx(exId).length + 1, reps, weight_g: kgToG(kg) }),
		onSuccess: () => invSets()
	}));
	const delSetM = createMutation(() => ({ mutationFn: (id: string) => removeSet(id), onSuccess: () => invSets() }));

	let addExPick = $state('');
	function addExercise() {
		if (addExPick && !activeExerciseIds.includes(addExPick)) addedIds = [...addedIds, addExPick];
		addExPick = '';
	}

	const volumeKg = $derived(Math.round(sessionVolume(sessionSets) / 1000));
</script>

<div class="flex flex-col gap-4">
	<div>
		<h1 class="text-xl font-semibold tracking-tight">Workouts</h1>
		<p class="text-sm text-muted-foreground">Log your sets as you go.</p>
	</div>

	{#if !current}
		<Card.Root>
			<Card.Content class="flex flex-col gap-3 pt-6">
				{#if todayDay}
					<div class="text-sm">Today is <span class="font-semibold">{WEEKDAYS[weekday]}</span> — your plan says <span class="font-semibold">{todayDay.name}</span>.</div>
					<Button onclick={() => startM.mutate(todayDay.id)}>Start {todayDay.name}</Button>
				{:else}
					<div class="text-sm text-muted-foreground">No planned workout for {WEEKDAYS[weekday]} today.</div>
				{/if}
				<Button variant="outline" onclick={() => startM.mutate(null)}>Freestyle workout</Button>
			</Card.Content>
		</Card.Root>
	{:else}
		<Card.Root>
			<Card.Content class="flex items-center justify-between pt-6">
				<div>
					<div class="font-semibold">{todayDay && current.plan_day_id ? todayDay.name : 'Freestyle'} · today</div>
					<div class="text-xs text-muted-foreground">{sessionSets.length} sets · {volumeKg} kg volume</div>
				</div>
				<div class="flex gap-2">
					<Button size="sm" variant="ghost" onclick={() => cancelM.mutate(current.id)}>Cancel</Button>
					<Button size="sm" disabled={finishM.isPending} onclick={() => finishM.mutate(current.id)}>Finish</Button>
				</div>
			</Card.Content>
		</Card.Root>

		{#each activeExerciseIds as exId (exId)}
			<Card.Root>
				<Card.Header class="flex-row items-center justify-between pb-2">
					<Card.Title class="text-base">{exById.get(exId)?.name ?? '—'}</Card.Title>
					{#if targetFor(exId)}<span class="text-xs text-muted-foreground">target {targetFor(exId)}</span>{/if}
				</Card.Header>
				<Card.Content class="flex flex-col gap-1.5">
					{#each setsForEx(exId) as s (s.id)}
						<div class="flex items-center gap-2 text-sm">
							<span class="w-6 text-muted-foreground">#{s.set_number}</span>
							<span class="font-medium">{s.reps} reps</span>
							<span>× {gToKg(s.weight_g)} kg</span>
							<button class="ml-auto text-muted-foreground hover:text-destructive" onclick={() => delSetM.mutate(s.id)} aria-label="Remove set"><Trash2 class="size-4" /></button>
						</div>
					{/each}

					{#if logging === exId}
						<div class="flex items-end gap-2 border-t border-border pt-2">
							<label class="flex flex-col text-[11px] text-muted-foreground">reps<Input type="number" bind:value={reps} class="w-20" /></label>
							<label class="flex flex-col text-[11px] text-muted-foreground">kg<Input type="number" step="1.25" bind:value={kg} class="w-24" /></label>
							<Button size="sm" class="gap-1" disabled={setM.isPending} onclick={() => setM.mutate(exId)}><Check class="size-4" /> Log set</Button>
							<Button size="sm" variant="ghost" onclick={() => (logging = null)}>Done</Button>
						</div>
					{:else}
						<button class="w-fit text-xs text-primary hover:underline" onclick={() => openLog(exId)}>+ Add set</button>
					{/if}
				</Card.Content>
			</Card.Root>
		{/each}

		<Card.Root>
			<Card.Content class="flex flex-wrap items-center gap-2 pt-6">
				<select bind:value={addExPick} class="h-9 rounded-md border border-border bg-background px-2 text-sm">
					<option value="">Add an exercise…</option>
					{#each exercises as e (e.id)}<option value={e.id}>{e.name}</option>{/each}
				</select>
				<Button size="sm" variant="outline" disabled={!addExPick} onclick={addExercise}>Add</Button>
			</Card.Content>
		</Card.Root>
	{/if}
</div>
