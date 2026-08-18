<script lang="ts">
	import { Spinner } from '$lib/components/ui/spinner';
	import { Toaster as Sonner, type ToasterProps as SonnerProps } from 'svelte-sonner';
	import { themeState } from '$lib/stores/theme.svelte';

	let { ...restProps }: SonnerProps = $props();

	// Follow the app's own theme (no mode-watcher / ModeWatcher needed).
	const theme = $derived<SonnerProps['theme']>(
		themeState.current === 'light' ? 'light' : themeState.current === 'system' ? 'system' : 'dark'
	);
</script>

<Sonner
	{theme}
	class="toaster group"
	style="--normal-bg: var(--color-popover); --normal-text: var(--color-popover-foreground); --normal-border: var(--color-border);"
	{...restProps}
	>{#snippet loadingIcon()}
		<Spinner size={16} />
	{/snippet}
	{#snippet successIcon()}{/snippet}
	{#snippet errorIcon()}{/snippet}
	{#snippet infoIcon()}{/snippet}
	{#snippet warningIcon()}{/snippet}
</Sonner>
