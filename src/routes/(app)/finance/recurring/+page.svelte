<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { toPaise, formatINR } from '$lib/money';
	import { todayIso } from '$lib/finance/dates';
	import { recurringRepo, listActiveSorted } from '$lib/finance/recurring';
	import { accountsRepo } from '$lib/finance/accounts';
	import { categoriesRepo } from '$lib/finance/categories';
	import type { Recurring, RecurringKind, Cadence } from '$lib/finance/types';

	const qc = useQueryClient();
	const items = createQuery(() => ({ queryKey: ['finance', 'recurring'], queryFn: () => listActiveSorted() }));
	const accounts = createQuery(() => ({ queryKey: ['finance', 'accounts'], queryFn: () => accountsRepo.list() }));
	const categories = createQuery(() => ({ queryKey: ['finance', 'categories'], queryFn: () => categoriesRepo.list() }));

	let kind = $state<RecurringKind>('expense');
	let name = $state('');
	let amount = $state('');
	let cadence = $state<Cadence>('monthly');
	let nextRunOn = $state(todayIso());
	let accountId = $state<string | null>(null);
	let categoryId = $state<string | null>(null);

	$effect(() => {
		if (!accountId && accounts.data?.length) accountId = accounts.data[0].id;
	});

	const add = createMutation(() => ({
		mutationFn: () => {
			if (!accountId) throw new Error('Pick an account');
			return recurringRepo.create({
				kind,
				name,
				amount_paise: toPaise(Number(amount)),
				account_id: accountId,
				category_id: categoryId,
				cadence,
				interval_days: cadence === 'custom' ? 30 : null,
				next_run_on: nextRunOn,
				active: true
			} as Partial<Recurring>);
		},
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['finance', 'recurring'] });
			name = '';
			amount = '';
		}
	}));

	const toggle = createMutation(() => ({
		mutationFn: (r: Recurring) => recurringRepo.update(r.id, { active: !r.active } as Partial<Recurring>),
		onSuccess: () => qc.invalidateQueries({ queryKey: ['finance', 'recurring'] })
	}));
</script>

<div class="flex flex-col gap-4">
	<Card.Root>
		<Card.Header><Card.Title>Add recurring</Card.Title></Card.Header>
		<Card.Content class="flex flex-wrap items-end gap-2">
			<select bind:value={kind} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				{#each ['income', 'expense', 'subscription'] as k}<option value={k}>{k}</option>{/each}
			</select>
			<Input placeholder="Name (e.g. Salary)" bind:value={name} class="w-40" />
			<Input type="number" placeholder="₹" bind:value={amount} class="w-28" />
			<select bind:value={cadence} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				{#each ['monthly', 'weekly', 'custom'] as c}<option value={c}>{c}</option>{/each}
			</select>
			<Input type="date" bind:value={nextRunOn} class="w-40" />
			<select bind:value={accountId} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				{#each accounts.data ?? [] as a (a.id)}<option value={a.id}>{a.name}</option>{/each}
			</select>
			<select bind:value={categoryId} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				<option value={null}>No category</option>
				{#each categories.data ?? [] as c (c.id)}<option value={c.id}>{c.name}</option>{/each}
			</select>
			<Button disabled={!name || !(Number(amount) > 0) || add.isPending} onclick={() => add.mutate()}>Add</Button>
		</Card.Content>
	</Card.Root>

	<div class="kn-stagger flex flex-col gap-2">
		{#each items.data ?? [] as r (r.id)}
			<Card.Root>
				<Card.Content class="flex items-center justify-between pt-4 text-sm">
					<div class="flex flex-col">
						<span class="font-medium">{r.name} <span class="text-xs text-muted-foreground">({r.kind})</span></span>
						<span class="text-xs text-muted-foreground">{formatINR(r.amount_paise)} · {r.cadence} · next {r.next_run_on}</span>
					</div>
					<Button variant="ghost" size="sm" onclick={() => toggle.mutate(r)}>{r.active ? 'Pause' : 'Resume'}</Button>
				</Card.Content>
			</Card.Root>
		{:else}
			<p class="py-6 text-center text-sm text-muted-foreground">No recurring items yet.</p>
		{/each}
	</div>
</div>
