<script lang="ts">
	import { page } from '$app/state';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Input } from '$lib/components/ui/input';
	import { formatINR, toPaise, fromPaise } from '$lib/money';
	import {
		listBelongings,
		addBelonging,
		updateBelonging,
		removeBelonging,
		uploadBelongingImage,
		type Belonging
	} from '$lib/belongings/belongings';
	import BelongingThumb from '$lib/belongings/BelongingThumb.svelte';
	import { toast } from 'svelte-sonner';
	import ArrowLeft from '@lucide/svelte/icons/arrow-left';
	import Plus from '@lucide/svelte/icons/plus';
	import Minus from '@lucide/svelte/icons/minus';
	import ImagePlus from '@lucide/svelte/icons/image-plus';
	import X from '@lucide/svelte/icons/x';

	const category = $derived(decodeURIComponent(page.params.category ?? ''));

	const qc = useQueryClient();
	const list = createQuery(() => ({ queryKey: ['belongings'], queryFn: () => listBelongings() }));
	function refetch() {
		return qc.refetchQueries({ queryKey: ['belongings'] });
	}

	const all = $derived(list.data ?? []);
	const countRow = $derived(all.find((b) => b.kind === 'clothing' && b.category === category));
	const photos = $derived(all.filter((b) => b.kind === 'wardrobe_photo' && b.category === category) as Belonging[]);

	// Optimistic count + price (held until the server confirms — no flicker).
	let qtyOverride = $state<number | undefined>(undefined);
	let priceOverride = $state<string | undefined>(undefined);
	let qtyTimer: ReturnType<typeof setTimeout> | undefined;
	let priceTimer: ReturnType<typeof setTimeout> | undefined;

	const qty = $derived(qtyOverride ?? countRow?.qty ?? 0);
	const priceVal = $derived(
		priceOverride ?? (countRow?.cost_paise != null ? String(fromPaise(countRow.cost_paise)) : '')
	);
	const pricePaise = $derived(priceVal ? toPaise(Number(priceVal)) : 0);
	const totalValue = $derived(qty * pricePaise);

	async function commit(patch: { qty?: number; cost_paise?: number | null }) {
		if (countRow) await updateBelonging(countRow.id, patch);
		else await addBelonging({ kind: 'clothing', category, qty: patch.qty ?? 0, cost_paise: patch.cost_paise ?? null });
	}

	function bump(d: number) {
		qtyOverride = Math.max(0, qty + d);
		clearTimeout(qtyTimer);
		qtyTimer = setTimeout(flushQty, 450);
	}
	async function flushQty() {
		const target = qtyOverride;
		if (target === undefined) return;
		try {
			await commit({ qty: target });
			await refetch();
		} catch {
			toast.error('Could not save count');
		}
		if (qtyOverride === target) qtyOverride = undefined;
	}

	function setPrice(v: string) {
		priceOverride = v;
		clearTimeout(priceTimer);
		priceTimer = setTimeout(flushPrice, 650);
	}
	async function flushPrice() {
		const v = priceOverride;
		if (v === undefined) return;
		try {
			await commit({ cost_paise: v ? toPaise(Number(v)) : null });
			await refetch();
		} catch {
			toast.error('Could not save price');
		}
		if (priceOverride === v) priceOverride = undefined;
	}

	let fileEl: HTMLInputElement;
	let uploading = $state(false);
	async function onPhoto(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		if (!file) return;
		uploading = true;
		try {
			const image_path = await uploadBelongingImage(file);
			await addBelonging({ kind: 'wardrobe_photo', category, qty: 1, image_path });
			await refetch();
			toast.success('Photo added');
		} catch {
			toast.error('Could not upload photo');
		}
		uploading = false;
	}
	async function delPhoto(id: string) {
		await removeBelonging(id);
		await refetch();
	}
</script>

<input bind:this={fileEl} type="file" accept="image/*" class="hidden" onchange={onPhoto} />

