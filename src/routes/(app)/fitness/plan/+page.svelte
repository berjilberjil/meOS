<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { cn } from '$lib/utils';
	import {
		listPlans, createPlan, removePlan,
		listPlanDays, createPlanDay, removePlanDay,
		listPlanExercises, addPlanExercise, removePlanExercise,
		listExercises
	} from '$lib/gym/gym';
	import { WEEKDAYS, type Exercise } from '$lib/gym/types';
	import { toast } from 'svelte-sonner';
	import Trash2 from '@lucide/svelte/icons/trash-2';

	const qc = useQueryClient();
	const plansQ = createQuery(() => ({ queryKey: ['plans'], queryFn: () => listPlans() }));
	const daysQ = createQuery(() => ({ queryKey: ['plan_days'], queryFn: () => listPlanDays() }));
	const pexQ = createQuery(() => ({ queryKey: ['plan_exercises'], queryFn: () => listPlanExercises() }));
	const exQ = createQuery(() => ({ queryKey: ['exercises'], queryFn: () => listExercises(), staleTime: 60 * 60_000 }));

	const plans = $derived(plansQ.data ?? []);
	const exercises = $derived(exQ.data ?? []);
	const exById = $derived(new Map(exercises.map((e) => [e.id, e])));

	let selectedPlan = $state<string | null>(null);
	$effect(() => {
		if (!selectedPlan && plans.length) selectedPlan = plans[0].id;
	});
	const days = $derived((daysQ.data ?? []).filter((d) => d.plan_id === selectedPlan).sort((a, b) => (a.weekday ?? 9) - (b.weekday ?? 9)));

	function inv(...keys: string[]) {
		for (const k of keys) qc.invalidateQueries({ queryKey: [k] });
	}

	let newPlan = $state('');
	const addPlanM = createMutation(() => ({
		mutationFn: () => createPlan(newPlan.trim()),
		onSuccess: (p) => { inv('plans'); newPlan = ''; selectedPlan = p.id; }
	}));
	const delPlanM = createMutation(() => ({ mutationFn: (id: string) => removePlan(id), onSuccess: () => { inv('plans'); selectedPlan = null; } }));

	let dayName = $state('');
	let dayWeekday = $state<number | null>(1);
	const addDayM = createMutation(() => ({
		mutationFn: () => createPlanDay(selectedPlan!, dayName.trim(), dayWeekday),
		onSuccess: () => { inv('plan_days'); dayName = ''; }
	}));
	const delDayM = createMutation(() => ({ mutationFn: (id: string) => removePlanDay(id), onSuccess: () => inv('plan_days') }));

	// add exercise to a day
	let addingTo = $state<string | null>(null);
	let exPick = $state('');
	let sets = $state(3);
	let repLo = $state(8);
	let repHi = $state(12);
	const addExM = createMutation(() => ({
		mutationFn: (dayId: string) =>
			addPlanExercise({ plan_day_id: dayId, exercise_id: exPick, target_sets: sets, target_reps_low: repLo, target_reps_high: repHi }),
		onSuccess: () => { inv('plan_exercises'); addingTo = null; toast.success('Added'); }
	}));
	const delExM = createMutation(() => ({ mutationFn: (id: string) => removePlanExercise(id), onSuccess: () => inv('plan_exercises') }));

	function exercisesForDay(dayId: string) {
		return (pexQ.data ?? []).filter((p) => p.plan_day_id === dayId).sort((a, b) => a.sort_order - b.sort_order);
	}
</script>

