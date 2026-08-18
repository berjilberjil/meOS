<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import MonthNav from '$lib/components/finance/MonthNav.svelte';
	import MiniRingChart from '$lib/components/charts/MiniRingChart.svelte';
	import DonutChart from '$lib/components/charts/DonutChart.svelte';
	import TransactionRow from '$lib/components/finance/TransactionRow.svelte';
	import { formatINR } from '$lib/money';
	import { monthKey, todayIso } from '$lib/finance/dates';
	import { accountsRepo, netWorth } from '$lib/finance/accounts';
	import { categoriesRepo } from '$lib/finance/categories';
	import { listByMonth } from '$lib/finance/transactions';
	import { budgetRollup, budgetTotals } from '$lib/finance/budgets';
	import { listActiveSorted } from '$lib/finance/recurring';

	let month = $state(monthKey(todayIso()));

	const accounts = createQuery(() => ({ queryKey: ['finance', 'accounts'], queryFn: () => accountsRepo.list() }));
	const categories = createQuery(() => ({ queryKey: ['finance', 'categories'], queryFn: () => categoriesRepo.list() }));
	const txns = createQuery(() => ({ queryKey: ['finance', 'txns', month], queryFn: () => listByMonth(month) }));
	const recurring = createQuery(() => ({ queryKey: ['finance', 'recurring'], queryFn: () => listActiveSorted() }));

	const income = $derived((txns.data ?? []).filter((t) => t.type === 'income').reduce((s, t) => s + t.amount_paise, 0));
	const expense = $derived((txns.data ?? []).filter((t) => t.type === 'expense').reduce((s, t) => s + t.amount_paise, 0));
	const lines = $derived(budgetRollup(categories.data ?? [], txns.data ?? []));
	const totals = $derived(budgetTotals(lines));
	const accName = (id: string) => (accounts.data ?? []).find((a) => a.id === id)?.name ?? '';
	const catName = (id: string | null) => (id ? (categories.data ?? []).find((c) => c.id === id)?.name ?? '' : '');

	const donut = $derived(
		lines
			.filter((l) => l.spent_paise > 0)
			.map((l) => ({
				label: l.name,
				value: l.spent_paise,
				color: (categories.data ?? []).find((c) => c.id === l.category_id)?.color ?? 'oklch(0.6 0.02 260)'
			}))
	);
	const recent = $derived((txns.data ?? []).slice(0, 8));
</script>

<div class="kn-stagger flex flex-col gap-4">
	<MonthNav monthKey={month} onChange={(m) => (month = m)} />

	<div class="grid gap-3 sm:grid-cols-3">
		<Card.Root><Card.Header><Card.Description>Net worth</Card.Description><Card.Title class="text-2xl">{formatINR(netWorth(accounts.data ?? []))}</Card.Title></Card.Header></Card.Root>
		<Card.Root><Card.Header><Card.Description>Income</Card.Description><Card.Title class="text-2xl text-emerald-500">{formatINR(income)}</Card.Title></Card.Header></Card.Root>
		<Card.Root><Card.Header><Card.Description>Expense</Card.Description><Card.Title class="text-2xl text-rose-500">{formatINR(expense)}</Card.Title></Card.Header></Card.Root>
	</div>

	<div class="grid gap-3 sm:grid-cols-2">
		<Card.Root>
			<Card.Header><Card.Title class="text-base">Budget</Card.Title></Card.Header>
			<Card.Content class="flex items-center gap-4">
				<MiniRingChart value={totals.spent_paise} max={totals.budget_paise} size={88} />
				<span class="text-sm text-muted-foreground">{formatINR(totals.spent_paise)} / {formatINR(totals.budget_paise)}</span>
			</Card.Content>
		</Card.Root>
		<Card.Root>
			<Card.Header><Card.Title class="text-base">Spend by category</Card.Title></Card.Header>
			<Card.Content>
				{#if donut.length}<DonutChart segments={donut} />{:else}<p class="text-sm text-muted-foreground">No spend yet.</p>{/if}
			</Card.Content>
		</Card.Root>
	</div>

	<Card.Root>
		<Card.Header><Card.Title class="text-base">Accounts</Card.Title></Card.Header>
		<Card.Content class="flex flex-wrap gap-4">
			{#each accounts.data ?? [] as a (a.id)}
				<div class="flex flex-col"><span class="text-xs text-muted-foreground">{a.name}</span><span class="font-semibold">{formatINR(a.balance_paise)}</span></div>
			{/each}
		</Card.Content>
	</Card.Root>

	<Card.Root>
		<Card.Header><Card.Title class="text-base">Upcoming</Card.Title></Card.Header>
		<Card.Content class="divide-y divide-border">
			{#each (recurring.data ?? []).slice(0, 5) as r (r.id)}
				<div class="flex items-center justify-between py-2 text-sm">
					<span>{r.name} <span class="text-xs text-muted-foreground">· {r.next_run_on}</span></span>
					<span class={r.kind === 'income' ? 'text-emerald-500' : 'text-rose-500'}>{formatINR(r.amount_paise)}</span>
				</div>
			{:else}
				<p class="py-4 text-center text-sm text-muted-foreground">No recurring items.</p>
			{/each}
		</Card.Content>
	</Card.Root>

	<Card.Root>
		<Card.Header><Card.Title class="text-base">Recent</Card.Title></Card.Header>
		<Card.Content class="divide-y divide-border">
			{#each recent as t (t.id)}
				<TransactionRow txn={t} categoryName={catName(t.category_id)} accountName={accName(t.account_id)} />
			{:else}
				<p class="py-4 text-center text-sm text-muted-foreground">Nothing logged this month.</p>
			{/each}
		</Card.Content>
	</Card.Root>
</div>
