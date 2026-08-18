<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { toPaise, formatINR } from '$lib/money';
	import { accountsRepo } from '$lib/finance/accounts';
	import type { Account, AccountType } from '$lib/finance/types';

	const qc = useQueryClient();
	const accounts = createQuery(() => ({ queryKey: ['finance', 'accounts'], queryFn: () => accountsRepo.list() }));

	let name = $state('');
	let type = $state<AccountType>('bank');
	let opening = $state('');

	const add = createMutation(() => ({
		mutationFn: () => {
			const paise = toPaise(Number(opening) || 0);
			return accountsRepo.create({
				name,
				type,
				opening_balance_paise: paise,
				balance_paise: paise
			} as Partial<Account>);
		},
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['finance'] });
			name = '';
			opening = '';
		}
	}));
</script>

<div class="flex flex-col gap-4">
	<Card.Root>
		<Card.Header><Card.Title>Add account</Card.Title></Card.Header>
		<Card.Content class="flex flex-wrap items-end gap-2">
			<Input placeholder="Name (e.g. HDFC)" bind:value={name} class="w-40" />
			<select bind:value={type} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				{#each ['bank', 'cash', 'upi', 'credit_card', 'wallet'] as t}
					<option value={t}>{t}</option>
				{/each}
			</select>
			<Input type="number" placeholder="Opening ₹" bind:value={opening} class="w-32" />
			<Button disabled={!name || add.isPending} onclick={() => add.mutate()}>Add</Button>
		</Card.Content>
	</Card.Root>

	<div class="kn-stagger grid gap-2 sm:grid-cols-2">
		{#each accounts.data ?? [] as a (a.id)}
			<Card.Root>
				<Card.Header>
					<Card.Title class="text-base">{a.name}</Card.Title>
					<Card.Description>{a.type}</Card.Description>
				</Card.Header>
				<Card.Content>
					<span class="text-xl font-semibold">{formatINR(a.balance_paise)}</span>
				</Card.Content>
			</Card.Root>
		{/each}
	</div>
</div>
