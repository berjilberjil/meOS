<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import MonthNav from '$lib/components/finance/MonthNav.svelte';
	import MiniRingChart from '$lib/components/charts/MiniRingChart.svelte';
	import { toPaise, formatINR } from '$lib/money';
	import { monthKey, todayIso } from '$lib/finance/dates';
	import { budgetRollup } from '$lib/finance/budgets';
	import { categoriesRepo } from '$lib/finance/categories';
	import { listByMonth } from '$lib/finance/transactions';
	import type { Category } from '$lib/finance/types';

	const qc = useQueryClient();
	let month = $state(monthKey(todayIso()));
	let newName = $state('');

	const categories = createQuery(() => ({ queryKey: ['finance', 'categories'], queryFn: () => categoriesRepo.list() }));
	const txns = createQuery(() => ({ queryKey: ['finance', 'txns', month], queryFn: () => listByMonth(month) }));

	const lines = $derived(budgetRollup(categories.data ?? [], txns.data ?? []));

	const setBudget = createMutation(() => ({
		mutationFn: ({ id, rupees }: { id: string; rupees: number }) =>
			categoriesRepo.update(id, { monthly_budget_paise: toPaise(rupees) } as Partial<Category>),
		onSuccess: () => qc.invalidateQueries({ queryKey: ['finance', 'categories'] })
	}));

	const addCat = createMutation(() => ({
		mutationFn: () => categoriesRepo.create({ name: newName, kind: 'expense', monthly_budget_paise: 0 } as Partial<Category>),
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['finance', 'categories'] });
			newName = '';
		}
	}));
</script>

<div class="flex flex-col gap-4">
	<MonthNav monthKey={month} onChange={(m) => (month = m)} />

	<Card.Root>
		<Card.Header><Card.Title>Add category</Card.Title></Card.Header>
		<Card.Content class="flex gap-2">
			<Input placeholder="Category name" bind:value={newName} class="w-48" />
			<Button disabled={!newName || addCat.isPending} onclick={() => addCat.mutate()}>Add</Button>
		</Card.Content>
	</Card.Root>

	<div class="kn-stagger grid gap-2 sm:grid-cols-2">
		{#each lines as l (l.category_id)}
			<Card.Root>
				<Card.Content class="flex items-center gap-4 pt-4">
					<MiniRingChart value={l.spent_paise} max={l.budget_paise} />
					<div class="flex flex-1 flex-col gap-1">
						<span class="text-sm font-medium">{l.name}</span>
						<span class="text-xs text-muted-foreground">
							{formatINR(l.spent_paise)} / {formatINR(l.budget_paise)}
						</span>
						<Input
							type="number"
							placeholder="Monthly budget ₹"
							class="h-7 w-32 text-xs"
							onchange={(e) => setBudget.mutate({ id: l.category_id, rupees: Number((e.currentTarget as HTMLInputElement).value) })}
						/>
					</div>
				</Card.Content>
			</Card.Root>
		{/each}
	</div>
</div>
