<script lang="ts">
	import LoaderIcon from '@lucide/svelte/icons/loader-circle';
	import { cn } from '$lib/utils.js';

	let { size = 16, class: className }: { size?: number; class?: string } = $props();
</script>

<LoaderIcon {size} class={cn('animate-spin', className)} />
