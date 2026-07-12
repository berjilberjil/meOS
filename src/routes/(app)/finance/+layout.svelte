<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { page } from '$app/state';
	import { cn } from '$lib/utils';
	import { seedDefaultCategories } from '$lib/finance/categories';
	import { reconcileAll } from '$lib/finance/accounts';
	import { runCatchUp } from '$lib/finance/recurring';
	import { setHeaderTabs, clearHeaderTabs } from '$lib/stores/headerTabs.svelte';

	let { children } = $props();

	const tabs = [
		{ href: '/finance', label: 'Overview' },
		{ href: '/finance/transactions', label: 'Transactions' },
		{ href: '/finance/recurring', label: 'Recurring' },
		{ href: '/finance/accounts', label: 'Accounts' },
		{ href: '/finance/budgets', label: 'Budgets' },
		{ href: '/finance/goals', label: 'Goals' },
		{ href: '/finance/investments', label: 'Investments' }
	];

	// Desktop: tabs in the top bar. Phones: keep the in-content row below.
	const headerToken = setHeaderTabs(tabs);
	onDestroy(() => clearHeaderTabs(headerToken));

	onMount(async () => {
		if (!navigator.onLine) return;
		await seedDefaultCategories();
		await runCatchUp();
		await reconcileAll();
	});
</script>

<div class="kn-stagger flex flex-col gap-4">
	<nav class="flex flex-wrap gap-1 border-b border-border pb-2 md:hidden">
		{#each tabs as t (t.href)}
			<a
				href={t.href}
				class={cn(
					'rounded-md px-3 py-1.5 text-sm transition-colors',
					page.url.pathname === t.href
						? 'bg-secondary text-secondary-foreground'
						: 'text-muted-foreground hover:bg-secondary/50'
				)}
			>
				{t.label}
			</a>
		{/each}
	</nav>
	{@render children()}
</div>
