<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Input } from '$lib/components/ui/input';
	import { Button } from '$lib/components/ui/button';
	import MonthNav from '$lib/components/finance/MonthNav.svelte';
	import TransactionRow from '$lib/components/finance/TransactionRow.svelte';
	import { monthKey, todayIso } from '$lib/finance/dates';
	import { listByMonth, deleteTransaction } from '$lib/finance/transactions';
	import { accountsRepo } from '$lib/finance/accounts';
	import { categoriesRepo } from '$lib/finance/categories';
	import type { Transaction } from '$lib/finance/types';

	const qc = useQueryClient();
	let month = $state(monthKey(todayIso()));
	let accountFilter = $state('');
	let search = $state('');

	const txns = createQuery(() => ({ queryKey: ['finance', 'txns', month], queryFn: () => listByMonth(month) }));
	const accounts = createQuery(() => ({ queryKey: ['finance', 'accounts'], queryFn: () => accountsRepo.list() }));
	const categories = createQuery(() => ({ queryKey: ['finance', 'categories'], queryFn: () => categoriesRepo.list() }));

	const accName = (id: string) => (accounts.data ?? []).find((a) => a.id === id)?.name ?? '';
	const catName = (id: string | null) => (id ? (categories.data ?? []).find((c) => c.id === id)?.name ?? '' : '');

	const filtered = $derived(
		(txns.data ?? []).filter((t) => {
			if (accountFilter && t.account_id !== accountFilter && t.transfer_account_id !== accountFilter) return false;
			if (search && !(`${t.note ?? ''} ${catName(t.category_id)}`.toLowerCase().includes(search.toLowerCase()))) return false;
			return true;
		})
	);

	const del = createMutation(() => ({
		mutationFn: (t: Transaction) => deleteTransaction(t),
		onSuccess: () => qc.invalidateQueries({ queryKey: ['finance'] })
	}));
</script>

<div class="flex flex-col gap-3">
	<MonthNav monthKey={month} onChange={(m) => (month = m)} />
	<div class="flex flex-wrap gap-2">
		<select bind:value={accountFilter} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
			<option value="">All accounts</option>
			{#each accounts.data ?? [] as a (a.id)}<option value={a.id}>{a.name}</option>{/each}
		</select>
		<Input placeholder="Search note/category" bind:value={search} class="w-48" />
	</div>

	<Card.Root>
		<Card.Content class="divide-y divide-border">
			{#each filtered as t (t.id)}
				<div class="flex items-center gap-2">
					<div class="flex-1">
						<TransactionRow txn={t} categoryName={catName(t.category_id)} accountName={accName(t.account_id)} />
					</div>
					<Button variant="ghost" size="sm" onclick={() => del.mutate(t)} aria-label="Delete">✕</Button>
				</div>
			{:else}
				<p class="py-6 text-center text-sm text-muted-foreground">No transactions this month.</p>
			{/each}
		</Card.Content>
	</Card.Root>
</div>
