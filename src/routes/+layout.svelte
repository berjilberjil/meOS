<script lang="ts">
	import '../app.css';
	import { onMount } from 'svelte';
	import { onNavigate } from '$app/navigation';
	import { QueryClientProvider } from '@tanstack/svelte-query';
	import { Toaster } from '$lib/components/ui/sonner';
	import { queryClient } from '$lib/data/query-client';
	import { initTheme } from '$lib/stores/theme.svelte';
	import { initProfile } from '$lib/stores/profile.svelte';
	import { flush } from '$lib/data/sync-queue';
	import { SupabaseRepository } from '$lib/data/repository';

	let { children } = $props();

	// Smooth cross-page transitions via the View Transitions API (WebKit/iOS 18+).
	// Graceful no-op where unsupported; the CSS keyframes respect reduced-motion.
	onNavigate((navigation) => {
		if (!document.startViewTransition) return;
		return new Promise((resolve) => {
			document.startViewTransition(async () => {
				resolve();
				await navigation.complete;
			});
		});
	});

	const resolveRepo = (table: string) => new SupabaseRepository<{ id: string }>(table);

	onMount(() => {
		initTheme();
		initProfile();
		const onOnline = () => flush(resolveRepo);
		addEventListener('online', onOnline);
		return () => removeEventListener('online', onOnline);
	});
</script>

<svelte:head>
	<link rel="icon" href="/favicon.svg" />
</svelte:head>

<QueryClientProvider client={queryClient}>
	{@render children()}
	<Toaster position="bottom-center" />
</QueryClientProvider>
