<script lang="ts">
	import { page } from '$app/state';
	import { cn } from '$lib/utils';
	import { onDestroy } from 'svelte';
	import { setHeaderTabs, clearHeaderTabs } from '$lib/stores/headerTabs.svelte';

	let { children } = $props();

	const tabs = [
		{ href: '/fitness', label: 'Today' },
		{ href: '/fitness/food', label: 'Food' },
		{ href: '/fitness/diet', label: 'Diet' },
		{ href: '/fitness/workouts', label: 'Workouts' },
		{ href: '/fitness/plan', label: 'Plan' },
		{ href: '/fitness/progress', label: 'Progress' }
	];
	const headerToken = setHeaderTabs(tabs);
	onDestroy(() => clearHeaderTabs(headerToken));
</script>

<div class="flex flex-col gap-4">
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
