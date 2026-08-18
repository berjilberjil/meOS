<script lang="ts">
	import { page } from '$app/state';
	import EntryForm from '$lib/components/journal/EntryForm.svelte';

	const date = $derived(page.url.searchParams.get('date') ?? undefined);
</script>

<div class="h-full">
	{#key date}
		<EntryForm {date} />
	{/key}
</div>
