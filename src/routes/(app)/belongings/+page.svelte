<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { openSectionFromQuery, focusSection } from '$lib/openFromQuery';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { cn } from '$lib/utils';
	import { todayIso } from '$lib/finance/dates';
	import { formatINR, toPaise, sumPaise } from '$lib/money';
	import {
		listBelongings,
		addBelonging,
		removeBelonging,
		uploadBelongingImage,
		PURCHASE_CATEGORIES,
		CLOTHING_CATEGORIES,
		type Belonging
	} from '$lib/belongings/belongings';
	import BelongingThumb from '$lib/belongings/BelongingThumb.svelte';
	import { toast } from 'svelte-sonner';
	import Trash2 from '@lucide/svelte/icons/trash-2';
	import ImagePlus from '@lucide/svelte/icons/image-plus';
	import ChevronRight from '@lucide/svelte/icons/chevron-right';

	const qc = useQueryClient();

	// Bottom-nav quick actions: /belongings?add=purchase|wardrobe
	onMount(() =>
		openSectionFromQuery(page.url.searchParams.get('add'), {
			purchase: () => focusSection('bel-purchase'),
			wardrobe: () => focusSection('bel-wardrobe')
		})
	);

	const list = createQuery(() => ({ queryKey: ['belongings'], queryFn: () => listBelongings() }));
	function invalidate() {
		qc.invalidateQueries({ queryKey: ['belongings'] });
	}

	const all = $derived(list.data ?? []);
	const purchases = $derived(all.filter((b) => b.kind === 'purchase'));
	const countRows = $derived(new Map(all.filter((b) => b.kind === 'clothing').map((b) => [b.category, b])));

	function qtyOf(cat: string): number {
		return countRows.get(cat)?.qty ?? 0;
	}
	function valueOf(cat: string): number {
		const r = countRows.get(cat);
		return (r?.qty ?? 0) * (r?.cost_paise ?? 0);
	}
	function firstPhoto(cat: string): Belonging | undefined {
		return all.find((b) => b.kind === 'wardrobe_photo' && b.category === cat);
	}
	function photoCount(cat: string): number {
		return all.filter((b) => b.kind === 'wardrobe_photo' && b.category === cat).length;
	}

	const totalSpent = $derived(sumPaise(purchases.map((p) => p.cost_paise ?? 0)));
	const wardrobeItems = $derived(CLOTHING_CATEGORIES.reduce((s, c) => s + qtyOf(c), 0));
	const wardrobeValue = $derived(CLOTHING_CATEGORIES.reduce((s, c) => s + valueOf(c), 0));
	const byCategory = $derived.by(() => {
		const m = new Map<string, number>();
		for (const p of purchases) m.set(p.category, (m.get(p.category) ?? 0) + (p.cost_paise ?? 0));
		return [...m.entries()].sort((a, b) => b[1] - a[1]);
	});

	// Purchases
	let pName = $state('');
	let pCat = $state(PURCHASE_CATEGORIES[0]);
	let pCost = $state('');
	let pDate = $state(todayIso());
	let pFile: HTMLInputElement;
	let pPhoto = $state<File | null>(null);
	let pSaving = $state(false);
	function onPurchasePhoto(e: Event) {
		pPhoto = (e.currentTarget as HTMLInputElement).files?.[0] ?? null;
	}
	async function addPurchase() {
		if (!pName) return;
		pSaving = true;
		try {
			const image_path = pPhoto ? await uploadBelongingImage(pPhoto) : undefined;
			await addBelonging({
				kind: 'purchase',
				name: pName,
				category: pCat,
				cost_paise: pCost ? toPaise(Number(pCost)) : null,
				acquired_on: pDate,
				image_path
			});
			invalidate();
			pName = '';
			pCost = '';
			pPhoto = null;
			toast.success('Purchase added');
		} catch {
			toast.error('Could not add purchase');
		}
		pSaving = false;
	}
	async function delPurchase(id: string) {
		await removeBelonging(id);
		invalidate();
		toast.success('Removed');
	}
</script>

