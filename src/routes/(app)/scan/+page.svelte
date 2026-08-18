<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { toast } from 'svelte-sonner';
	import { analyzeImage, hasGeminiKey } from '$lib/ai/gemini';
	import { createCustomFood, listNutrients, logFood } from '$lib/nutrition/foods';
	import { todayIso } from '$lib/finance/dates';
	import { compressImage } from '$lib/image';
	import { Button } from '$lib/components/ui/button';
	import type { ScanResult } from '$lib/ai/scan';
	import Camera from '@lucide/svelte/icons/camera';
	import ImagePlus from '@lucide/svelte/icons/image-plus';
	import LoaderCircle from '@lucide/svelte/icons/loader-circle';

	const qc = useQueryClient();
	const nutrientsQ = createQuery(() => ({
		queryKey: ['nutrients'],
		queryFn: () => listNutrients(),
		staleTime: 60 * 60_000
	}));

	let fileEl: HTMLInputElement;
	let preview = $state<string | null>(null);
	let result = $state<ScanResult | null>(null);
	let busy = $state(false);
	let logging = $state(false);
	let error = $state('');

	async function fileToDataUrl(file: File): Promise<string> {
		const compressed = await compressImage(file, 1280, 0.8);
		return new Promise((resolve, reject) => {
			const r = new FileReader();
			r.onload = () => resolve(String(r.result));
			r.onerror = () => reject(new Error('Could not read the photo'));
			r.readAsDataURL(compressed);
		});
	}

	async function onPick(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		if (!file) return;
		error = '';
		result = null;
		busy = true;
		try {
			preview = await fileToDataUrl(file);
			if (!hasGeminiKey()) {
				throw new Error('Add a Gemini key in Today → Settings first.');
			}
			result = await analyzeImage(preview);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not read that photo';
		}
		busy = false;
	}

	async function logScanned() {
		if (!result || result.kind !== 'food') return;
		logging = true;
		try {
			const nutrients = nutrientsQ.data ?? (await listNutrients());
			const food = await createCustomFood(
				{
					name: result.name,
					category: 'prepared',
					default_serving_label: result.serving,
					serving_grams: 0,
					energy_kcal: result.energy_kcal
				},
				{
					protein_mg: Math.round(result.protein_g * 1000),
					carb_mg: Math.round(result.carb_g * 1000),
					fat_mg: Math.round(result.fat_g * 1000),
					fiber_mg: 0
				},
				nutrients
			);
			await logFood({ food_id: food.id, quantity: 1, logged_on: todayIso() });
			await qc.invalidateQueries({ queryKey: ['food_log'] });
			toast.success(`Logged ${result.name}`);
		} catch {
			toast.error('Could not log that food');
		}
		logging = false;
	}

	const neededLabel: Record<string, string> = {
		yes: 'Worth keeping',
		no: 'You don’t need this',
		maybe: 'Only if it earns its place'
	};
</script>