<div class="kn-stagger flex flex-col gap-4">
	<a href="/belongings" class="inline-flex w-fit items-center gap-1.5 rounded-full border border-border px-3 py-1.5 text-xs text-muted-foreground hover:bg-accent">
		<ArrowLeft class="size-3.5" /> Belongings
	</a>

	<div>
		<h1 class="text-2xl font-semibold tracking-tight">{category}</h1>
		<p class="text-sm text-muted-foreground">{qty} owned · worth {formatINR(totalValue)}</p>
	</div>

	<!-- Count + price + stats -->
	<div class="grid gap-3 sm:grid-cols-3">
		<Card.Root class="sm:col-span-1">
			<Card.Content class="flex flex-col items-center gap-3 pt-6">
				<div class="text-5xl font-bold leading-none">{qty}</div>
				<div class="text-xs text-muted-foreground">in the wardrobe</div>
				<div class="flex w-full gap-2">
					<button class="step" onclick={() => bump(-1)} disabled={qty === 0} aria-label="Remove one"><Minus class="size-5" /></button>
					<button class="step step-add" onclick={() => bump(1)} aria-label="Add one"><Plus class="size-5" /></button>
				</div>
			</Card.Content>
		</Card.Root>

		<Card.Root class="sm:col-span-2">
			<Card.Content class="grid grid-cols-2 gap-4 pt-6">
				<label class="flex flex-col gap-1">
					<span class="text-xs text-muted-foreground">Avg price / item</span>
					<div class="flex items-center gap-1.5">
						<span class="text-muted-foreground">₹</span>
						<Input type="number" step="1" placeholder="price" value={priceVal} oninput={(e) => setPrice(e.currentTarget.value)} class="w-28" />
					</div>
				</label>
				<div class="flex flex-col gap-1">
					<span class="text-xs text-muted-foreground">Total value</span>
					<span class="text-2xl font-bold">{formatINR(totalValue)}</span>
				</div>
				<div class="flex flex-col gap-1">
					<span class="text-xs text-muted-foreground">Photos</span>
					<span class="text-2xl font-bold">{photos.length}</span>
				</div>
				<div class="flex flex-col gap-1">
					<span class="text-xs text-muted-foreground">Spent on {category.toLowerCase()}</span>
					<span class="text-2xl font-bold">{formatINR(totalValue)}</span>
				</div>
			</Card.Content>
		</Card.Root>
	</div>

	<!-- Gallery -->
	<Card.Root>
		<Card.Header class="flex-row items-center justify-between">
			<Card.Title class="text-base">Gallery</Card.Title>
			<button class="add-btn" onclick={() => fileEl.click()} disabled={uploading}>
				<ImagePlus class="size-4" /> {uploading ? 'Uploading…' : 'Add photo'}
			</button>
		</Card.Header>
		<Card.Content>
			{#if photos.length}
				<div class="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
					{#each photos as pic (pic.id)}
						<div class="cell">
							{#if pic.image_path}<BelongingThumb path={pic.image_path} alt={category} />{/if}
							<button class="x" onclick={() => delPhoto(pic.id)} aria-label="Delete photo"><X class="size-3.5" /></button>
						</div>
					{/each}
				</div>
			{:else}
				<p class="py-8 text-center text-sm text-muted-foreground">No photos yet — add a few to remember what you own.</p>
			{/if}
		</Card.Content>
	</Card.Root>
</div>

<style>
	.step {
		display: grid;
		height: 44px;
		flex: 1;
		place-items: center;
		border-radius: var(--radius-lg);
		border: 1px solid var(--border);
		color: var(--foreground);
		background: var(--card);
	}
	.step:hover:not(:disabled) {
		background: var(--accent);
	}
	.step:active:not(:disabled) {
		transform: scale(0.96);
	}
	.step:disabled {
		opacity: 0.35;
	}
	.step-add {
		flex: 2;
		background: var(--primary);
		border-color: var(--primary);
		color: var(--primary-foreground);
	}
	.step-add:hover {
		background: color-mix(in oklch, var(--primary) 88%, black);
	}
	.add-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		border-radius: var(--radius-md);
		border: 1px solid var(--border);
		padding: 0.35rem 0.7rem;
		font-size: var(--text-sm);
		color: var(--foreground);
	}
	.add-btn:hover {
		background: var(--accent);
	}
	.add-btn:disabled {
		opacity: 0.5;
	}
	.cell {
		position: relative;
		aspect-ratio: 1;
		overflow: hidden;
		border-radius: var(--radius-md);
		border: 1px solid var(--border);
	}
	.x {
		position: absolute;
		right: 4px;
		top: 4px;
		z-index: 2;
		display: grid;
		height: 22px;
		width: 22px;
		place-items: center;
		border-radius: 9999px;
		background: rgb(0 0 0 / 0.6);
		color: #fff;
		opacity: 0;
		transition: opacity var(--duration-fast) ease;
	}
	.cell:hover .x {
		opacity: 1;
	}
	.x:hover {
		background: var(--destructive);
	}
</style>
