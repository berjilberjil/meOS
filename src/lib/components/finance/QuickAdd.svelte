<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Dialog from '$lib/components/ui/dialog';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { cn } from '$lib/utils';
	import { toPaise } from '$lib/money';
	import { accountsRepo } from '$lib/finance/accounts';
	import { categoriesRepo } from '$lib/finance/categories';
	import { createTransaction } from '$lib/finance/transactions';
	import type { TxnType } from '$lib/finance/types';
	import * as haptics from '$lib/haptics';

	const qc = useQueryClient();
	let open = $state(false);
	let amount = $state('');
	let type = $state<TxnType>('expense');
	let categoryId = $state<string | null>(null);
	let accountId = $state<string | null>(null);
	let toAccountId = $state<string | null>(null); // transfer destination

	const accounts = createQuery(() => ({ queryKey: ['finance', 'accounts'], queryFn: () => accountsRepo.list() }));
	const categories = createQuery(() => ({ queryKey: ['finance', 'categories'], queryFn: () => categoriesRepo.list() }));

	const visibleCats = $derived(
		(categories.data ?? []).filter((c) => (type === 'income' ? c.kind === 'income' : c.kind === 'expense'))
	);

	$effect(() => {
		if (!accountId && accounts.data?.length) accountId = accounts.data[0].id;
	});

	const save = createMutation(() => ({
		mutationFn: async () => {
			if (!accountId) throw new Error('Pick an account');
			if (type === 'transfer' && (!toAccountId || toAccountId === accountId))
				throw new Error('Pick a different destination account');
			return createTransaction({
				account_id: accountId,
				type,
				amount_paise: toPaise(Number(amount)),
				category_id: type === 'transfer' ? null : categoryId,
				transfer_account_id: type === 'transfer' ? toAccountId : null
			});
		},
		onSuccess: () => {
			haptics.success();
			qc.invalidateQueries({ queryKey: ['finance'] });
			amount = '';
			categoryId = null;
			open = false;
		},
		onError: () => haptics.warning()
	}));

	const canSave = $derived(
		Number(amount) > 0 && !!accountId && (type !== 'transfer' || (!!toAccountId && toAccountId !== accountId))
	);
</script>

<Button
	class="fixed bottom-[calc(5rem+env(safe-area-inset-bottom))] right-4 z-50 hidden h-14 w-14 rounded-full text-2xl shadow-lg md:inline-flex md:bottom-6 md:right-6"
	onclick={() => (open = true)}
	aria-label="Quick add transaction"
>
	+
</Button>

<Dialog.Root bind:open>
	<Dialog.Content class="max-w-sm">
		<Dialog.Header>
			<Dialog.Title>Quick add</Dialog.Title>
		</Dialog.Header>

		<div class="flex flex-col gap-3">
			<div class="flex gap-1">
				{#each ['expense', 'income', 'transfer'] as const as t}
					<button
						class={cn('flex-1 rounded-md px-2 py-1.5 text-sm', type === t ? 'bg-secondary' : 'text-muted-foreground')}
						onclick={() => (type = t)}
					>
						{t}
					</button>
				{/each}
			</div>

			<Input type="number" inputmode="decimal" placeholder="0.00" bind:value={amount} class="text-2xl h-14" />

			{#if type !== 'transfer'}
				<div class="flex flex-wrap gap-1">
					{#each visibleCats as c (c.id)}
						<button
							class={cn('rounded-full border px-3 py-1 text-xs', categoryId === c.id ? 'bg-secondary' : 'border-border')}
							onclick={() => (categoryId = c.id)}
						>
							{c.name}
						</button>
					{/each}
				</div>
			{/if}

			<select bind:value={accountId} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				{#each accounts.data ?? [] as a (a.id)}
					<option value={a.id}>{type === 'transfer' ? `From: ${a.name}` : a.name}</option>
				{/each}
			</select>

			{#if type === 'transfer'}
				<select bind:value={toAccountId} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
					<option value={null}>To: pick account…</option>
					{#each (accounts.data ?? []).filter((a) => a.id !== accountId) as a (a.id)}
						<option value={a.id}>To: {a.name}</option>
					{/each}
				</select>
			{/if}

			<Button disabled={!canSave || save.isPending} onclick={() => save.mutate()}>
				{save.isPending ? 'Saving…' : 'Save'}
			</Button>
		</div>
	</Dialog.Content>
</Dialog.Root>
