<script lang="ts">
	import { formatINR } from '$lib/money';
	import type { Transaction } from '$lib/finance/types';

	let {
		txn,
		categoryName = '',
		accountName = ''
	}: { txn: Transaction; categoryName?: string; accountName?: string } = $props();

	const signed = $derived(txn.type === 'income' ? txn.amount_paise : -txn.amount_paise);
	const tone = $derived(
		txn.type === 'income' ? 'text-emerald-500' : txn.type === 'transfer' ? 'text-muted-foreground' : 'text-rose-500'
	);
</script>

<div class="flex items-center justify-between py-2 text-sm">
	<div class="flex flex-col">
		<span class="font-medium">{txn.note || categoryName || txn.type}</span>
		<span class="text-xs text-muted-foreground">{accountName} · {txn.occurred_on}</span>
	</div>
	<span class={tone}>{txn.type === 'transfer' ? formatINR(txn.amount_paise) : formatINR(signed)}</span>
</div>