<div class="kn-stagger flex flex-col gap-4">
	<div>
		<h1 class="text-xl font-semibold tracking-tight">Belongings</h1>
		<p class="text-sm text-muted-foreground">Everything I own — what it cost, and what's in the wardrobe.</p>
	</div>

	<!-- Spend summary -->
	<Card.Root>
		<Card.Content class="flex flex-col gap-4 pt-6 sm:flex-row sm:items-center sm:justify-between">
			<div>
				<div class="text-xs uppercase tracking-wide text-muted-foreground">Total spent on stuff</div>
				<div class="text-4xl font-bold tracking-tight">{formatINR(totalSpent + wardrobeValue)}</div>
				<div class="text-xs text-muted-foreground">purchases {formatINR(totalSpent)} · wardrobe {formatINR(wardrobeValue)}</div>
			</div>
			{#if byCategory.length}
				<div class="flex flex-wrap gap-2">
					{#each byCategory as [cat, paise] (cat)}
						<div class="rounded-full border border-border px-3 py-1.5 text-sm">
							<span class="text-muted-foreground">{cat}</span>
							<span class="ml-1.5 font-semibold">{formatINR(paise)}</span>
						</div>
					{/each}
				</div>
			{/if}
		</Card.Content>
	</Card.Root>

	<!-- Purchases -->
	<Card.Root id="bel-purchase">
		<Card.Header><Card.Title>Purchases</Card.Title></Card.Header>
		<Card.Content class="flex flex-col gap-3">
			<div class="flex flex-wrap items-end gap-2">
				<Input placeholder="What did you buy?" bind:value={pName} class="w-56" />
				<select bind:value={pCat} class="h-9 rounded-md border border-border bg-background px-2 text-sm">
					{#each PURCHASE_CATEGORIES as c}<option value={c}>{c}</option>{/each}
				</select>
				<Input type="number" step="1" placeholder="₹ cost" bind:value={pCost} class="w-28" />
				<Input type="date" bind:value={pDate} class="w-40" />
				<input bind:this={pFile} type="file" accept="image/*" class="hidden" onchange={onPurchasePhoto} />
				<Button variant="outline" class={cn('gap-1.5', pPhoto && 'border-primary text-primary')} onclick={() => pFile.click()}>
					<ImagePlus class="size-4" /> {pPhoto ? 'Photo ✓' : 'Photo'}
				</Button>
				<Button disabled={!pName || pSaving} onclick={addPurchase}>Add</Button>
			</div>

			<div class="divide-y divide-border">
				{#each purchases as p (p.id)}
					<div class="flex items-center gap-3 py-2 text-sm">
						{#if p.image_path}
							<span class="size-9 overflow-hidden rounded-md border border-border"><BelongingThumb path={p.image_path} alt={p.name} /></span>
						{/if}
						<span class="font-medium">{p.name || '—'}</span>
						<span class="rounded-full bg-secondary px-2 py-0.5 text-xs">{p.category}</span>
						<span class="text-muted-foreground">{p.acquired_on ?? ''}</span>
						<span class="ml-auto font-semibold">{p.cost_paise != null ? formatINR(p.cost_paise) : '—'}</span>
						<button class="text-muted-foreground hover:text-destructive" onclick={() => delPurchase(p.id)} aria-label="Remove">
							<Trash2 class="size-4" />
						</button>
					</div>
				{:else}
					<p class="py-6 text-center text-sm text-muted-foreground">No purchases logged yet.</p>
				{/each}
			</div>
		</Card.Content>
	</Card.Root>

	<!-- Wardrobe — compact, tap a category for details -->
	<Card.Root id="bel-wardrobe">
		<Card.Header class="flex-row items-baseline justify-between">
			<Card.Title>Wardrobe</Card.Title>
			<span class="text-sm text-muted-foreground">{wardrobeItems} items · {formatINR(wardrobeValue)}</span>
		</Card.Header>
		<Card.Content>
			<div class="grid grid-cols-2 gap-2.5 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
				{#each CLOTHING_CATEGORIES as cat (cat)}
					{@const n = qtyOf(cat)}
					{@const pic = firstPhoto(cat)}
					<a href="/belongings/{encodeURIComponent(cat)}" class={cn('wcard', n && 'has')}>
						<div class="thumb">
							{#if pic?.image_path}
								<BelongingThumb path={pic.image_path} alt={cat} />
							{:else}
								<span class="ph"><ImagePlus class="size-4" /></span>
							{/if}
							{#if photoCount(cat) > 1}<span class="badge">{photoCount(cat)}</span>{/if}
						</div>
						<div class="meta">
							<div class="row">
								<span class="name">{cat}</span>
								<ChevronRight class="size-4 text-muted-foreground" />
							</div>
							<div class="row">
								<span class="count">{n}</span>
								{#if valueOf(cat) > 0}<span class="val">{formatINR(valueOf(cat))}</span>{/if}
							</div>
						</div>
					</a>
				{/each}
			</div>
		</Card.Content>
	</Card.Root>
</div>

<style>
	.wcard {
		display: flex;
		flex-direction: column;
		overflow: hidden;
		border-radius: var(--radius-lg);
		border: 1px solid var(--border);
		background: var(--card);
		text-decoration: none;
		color: var(--foreground);
		transition: border-color var(--duration-fast) ease, transform var(--duration-fast) ease;
	}
	.wcard:hover {
		border-color: color-mix(in oklch, var(--primary) 50%, var(--border));
		transform: translateY(-2px);
	}
	.wcard.has {
		border-color: color-mix(in oklch, var(--primary) 35%, var(--border));
	}
	.thumb {
		position: relative;
		aspect-ratio: 16 / 10;
		overflow: hidden;
		background: color-mix(in oklch, var(--muted) 60%, transparent);
	}
	.ph {
		display: grid;
		height: 100%;
		width: 100%;
		place-items: center;
		color: var(--muted-foreground);
	}
	.badge {
		position: absolute;
		right: 5px;
		top: 5px;
		border-radius: 9999px;
		background: rgb(0 0 0 / 0.6);
		padding: 1px 7px;
		font-size: 10px;
		color: #fff;
	}
	.meta {
		display: flex;
		flex-direction: column;
		gap: 2px;
		padding: 8px 10px 10px;
	}
	.row {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: 0.4rem;
	}
	.name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--text-sm);
		font-weight: 600;
	}
	.count {
		font-size: 1.6rem;
		font-weight: 800;
		line-height: 1.1;
	}
	.val {
		font-size: var(--text-xs);
		color: var(--muted-foreground);
	}
</style>
