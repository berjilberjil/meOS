<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { cn } from '$lib/utils';
	import { todayIso } from '$lib/finance/dates';
	import {
		listNutrients,
		listFoods,
		listNutrientValues,
		listLogFor,
		recentFoodIds,
		logFood,
		deleteLog,
		createCustomFood,
		getNutritionGoals,
		saveNutritionGoals
	} from '$lib/nutrition/foods';
	import {
		dailyTotals,
		entryTotals,
		nutrientKeyById,
		groupValuesByFood,
		mgToG,
		goalPct
	} from '$lib/nutrition/calc';
	import { MEALS, FOOD_CATEGORIES, type FoodItem, type Meal } from '$lib/nutrition/types';
	import { toast } from 'svelte-sonner';
	import Trash2 from '@lucide/svelte/icons/trash-2';
	import Plus from '@lucide/svelte/icons/plus';
	import Minus from '@lucide/svelte/icons/minus';

	const qc = useQueryClient();
	const today = todayIso();

	const nutrientsQ = createQuery(() => ({ queryKey: ['nutrients'], queryFn: () => listNutrients(), staleTime: 60 * 60_000 }));
	const foodsQ = createQuery(() => ({ queryKey: ['foods'], queryFn: () => listFoods(), staleTime: 60 * 60_000 }));
	const valuesQ = createQuery(() => ({ queryKey: ['food_values'], queryFn: () => listNutrientValues(), staleTime: 60 * 60_000 }));
	const logQ = createQuery(() => ({ queryKey: ['food_log', today], queryFn: () => listLogFor(today) }));
	const recentQ = createQuery(() => ({ queryKey: ['food_recent'], queryFn: () => recentFoodIds(10) }));
	const goalsQ = createQuery(() => ({ queryKey: ['nutrition_goals'], queryFn: () => getNutritionGoals() }));

	function invalidateLog() {
		qc.invalidateQueries({ queryKey: ['food_log', today] });
		qc.invalidateQueries({ queryKey: ['food_recent'] });
	}

	const nutrients = $derived(nutrientsQ.data ?? []);
	const foods = $derived(foodsQ.data ?? []);
	const keyById = $derived(nutrientKeyById(nutrients));
	const valuesByFood = $derived(groupValuesByFood(valuesQ.data ?? []));
	const foodById = $derived(new Map(foods.map((f) => [f.id, f])));
	const goals = $derived(goalsQ.data ?? { energy_kcal: null, protein_mg: null, carb_mg: null, fat_mg: null, fiber_mg: null });

	const entries = $derived(logQ.data ?? []);
	const totals = $derived(dailyTotals(entries, foodById, valuesByFood, keyById));

	const recentFoods = $derived((recentQ.data ?? []).map((id) => foodById.get(id)).filter((f): f is FoodItem => !!f));

	// ---- search ----
	let search = $state('');
	const results = $derived.by(() => {
		const q = search.trim().toLowerCase();
		if (!q) return [] as FoodItem[];
		return foods.filter((f) => f.name.toLowerCase().includes(q)).slice(0, 8);
	});

	function mealOfDay(): Meal {
		const h = new Date().getHours();
		if (h < 11) return 'breakfast';
		if (h < 16) return 'lunch';
		if (h < 21) return 'dinner';
		return 'snack';
	}

	// ---- add sheet ----
	let picked = $state<FoodItem | null>(null);
	let qty = $state(1);
	let meal = $state<Meal>('breakfast');
	function openAdd(f: FoodItem) {
		picked = f;
		qty = 1;
		meal = mealOfDay();
	}
	const addM = createMutation(() => ({
		mutationFn: () => logFood({ food_id: picked!.id, quantity: qty, logged_on: today, meal }),
		onSuccess: () => {
			invalidateLog();
			toast.success(`Added ${qty} × ${picked!.name}`);
			picked = null;
			search = '';
		}
	}));

	const delM = createMutation(() => ({
		mutationFn: (id: string) => deleteLog(id),
		onSuccess: () => invalidateLog()
	}));

	function kcalOf(foodId: string, quantity: number): number {
		const f = foodById.get(foodId);
		if (!f) return 0;
		return entryTotals(quantity, f, valuesByFood.get(foodId) ?? [], keyById).energy_kcal;
	}

	// ---- custom food ----
	let showCustom = $state(false);
	let cName = $state('');
	let cCat = $state(FOOD_CATEGORIES[0]);
	let cServing = $state('1 serving');
	let cGrams = $state(100);
	let cKcal = $state(0);
	let cP = $state(0);
	let cC = $state(0);
	let cF = $state(0);
	let cFib = $state(0);
	const customM = createMutation(() => ({
		mutationFn: () =>
			createCustomFood(
				{ name: cName.trim(), category: cCat, default_serving_label: cServing, serving_grams: cGrams, energy_kcal: cKcal },
				{ protein_mg: cP * 1000, carb_mg: cC * 1000, fat_mg: cF * 1000, fiber_mg: cFib * 1000 },
				nutrients
			),
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['foods'] });
			qc.invalidateQueries({ queryKey: ['food_values'] });
			toast.success('Custom food added');
			cName = '';
			cKcal = cP = cC = cF = cFib = 0;
			showCustom = false;
		}
	}));

	// ---- goals ----
	let showGoals = $state(false);
	let gKcal = $state('');
	let gP = $state('');
	let seededGoals = false;
	$effect(() => {
		if (seededGoals || !goalsQ.data) return;
		gKcal = goalsQ.data.energy_kcal ? String(goalsQ.data.energy_kcal) : '';
		gP = goalsQ.data.protein_mg ? String(mgToG(goalsQ.data.protein_mg)) : '';
		seededGoals = true;
	});
	const goalsM = createMutation(() => ({
		mutationFn: () =>
			saveNutritionGoals({
				energy_kcal: gKcal ? Number(gKcal) : null,
				protein_mg: gP ? Math.round(Number(gP) * 1000) : null,
				carb_mg: goals.carb_mg,
				fat_mg: goals.fat_mg,
				fiber_mg: goals.fiber_mg
			}),
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['nutrition_goals'] });
			toast.success('Goals saved');
			showGoals = false;
		}
	}));

	const kcalPct = $derived(goalPct(totals.energy_kcal, goals.energy_kcal));
	const proteinPct = $derived(goalPct(totals.protein_mg, goals.protein_mg));

	const microList = $derived(
		nutrients
			.filter((n) => n.nutrient_group !== 'macro' && (totals.micros[n.key] ?? 0) > 0)
			.map((n) => ({ label: n.label, unit: n.unit, amount: totals.micros[n.key] }))
	);
