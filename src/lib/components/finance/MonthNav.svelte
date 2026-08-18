<script lang="ts">
	import { Button } from '$lib/components/ui/button';

	let { monthKey, onChange }: { monthKey: string; onChange: (m: string) => void } = $props();

	const label = $derived(
		new Date(`${monthKey}-01T00:00:00Z`).toLocaleDateString('en-IN', {
			month: 'long',
			year: 'numeric',
			timeZone: 'UTC'
		})
	);

	function shift(delta: number) {
		const [y, m] = monthKey.split('-').map(Number);
		const d = new Date(Date.UTC(y, m - 1 + delta, 1));
		const next = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
		onChange(next);
	}
</script>

<div class="flex items-center justify-between">
	<Button variant="ghost" size="sm" onclick={() => shift(-1)} aria-label="Previous month">‹</Button>
	<span class="text-sm font-medium">{label}</span>
	<Button variant="ghost" size="sm" onclick={() => shift(1)} aria-label="Next month">›</Button>
</div>
