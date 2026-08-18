<script lang="ts">
	import { cn } from '$lib/utils';
	import type { Snippet } from 'svelte';

	let { class: klass = '', children }: { class?: string; children?: Snippet } = $props();
</script>

<div class={cn('rounded-xl border border-border/60 bg-card shadow-sm', klass)}>
	{@render children?.()}
</div>
