<script lang="ts">
	import { page } from '$app/state';
	import { cn } from '$lib/utils';
	import { onDestroy } from 'svelte';
	import { setHeaderTabs, clearHeaderTabs } from '$lib/stores/headerTabs.svelte';

	let { children } = $props();

	// Shares the "Assets & Liabilities" area's sub-tabs (belongings = inventory).
	const tabs = [
		{ href: '/assets', label: 'Assets & Liabilities' },
		{ href: '/belongings', label: 'Belongings' }
	];
	const headerToken = setHeaderTabs(tabs);
	onDestroy(() => clearHeaderTabs(headerToken));

	function active(href: string): boolean {
		return page.url.pathname === href || page.url.pathname.startsWith(href + '/');
	}
</script>

<div class="flex flex-col gap-4">
	<nav class="flex flex-wrap gap-1 border-b border-border pb-2 md:hidden">
		{#each tabs as t (t.href)}
			<a
				href={t.href}
				class={cn(
					'rounded-md px-3 py-1.5 text-sm transition-colors',
					active(t.href) ? 'bg-secondary text-secondary-foreground' : 'text-muted-foreground hover:bg-secondary/50'
				)}
			>
				{t.label}
			</a>
		{/each}
	</nav>
	{@render children()}
</div>