<div class="flex flex-col gap-4">
	<div>
		<h1 class="text-xl font-semibold tracking-tight">Plan</h1>
		<p class="text-sm text-muted-foreground">Build your weekly split — days, exercises, target sets & reps.</p>
	</div>

	<!-- Plans -->
	<Card.Root>
		<Card.Content class="flex flex-wrap items-center gap-2 pt-6">
			{#each plans as p (p.id)}
				<button
					class={cn('rounded-full border px-3 py-1.5 text-sm', selectedPlan === p.id ? 'border-primary bg-primary/10 font-semibold' : 'border-border')}
					onclick={() => (selectedPlan = p.id)}>{p.name}</button>
			{/each}
			<Input placeholder="New plan (e.g. PPL)" bind:value={newPlan} class="w-40" />
			<Button size="sm" disabled={!newPlan.trim() || addPlanM.isPending} onclick={() => addPlanM.mutate()}>Add plan</Button>
			{#if selectedPlan}
				<button class="ml-auto text-xs text-muted-foreground hover:text-destructive" onclick={() => delPlanM.mutate(selectedPlan!)}>Delete plan</button>
			{/if}
		</Card.Content>
	</Card.Root>

	{#if selectedPlan}
		<!-- Add day -->
		<Card.Root>
			<Card.Content class="flex flex-wrap items-end gap-2 pt-6">
				<Input placeholder="Day name (e.g. Push)" bind:value={dayName} class="w-40" />
				<select bind:value={dayWeekday} class="h-9 rounded-md border border-border bg-background px-2 text-sm">
					<option value={null}>Unscheduled</option>
					{#each WEEKDAYS as w, i (w)}<option value={i}>{w}</option>{/each}
				</select>
				<Button size="sm" disabled={!dayName.trim() || addDayM.isPending} onclick={() => addDayM.mutate()}>Add day</Button>
			</Card.Content>
		</Card.Root>

		<!-- Days -->
		{#each days as d (d.id)}
			<Card.Root>
				<Card.Header class="flex-row items-center justify-between pb-2">
					<Card.Title class="text-base">{d.weekday != null ? WEEKDAYS[d.weekday] + ' · ' : ''}{d.name}</Card.Title>
					<button class="text-muted-foreground hover:text-destructive" onclick={() => delDayM.mutate(d.id)} aria-label="Delete day"><Trash2 class="size-4" /></button>
				</Card.Header>
				<Card.Content class="flex flex-col gap-2">
					{#each exercisesForDay(d.id) as pe (pe.id)}
						<div class="flex items-center gap-2 text-sm">
							<span class="font-medium">{exById.get(pe.exercise_id)?.name ?? '—'}</span>
							<span class="text-muted-foreground">{pe.target_sets} × {pe.target_reps_low}-{pe.target_reps_high}</span>
							<button class="ml-auto text-muted-foreground hover:text-destructive" onclick={() => delExM.mutate(pe.id)} aria-label="Remove"><Trash2 class="size-4" /></button>
						</div>
					{:else}
						<p class="text-xs text-muted-foreground">No exercises yet.</p>
					{/each}

					{#if addingTo === d.id}
						<div class="flex flex-wrap items-end gap-2 border-t border-border pt-2">
							<select bind:value={exPick} class="h-9 rounded-md border border-border bg-background px-2 text-sm">
								<option value="">Pick exercise…</option>
								{#each exercises as e (e.id)}<option value={e.id}>{e.name}</option>{/each}
							</select>
							<label class="flex flex-col text-[11px] text-muted-foreground">sets<Input type="number" bind:value={sets} class="w-16" /></label>
							<label class="flex flex-col text-[11px] text-muted-foreground">rep low<Input type="number" bind:value={repLo} class="w-16" /></label>
							<label class="flex flex-col text-[11px] text-muted-foreground">rep high<Input type="number" bind:value={repHi} class="w-16" /></label>
							<Button size="sm" disabled={!exPick || addExM.isPending} onclick={() => addExM.mutate(d.id)}>Add</Button>
							<Button size="sm" variant="ghost" onclick={() => (addingTo = null)}>Cancel</Button>
						</div>
					{:else}
						<button class="w-fit text-xs text-primary hover:underline" onclick={() => { addingTo = d.id; exPick = ''; }}>+ Add exercise</button>
					{/if}
				</Card.Content>
			</Card.Root>
		{:else}
			<p class="text-sm text-muted-foreground">No days yet — add your first training day above.</p>
		{/each}
	{/if}
</div>
