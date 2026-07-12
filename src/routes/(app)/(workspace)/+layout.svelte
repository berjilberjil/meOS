<script lang="ts">
	import { onDestroy } from 'svelte';
	import { page } from '$app/state';
	import { cn } from '$lib/utils';
	import { setHeaderTabs, clearHeaderTabs } from '$lib/stores/headerTabs.svelte';

	let { children } = $props();

	// To-dos & Goals are now captured inline via the editor's "/" slash menu and
	// reviewed on the Dashboard; their full pages live at /todos and /goals but are
	// intentionally off the tab bar.
	const tabs = [
		{ href: '/journal', label: 'Journal' },
		{ href: '/notes', label: 'Notes' }
	];

	// Publish to the desktop top bar; keep an in-content row for phones.
	setHeaderTabs(tabs);
	onDestroy(clearHeaderTabs);

	function active(href: string): boolean {
		const p = page.url.pathname;
		return p === href || p.startsWith(href + '/');
	}
</script>

<div class="flex h-full flex-col gap-4">
	<nav class="flex shrink-0 flex-wrap gap-1 border-b border-border pb-2 md:hidden">
		{#each tabs as t (t.href)}
			<a
				href={t.href}
				class={cn(
					'rounded-md px-3 py-1.5 text-sm transition-colors',
					active(t.href)
						? 'bg-secondary font-medium text-secondary-foreground'
						: 'text-muted-foreground hover:bg-secondary/50'
				)}
			>
				{t.label}
			</a>
		{/each}
	</nav>
	<div class="min-h-0 flex-1 overflow-auto">
		{@render children()}
	</div>
</div>
