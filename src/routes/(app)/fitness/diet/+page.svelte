<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { cn } from '$lib/utils';
	import { todayIso } from '$lib/finance/dates';
	import { dietStore } from '$lib/diet/diet';
	import { WEEKDAY_LABELS, dateForWeekday, shiftWeek, weekStartMonday, weekdayIndex } from '$lib/diet/week';
	import { planDayTotals, slotsForMeal } from '$lib/diet/plan';
	import { entryTotals, nutrientKeyById, groupValuesByFood, mgToG, goalPct } from '$lib/nutrition/calc';
	import { MEALS, type FoodItem, type Meal } from '$lib/nutrition/types';
	import { toast } from 'svelte-sonner';
	import Trash2 from '@lucide/svelte/icons/trash-2';
	import Plus from '@lucide/svelte/icons/plus';
	import Minus from '@lucide/svelte/icons/minus';
	import ChevronLeft from '@lucide/svelte/icons/chevron-left';
	import ChevronRight from '@lucide/svelte/icons/chevron-right';

	const qc = useQueryClient();
	const today = todayIso();
	const api = dietStore();

	let weekStart = $state(weekStartMonday(today));

	const foodsQ = createQuery(() => ({ queryKey: ['foods'], queryFn: () => api.listFoods(), staleTime: 60 * 60_000 }));
	const valuesQ = createQuery(() => ({ queryKey: ['food_values'], queryFn: () => api.listNutrientValues(), staleTime: 60 * 60_000 }));
	const nutrientsQ = createQuery(() => ({ queryKey: ['nutrients'], queryFn: () => api.listNutrients(), staleTime: 60 * 60_000 }));
	const goalsQ = createQuery(() => ({ queryKey: ['nutrition_goals'], queryFn: () => api.getNutritionGoals() }));
	const weekQ = createQuery(() => ({
		queryKey: ['diet_week', weekStart],
		queryFn: () => api.getWeekPlan(weekStart)
	}));

	const foods = $derived(foodsQ.data ?? []);
	const foodById = $derived(new Map(foods.map((f) => [f.id, f])));
	const keyById = $derived(nutrientKeyById(nutrientsQ.data ?? []));
	const valuesByFood = $derived(groupValuesByFood(valuesQ.data ?? []));
	const slots = $derived(weekQ.data?.slots ?? []);
	const goals = $derived(goalsQ.data);
	const todayWeekday = weekdayIndex(today);

	function kcalOf(foodId: string, quantity: number): number {
		const f = foodById.get(foodId);
		if (!f) return 0;
		return entryTotals(quantity, f, valuesByFood.get(foodId) ?? [], keyById).energy_kcal;
	}

	function proteinG(foodId: string, quantity: number): number {
		const f = foodById.get(foodId);
		if (!f) return 0;
		return mgToG(entryTotals(quantity, f, valuesByFood.get(foodId) ?? [], keyById).protein_mg);
	}

	function dayTotals(weekday: number) {
		return planDayTotals(slots, weekday, foodById, valuesByFood, keyById);
	}

	function invWeek() {
		qc.invalidateQueries({ queryKey: ['diet_week', weekStart] });
	}

	let editor = $state<{ weekday: number; meal: Meal } | null>(null);
	let search = $state('');
	let qty = $state(1);

	const results = $derived.by(() => {
		const q = search.trim().toLowerCase();
		if (!q) return [] as FoodItem[];
		return foods.filter((f) => f.name.toLowerCase().includes(q)).slice(0, 8);
	});

	const addM = createMutation(() => ({
		mutationFn: (food: FoodItem) =>
			api.addSlotFood({
				week_start: weekStart,
				weekday: editor!.weekday,
				meal: editor!.meal,
				food_id: food.id,
				quantity: qty
			}),
		onSuccess: (_s, food) => {
			invWeek();
			toast.success(`Added ${qty} × ${food.name}`);
			search = '';
			qty = 1;
		},
		onError: (e: Error) => toast.error(e.message)
	}));

	const removeM = createMutation(() => ({
		mutationFn: (id: string) => api.removeSlotFood(id),
		onSuccess: () => invWeek(),
		onError: (e: Error) => toast.error(e.message)
	}));

	const clearM = createMutation(() => ({
		mutationFn: () => api.clearSlot({ week_start: weekStart, weekday: editor!.weekday, meal: editor!.meal }),
		onSuccess: () => {
			invWeek();
			toast.success('Slot cleared');
		}
	}));

	const logM = createMutation(() => ({
		mutationFn: (input: { weekday: number; meal: Meal; date: string }) => api.logPlannedMeal(input),
		onSuccess: (rows) => {
			qc.invalidateQueries({ queryKey: ['food_log'] });
			toast.success(rows.length ? `Logged ${rows.length} item${rows.length === 1 ? '' : 's'}` : 'Nothing planned');
		},
		onError: (e: Error) => toast.error(e.message)
	}));

	function openSlot(weekday: number, meal: Meal) {
		editor = { weekday, meal };
		search = '';
		qty = 1;
	}

	const weekLabel = $derived(
		`${dateForWeekday(weekStart, 0).slice(5)} – ${dateForWeekday(weekStart, 6).slice(5)}`
	);

	const todayPlan = $derived(dayTotals(todayWeekday));
	const todayGoalPct = $derived(goalPct(todayPlan.energy_kcal, goals?.energy_kcal ?? null));
