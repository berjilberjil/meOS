<script lang="ts">
	import type { HTMLAttributes } from 'svelte/elements';
	import { cn, type WithElementRef } from '$lib/utils.js';

	let {
		ref = $bindable(null),
		class: className,
		children,
		...restProps
	}: WithElementRef<HTMLAttributes<HTMLDivElement>> = $props();
</script>

<div
	bind:this={ref}
	data-slot="card"
	class={cn(
		'ring-foreground/5 dark:ring-foreground/10 flex flex-col gap-6 rounded-3xl bg-card py-6 text-card-foreground shadow-sm ring-1',
		className
	)}
	{...restProps}
>
	{@render children?.()}
</div>
