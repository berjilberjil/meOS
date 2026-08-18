<script lang="ts">
	import LifeMap from '$lib/mindmap/LifeMap.svelte';
</script>

<div class="flex flex-col gap-3">
	<div class="shrink-0">
		<h1 class="text-xl font-semibold tracking-tight">Life map</h1>
		<p class="text-sm text-muted-foreground">
			How everything connects. Center is you; branches are your modules.
		</p>
	</div>
	<div class="h-[72vh] min-h-[520px]">
		<LifeMap />
	</div>
</div>
