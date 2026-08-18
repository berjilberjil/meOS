<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import MiniRingChart from '$lib/components/charts/MiniRingChart.svelte';
	import { toPaise, formatINR } from '$lib/money';
	import { goalsRepo, contributeToGoal } from '$lib/finance/goals';
	import { accountsRepo } from '$lib/finance/accounts';
	import type { SavingsGoal } from '$lib/finance/types';

	const qc = useQueryClient();
	const goals = createQuery(() => ({ queryKey: ['finance', 'goals'], queryFn: () => goalsRepo.list() }));
	const accounts = createQuery(() => ({ queryKey: ['finance', 'accounts'], queryFn: () => accountsRepo.list() }));

	let name = $state('');
	let target = $state('');
	let contribAccount = $state<string | null>(null);

	$effect(() => {
		if (!contribAccount && accounts.data?.length) contribAccount = accounts.data[0].id;
	});

	const add = createMutation(() => ({
		mutationFn: () =>
			goalsRepo.create({ name, target_paise: toPaise(Number(target)), saved_paise: 0 } as Partial<SavingsGoal>),
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['finance', 'goals'] });
			name = '';
			target = '';
		}
	}));

	const contribute = createMutation(() => ({
		mutationFn: ({ goal, rupees }: { goal: SavingsGoal; rupees: number }) => {
			if (!contribAccount) throw new Error('Pick an account');
			return contributeToGoal(goal, toPaise(rupees), contribAccount);
		},
		onSuccess: () => qc.invalidateQueries({ queryKey: ['finance'] })
	}));
</script>

<div class="flex flex-col gap-4">
	<Card.Root>
		<Card.Header><Card.Title>Add goal</Card.Title></Card.Header>
		<Card.Content class="flex flex-wrap items-end gap-2">
			<Input placeholder="Name (e.g. Emergency fund)" bind:value={name} class="w-48" />
			<Input type="number" placeholder="Target ₹" bind:value={target} class="w-32" />
			<select bind:value={contribAccount} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				{#each accounts.data ?? [] as a (a.id)}<option value={a.id}>{a.name}</option>{/each}
			</select>
			<Button disabled={!name || !(Number(target) > 0) || add.isPending} onclick={() => add.mutate()}>Add</Button>
		</Card.Content>
	</Card.Root>

	<div class="kn-stagger grid gap-2 sm:grid-cols-2">
		{#each goals.data ?? [] as g (g.id)}
			<Card.Root>
				<Card.Content class="flex items-center gap-4 pt-4">
					<MiniRingChart value={g.saved_paise} max={g.target_paise} color="oklch(0.72 0.12 200)" />
					<div class="flex flex-1 flex-col gap-1">
						<span class="text-sm font-medium">{g.name}</span>
						<span class="text-xs text-muted-foreground">{formatINR(g.saved_paise)} / {formatINR(g.target_paise)}</span>
						<div class="flex gap-1">
							<Input type="number" placeholder="Add ₹" class="h-7 w-24 text-xs" id="contrib-{g.id}" />
							<Button
								size="sm"
								onclick={() => {
									const el = document.getElementById(`contrib-${g.id}`) as HTMLInputElement;
									const rupees = Number(el.value);
									if (rupees > 0) contribute.mutate({ goal: g, rupees });
									el.value = '';
								}}
							>
								Save
							</Button>
						</div>
					</div>
				</Card.Content>
			</Card.Root>
		{/each}
	</div>
</div>