</script>

<div class="flex flex-col gap-4">
	<div>
		<h1 class="text-xl font-semibold tracking-tight">Food</h1>
		<p class="text-sm text-muted-foreground">Log what you eat — macros & full micros, all estimated.</p>
	</div>

	<!-- Today's totals -->
	<Card.Root>
		<Card.Content class="flex flex-col gap-3 pt-6">
			<div class="flex items-end justify-between">
				<div>
					<div class="text-xs uppercase tracking-wide text-muted-foreground">Today</div>
					<div class="text-4xl font-bold tracking-tight">
						{totals.energy_kcal}<span class="text-lg font-medium text-muted-foreground"> kcal{goals.energy_kcal ? ` / ${goals.energy_kcal}` : ''}</span>
					</div>
				</div>
				<button class="text-xs text-primary hover:underline" onclick={() => (showGoals = !showGoals)}>Goals</button>
			</div>
			{#if kcalPct !== null}
				<div class="h-2 w-full overflow-hidden rounded-full bg-secondary">
					<div class="h-full rounded-full bg-primary transition-[width]" style="width: {kcalPct}%"></div>
				</div>
			{/if}
			<div class="grid grid-cols-4 gap-2 text-center text-sm">
				<div><div class="font-bold">{mgToG(totals.protein_mg)}g</div><div class="text-[11px] text-muted-foreground">protein{proteinPct !== null ? ` ${proteinPct}%` : ''}</div></div>
				<div><div class="font-bold">{mgToG(totals.carb_mg)}g</div><div class="text-[11px] text-muted-foreground">carbs</div></div>
				<div><div class="font-bold">{mgToG(totals.fat_mg)}g</div><div class="text-[11px] text-muted-foreground">fat</div></div>
				<div><div class="font-bold">{mgToG(totals.fiber_mg)}g</div><div class="text-[11px] text-muted-foreground">fiber</div></div>
			</div>
			{#if microList.length}
				<details>
					<summary class="cursor-pointer text-xs text-muted-foreground select-none">Vitamins & minerals today</summary>
					<div class="mt-2 flex flex-wrap gap-1.5">
						{#each microList as m (m.label)}
							<span class="rounded-full border border-border px-2 py-0.5 text-[11px]">{m.label} {m.amount}{m.unit}</span>
						{/each}
					</div>
				</details>
			{/if}

			{#if showGoals}
				<div class="flex flex-wrap items-end gap-2 border-t border-border pt-3">
					<label class="flex flex-col gap-1 text-xs text-muted-foreground">Calorie goal<Input type="number" bind:value={gKcal} class="w-28" placeholder="2200" /></label>
					<label class="flex flex-col gap-1 text-xs text-muted-foreground">Protein (g)<Input type="number" bind:value={gP} class="w-24" placeholder="140" /></label>
					<Button variant="outline" size="sm" disabled={goalsM.isPending} onclick={() => goalsM.mutate()}>Save</Button>
				</div>
			{/if}
		</Card.Content>
	</Card.Root>

	<!-- Quick add -->
	<Card.Root id="food-add">
		<Card.Content class="flex flex-col gap-3 pt-6">
			<Input placeholder="Search foods… (chapati, dosa, whey)" bind:value={search} />

			{#if picked}
				<div class="flex flex-wrap items-center gap-2 rounded-lg border border-primary/40 bg-primary/5 p-3">
					<span class="font-medium">{picked.name}</span>
					<span class="text-xs text-muted-foreground">{picked.default_serving_label}</span>
					<div class="flex items-center gap-1">
						<button class="icon-btn" onclick={() => (qty = Math.max(0.5, Math.round((qty - 0.5) * 2) / 2))} aria-label="Less"><Minus class="size-4" /></button>
						<span class="w-8 text-center font-semibold">{qty}</span>
						<button class="icon-btn" onclick={() => (qty = Math.round((qty + 0.5) * 2) / 2)} aria-label="More"><Plus class="size-4" /></button>
					</div>
					<select bind:value={meal} class="h-9 rounded-md border border-border bg-background px-2 text-sm">
						{#each MEALS as m (m)}<option value={m}>{m}</option>{/each}
					</select>
					<span class="text-xs text-muted-foreground">{kcalOf(picked.id, qty)} kcal</span>
					<Button size="sm" class="ml-auto" disabled={addM.isPending} onclick={() => addM.mutate()}>Add</Button>
					<Button size="sm" variant="ghost" onclick={() => (picked = null)}>Cancel</Button>
				</div>
			{/if}

			{#if results.length}
				<div class="flex flex-col divide-y divide-border">
					{#each results as f (f.id)}
						<button class="flex items-center justify-between py-2 text-left text-sm hover:bg-secondary/40" onclick={() => openAdd(f)}>
							<span>{f.name}</span>
							<span class="text-xs text-muted-foreground">{f.default_serving_label} · {f.energy_kcal} kcal</span>
						</button>
					{/each}
				</div>
			{:else if !search && recentFoods.length}
				<div>
					<div class="mb-1.5 text-xs text-muted-foreground">Recent</div>
					<div class="flex flex-wrap gap-1.5">
						{#each recentFoods as f (f.id)}
							<button class="rounded-full border border-border px-3 py-1 text-sm hover:border-primary" onclick={() => openAdd(f)}>{f.name}</button>
						{/each}
					</div>
				</div>
			{/if}

			<button class="w-fit text-xs text-muted-foreground hover:underline" onclick={() => (showCustom = !showCustom)}>
				Can't find it? Add a custom food
			</button>

			{#if showCustom}
				<div class="flex flex-col gap-2 border-t border-border pt-3">
					<div class="flex flex-wrap gap-2">
						<Input placeholder="Name" bind:value={cName} class="w-48" />
						<select bind:value={cCat} class="h-9 rounded-md border border-border bg-background px-2 text-sm">
							{#each FOOD_CATEGORIES as c (c)}<option value={c}>{c}</option>{/each}
						</select>
						<Input placeholder="serving label" bind:value={cServing} class="w-32" />
						<Input type="number" placeholder="g/serving" bind:value={cGrams} class="w-24" />
					</div>
					<div class="flex flex-wrap gap-2">
						<label class="flex flex-col gap-1 text-xs text-muted-foreground">kcal<Input type="number" bind:value={cKcal} class="w-20" /></label>
						<label class="flex flex-col gap-1 text-xs text-muted-foreground">protein g<Input type="number" bind:value={cP} class="w-20" /></label>
						<label class="flex flex-col gap-1 text-xs text-muted-foreground">carb g<Input type="number" bind:value={cC} class="w-20" /></label>
						<label class="flex flex-col gap-1 text-xs text-muted-foreground">fat g<Input type="number" bind:value={cF} class="w-20" /></label>
						<label class="flex flex-col gap-1 text-xs text-muted-foreground">fiber g<Input type="number" bind:value={cFib} class="w-20" /></label>
					</div>
					<Button size="sm" class="w-fit" disabled={!cName.trim() || customM.isPending} onclick={() => customM.mutate()}>Save food</Button>
				</div>
			{/if}
		</Card.Content>
	</Card.Root>

	<!-- Today's log -->
	<Card.Root>
		<Card.Header class="pb-2"><Card.Title>Today's log</Card.Title></Card.Header>
		<Card.Content class="flex flex-col gap-3">
			{#each MEALS as m (m)}
				{@const rows = entries.filter((e) => e.meal === m)}
				{#if rows.length}
					<div>
						<div class="mb-1 text-xs font-medium capitalize text-muted-foreground">{m}</div>
						<div class="divide-y divide-border">
							{#each rows as e (e.id)}
								<div class="flex items-center gap-2 py-1.5 text-sm">
									<span class="font-medium">{e.quantity} ×</span>
									<span>{foodById.get(e.food_id)?.name ?? '—'}</span>
									<span class="ml-auto text-muted-foreground">{kcalOf(e.food_id, e.quantity)} kcal</span>
									<button class="icon-btn hover:text-destructive" onclick={() => delM.mutate(e.id)} aria-label="Remove"><Trash2 class="size-4" /></button>
								</div>
							{/each}
						</div>
					</div>
				{/if}
			{/each}
			{#if !entries.length}
				<p class="py-6 text-center text-sm text-muted-foreground">Nothing logged yet today.</p>
			{/if}
		</Card.Content>
	</Card.Root>
</div>

<style>
	.icon-btn {
		display: grid;
		place-items: center;
		padding: 4px;
		border-radius: var(--radius-md);
		color: var(--muted-foreground);
	}
	.icon-btn:hover {
		background: var(--secondary);
	}
</style>