</script>

<div class="flex flex-col gap-4">
	<div class="flex flex-wrap items-end justify-between gap-3">
		<div>
			<h1 class="text-xl font-semibold tracking-tight">Diet</h1>
			<p class="text-sm text-muted-foreground">Weekly grid. Tap a meal to add food. Log a planned meal in one tap.</p>
		</div>
		<div class="flex flex-wrap items-center gap-2">
			{#if goals?.energy_kcal}
				<span class="rounded-full border border-border px-2.5 py-1 text-xs">
					Today planned {todayPlan.energy_kcal} / {goals.energy_kcal} kcal
					{#if todayGoalPct != null}· {todayGoalPct}%{/if}
					{#if goals.protein_mg}
						· {mgToG(todayPlan.protein_mg)} / {mgToG(goals.protein_mg)} g P
					{/if}
				</span>
			{/if}
			<div class="flex items-center gap-1">
				<Button variant="outline" size="icon-sm" onclick={() => (weekStart = shiftWeek(weekStart, -1))} aria-label="Previous week">
					<ChevronLeft />
				</Button>
				<Button variant="ghost" size="sm" onclick={() => (weekStart = weekStartMonday(today))}>{weekLabel}</Button>
				<Button variant="outline" size="icon-sm" onclick={() => (weekStart = shiftWeek(weekStart, 1))} aria-label="Next week">
					<ChevronRight />
				</Button>
			</div>
		</div>
	</div>

	<div class="overflow-x-auto" data-testid="diet-grid">
		<div class="grid min-w-[52rem] grid-cols-7 gap-2">
			{#each WEEKDAY_LABELS as label, weekday (label)}
				{@const date = dateForWeekday(weekStart, weekday)}
				{@const totals = dayTotals(weekday)}
				{@const isToday = date === today}
				<div
					class={cn(
						'flex flex-col gap-1.5 rounded-lg border border-border p-2',
						isToday && 'border-primary/50 bg-primary/5'
					)}
					data-testid={`diet-day-${weekday}`}
				>
					<div class="flex items-baseline justify-between">
						<div>
							<div class="text-xs font-medium">{label}</div>
							<div class="text-[11px] text-muted-foreground">{date.slice(5)}</div>
						</div>
						<div class="text-right text-[11px] text-muted-foreground">
							{totals.energy_kcal} kcal
							{#if totals.protein_mg}<div>{mgToG(totals.protein_mg)} g P</div>{/if}
						</div>
					</div>
					{#each MEALS as meal (meal)}
						{@const rows = slotsForMeal(slots, weekday, meal)}
						<button
							type="button"
							class={cn(
								'rounded-md border border-dashed border-border px-1.5 py-1 text-left hover:border-primary/50',
								rows.length && 'border-solid bg-background'
							)}
							data-testid={`diet-slot-${weekday}-${meal}`}
							onclick={() => openSlot(weekday, meal)}
						>
							<div class="text-[10px] font-medium capitalize text-muted-foreground">{meal}</div>
							{#if rows.length}
								{#each rows as row (row.id)}
									<div class="truncate text-[11px]">
										{row.quantity}× {foodById.get(row.food_id)?.name ?? '…'}
										<span class="text-muted-foreground">{kcalOf(row.food_id, row.quantity)}</span>
									</div>
								{/each}
							{:else}
								<div class="text-[11px] text-muted-foreground">add</div>
							{/if}
						</button>
						{#if isToday && rows.length}
							<Button
								variant="ghost"
								size="xs"
								class="h-6 justify-start px-1.5 text-[11px]"
								data-testid={`log-planned-${meal}`}
								disabled={logM.isPending}
								onclick={() => logM.mutate({ weekday, meal, date })}
							>
								Log {meal}
							</Button>
						{/if}
					{/each}
				</div>
			{/each}
		</div>
	</div>

	{#if editor}
		{@const openRows = slotsForMeal(slots, editor.weekday, editor.meal)}
		<Card.Root data-testid="diet-editor">
			<Card.Header class="pb-2">
				<Card.Title class="text-base capitalize">
					{WEEKDAY_LABELS[editor.weekday]} {editor.meal}
					<span class="font-normal text-muted-foreground">· {dateForWeekday(weekStart, editor.weekday)}</span>
				</Card.Title>
			</Card.Header>
			<Card.Content class="flex flex-col gap-3">
				{#if openRows.length}
					<div class="divide-y divide-border">
						{#each openRows as row (row.id)}
							<div class="flex items-center gap-2 py-1.5 text-sm">
								<span class="font-medium">{row.quantity} ×</span>
								<span>{foodById.get(row.food_id)?.name ?? '—'}</span>
								<span class="ml-auto text-muted-foreground"
									>{kcalOf(row.food_id, row.quantity)} kcal · {proteinG(row.food_id, row.quantity)} g P</span
								>
								<button class="icon-btn hover:text-destructive" onclick={() => removeM.mutate(row.id)} aria-label="Remove">
									<Trash2 class="size-4" />
								</button>
							</div>
						{/each}
					</div>
					<Button variant="ghost" size="sm" class="w-fit" onclick={() => clearM.mutate()}>Clear meal</Button>
				{/if}

				<Input placeholder="Search foods… (idli, chicken, whey)" bind:value={search} data-testid="diet-search" />
				{#if results.length}
					<div class="flex flex-col divide-y divide-border">
						{#each results as f (f.id)}
							<button
								class="flex items-center justify-between py-2 text-left text-sm hover:bg-secondary/40"
								onclick={() => addM.mutate(f)}
								data-testid={`diet-add-${f.name}`}
							>
								<span>{f.name}</span>
								<span class="text-xs text-muted-foreground">{f.default_serving_label} · {f.energy_kcal} kcal</span>
							</button>
						{/each}
					</div>
					<div class="flex items-center gap-2 text-xs text-muted-foreground">
						<span>qty</span>
						<button class="icon-btn" onclick={() => (qty = Math.max(0.5, Math.round((qty - 0.5) * 2) / 2))} aria-label="Less">
							<Minus class="size-4" />
						</button>
						<span class="w-8 text-center font-semibold text-foreground">{qty}</span>
						<button class="icon-btn" onclick={() => (qty = Math.round((qty + 0.5) * 2) / 2)} aria-label="More">
							<Plus class="size-4" />
						</button>
					</div>
				{/if}
				<Button variant="outline" size="sm" class="w-fit" onclick={() => (editor = null)}>Done</Button>
			</Card.Content>
		</Card.Root>
	{/if}
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
