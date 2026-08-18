<script lang="ts">
	import type { Snippet } from 'svelte';

	let { sidebar, main }: { sidebar?: Snippet; main?: Snippet } = $props();
</script>

<div class="flex h-dvh flex-col gap-2 p-2 md:flex-row" style="scrollbar-gutter: stable;">
	<aside class="shrink-0 md:w-64">{@render sidebar?.()}</aside>
	<main class="min-w-0 flex-1 overflow-auto">{@render main?.()}</main>
</div>