<div class="scan">
	<header>
		<h1>Scan</h1>
		<p>Food gets a nutrition read. Anything else — whether you actually need it.</p>
	</header>

	<input
		bind:this={fileEl}
		type="file"
		accept="image/*"
		capture="environment"
		class="hidden"
		onchange={onPick}
	/>

	{#if preview}
		<div class="frame">
			<img src={preview} alt="Scan preview" />
			{#if busy}
				<div class="veil">
					<LoaderCircle class="spin size-6" />
					<span>Reading…</span>
				</div>
			{/if}
		</div>
	{:else}
		<button class="shutter" type="button" onclick={() => fileEl.click()}>
			<Camera class="cam" />
			<span>Take or pick a photo</span>
		</button>
	{/if}

	<div class="actions">
		<Button variant="outline" class="gap-2" onclick={() => fileEl.click()} disabled={busy}>
			<ImagePlus class="size-4" /> {preview ? 'Another photo' : 'Photo library'}
		</Button>
	</div>

	{#if error}
		<p class="err">{error}</p>
	{/if}

	{#if result?.kind === 'food'}
		<section class="card">
			<p class="kicker">Food</p>
			<h2>{result.name}</h2>
			<p class="serving">{result.serving}</p>
			<div class="macros">
				<div><strong>{result.energy_kcal}</strong><span>kcal</span></div>
				<div><strong>{result.protein_g}</strong><span>protein</span></div>
				<div><strong>{result.carb_g}</strong><span>carbs</span></div>
				<div><strong>{result.fat_g}</strong><span>fat</span></div>
			</div>
			{#if result.detail}<p class="detail">{result.detail}</p>{/if}
			<Button disabled={logging} onclick={logScanned}>{logging ? 'Logging…' : 'Log this meal'}</Button>
		</section>
	{:else if result?.kind === 'object'}
		<section class="card">
			<p class="kicker" data-need={result.needed}>{neededLabel[result.needed]}</p>
			<h2>{result.name}</h2>
			<p class="detail">{result.why}</p>
			{#if result.useful}
				<p class="useful"><span>If you keep it</span>{result.useful}</p>
			{/if}
		</section>
	{/if}
</div>

<style>
	.scan {
		display: flex;
		flex-direction: column;
		gap: 1rem;
		max-width: 520px;
		padding-bottom: 1.5rem;
	}
	header h1 {
		margin: 0;
		font-size: 1.5rem;
		font-weight: 650;
		letter-spacing: -0.03em;
	}
	header p {
		margin: 0.25rem 0 0;
		font-size: var(--text-sm);
		color: var(--muted-foreground);
	}
	.hidden {
		display: none;
	}
	.shutter {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 0.65rem;
		width: 100%;
		aspect-ratio: 4 / 5;
		max-height: 420px;
		border: 1px dashed var(--border);
		border-radius: 1.25rem;
		background: color-mix(in oklch, var(--card) 80%, transparent);
		color: var(--muted-foreground);
		font-size: var(--text-sm);
	}
	.shutter :global(.cam) {
		height: 36px;
		width: 36px;
		color: var(--foreground);
	}
	.frame {
		position: relative;
		overflow: hidden;
		border-radius: 1.25rem;
		border: 1px solid var(--border);
		aspect-ratio: 4 / 5;
		max-height: 420px;
		background: var(--secondary);
	}
	.frame img {
		height: 100%;
		width: 100%;
		object-fit: cover;
	}
	.veil {
		position: absolute;
		inset: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 0.5rem;
		background: rgb(0 0 0 / 0.45);
		color: #fff;
		font-size: var(--text-sm);
	}
	.veil :global(.spin) {
		animation: spin 0.8s linear infinite;
	}
	@keyframes spin {
		to {
			transform: rotate(360deg);
		}
	}
	.actions {
		display: flex;
		gap: 0.5rem;
	}
	.err {
		margin: 0;
		font-size: var(--text-sm);
		color: var(--destructive);
	}
	.card {
		display: flex;
		flex-direction: column;
		gap: 0.45rem;
		border-radius: 1.15rem;
		border: 1px solid var(--border);
		background: var(--card);
		padding: 1rem 1.05rem 1.1rem;
	}
	.kicker {
		margin: 0;
		font-size: 10px;
		font-weight: 600;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		color: var(--muted-foreground);
	}
	.kicker[data-need='yes'] {
		color: #34d399;
	}
	.kicker[data-need='no'] {
		color: #fb7185;
	}
	.card h2 {
		margin: 0;
		font-size: 1.25rem;
		font-weight: 600;
		letter-spacing: -0.03em;
	}
	.serving {
		margin: 0;
		font-size: var(--text-sm);
		color: var(--muted-foreground);
	}
	.macros {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: 0.4rem;
		margin: 0.35rem 0 0.5rem;
	}
	.macros div {
		display: flex;
		min-width: 0;
		flex-direction: column;
		align-items: center;
		border-radius: 0.7rem;
		background: var(--secondary);
		padding: 0.45rem 0.2rem;
	}
	.macros strong {
		font-size: var(--text-base);
		font-variant-numeric: tabular-nums;
	}
	.macros span {
		font-size: 10px;
		color: var(--muted-foreground);
	}
	.detail {
		margin: 0 0 0.4rem;
		font-size: var(--text-sm);
		line-height: 1.45;
	}
	.useful {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		margin: 0;
		font-size: var(--text-sm);
		line-height: 1.45;
	}
	.useful span {
		font-size: 10px;
		font-weight: 600;
		letter-spacing: 0.1em;
		text-transform: uppercase;
		color: var(--muted-foreground);
	}
</style>
