<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { openSectionFromQuery, focusSection } from '$lib/openFromQuery';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { todayIso } from '$lib/finance/dates';
	import { recentFitness, totalDuration, recentHealth, upsertHealth } from '$lib/health/logs';
	import { mToKm, kgToG, gToKg, minToHours } from '$lib/health/units';
	import { getPersonal } from '$lib/profile/personal';
	import { listFitnessPhotos, uploadFitnessPhoto, deleteFitnessPhoto } from '$lib/health/photos';
	import WeightChart from '$lib/health/WeightChart.svelte';
	import { toast } from 'svelte-sonner';
	import { openLightbox } from '$lib/stores/lightbox.svelte';
	import Camera from '@lucide/svelte/icons/camera';
	import X from '@lucide/svelte/icons/x';

	const qc = useQueryClient();

	// Bottom-nav quick actions: /fitness?add=workout|photo
	onMount(() =>
		openSectionFromQuery(page.url.searchParams.get('add'), {
			workout: () => goto('/fitness/workouts'),
			log: () => goto('/fitness/workouts'),
			photo: () => focusSection('fit-photo', { click: true })
		})
	);

	const fitness = createQuery(() => ({ queryKey: ['fitness'], queryFn: () => recentFitness() }));
	const health = createQuery(() => ({ queryKey: ['health'], queryFn: () => recentHealth(120) }));
	const personalQ = createQuery(() => ({ queryKey: ['personal'], queryFn: () => getPersonal() }));
	const photos = createQuery(() => ({ queryKey: ['fitness', 'photos'], queryFn: () => listFitnessPhotos() }));

	const weightPoints = $derived(
		(health.data ?? [])
			.filter((l) => l.weight_g != null)
			.map((l) => ({ iso: l.logged_on, kg: gToKg(l.weight_g!) }))
			.reverse()
	);
	const currentKg = $derived(weightPoints.at(-1)?.kg ?? null);
	const goalKg = $derived(personalQ.data?.goal_weight_kg ?? null);
	const toGoal = $derived(currentKg != null && goalKg != null ? +(currentKg - goalKg).toFixed(1) : null);

	// Quick weight log
	let quickWeight = $state('');
	const logWeight = createMutation(() => ({
		mutationFn: () => upsertHealth(todayIso(), { weight_g: kgToG(Number(quickWeight)) }),
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['health'] });
			quickWeight = '';
			toast.success('Weight logged');
		}
	}));

	// Progress photos
	let photoEl: HTMLInputElement;
	let uploading = $state(false);
	async function onPhoto(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		if (!file) return;
		uploading = true;
		try {
			await uploadFitnessPhoto(file);
			qc.invalidateQueries({ queryKey: ['fitness', 'photos'] });
			toast.success('Progress photo added');
		} catch {
			toast.error('Could not upload photo');
		}
		uploading = false;
	}
	async function removePhoto(id: string, path: string) {
		try {
			await deleteFitnessPhoto(id, path);
			qc.invalidateQueries({ queryKey: ['fitness', 'photos'] });
			toast.success('Photo deleted');
		} catch {
			toast.error('Could not delete photo');
		}
	}

	const weekMin = $derived(totalDuration(fitness.data ?? [], todayIso(), 7));
</script>

<div class="kn-stagger flex flex-col gap-4">
	<!-- Weight tracking -->
	<Card.Root>
		<Card.Header>
			<Card.Title>Weight</Card.Title>
			<Card.Description>Log it often and watch the trend.</Card.Description>
		</Card.Header>
		<Card.Content class="flex flex-col gap-4">
			<div class="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-end sm:gap-x-8">
				<div>
					<div class="text-xs text-muted-foreground">Current</div>
					<div class="text-3xl font-bold">{currentKg != null ? `${currentKg} kg` : '—'}</div>
				</div>
				{#if goalKg != null}
					<div>
						<div class="text-xs text-muted-foreground">Goal</div>
						<div class="text-xl font-semibold text-muted-foreground">{goalKg} kg</div>
					</div>
				{/if}
				{#if toGoal != null}
					<div>
						<div class="text-xs text-muted-foreground">To goal</div>
						<div class="text-xl font-semibold" style="color:{toGoal <= 0 ? '#22c55e' : '#ec4899'}">
							{toGoal > 0 ? `${toGoal} kg to lose` : toGoal < 0 ? `${-toGoal} kg to gain` : 'On target 🎯'}
						</div>
					</div>
				{/if}
				<div class="flex items-end gap-2 sm:ml-auto">
					<Input type="number" step="0.1" placeholder="Today's weight kg" bind:value={quickWeight} class="min-w-0 flex-1 sm:w-40" />
					<Button disabled={!quickWeight || logWeight.isPending} onclick={() => logWeight.mutate()}>Log</Button>
				</div>
			</div>
			<WeightChart points={weightPoints} goal={goalKg} />
		</Card.Content>
	</Card.Root>

	<!-- Progress photos -->
	<Card.Root id="fit-photo">
		<Card.Header class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
			<div>
				<Card.Title>Progress photos</Card.Title>
				<Card.Description>Snap one regularly to see the change.</Card.Description>
			</div>
			<Button size="sm" class="gap-2" disabled={uploading} onclick={() => photoEl.click()}>
				<Camera class="size-4" /> {uploading ? 'Uploading…' : 'Add photo'}
			</Button>
			<input bind:this={photoEl} type="file" accept="image/*" class="hidden" onchange={onPhoto} />
		</Card.Header>
		<Card.Content>
			{#if (photos.data ?? []).length}
				<div class="grid grid-cols-3 gap-2 sm:grid-cols-4 lg:grid-cols-6">
					{#each photos.data ?? [] as p (p.id)}
						<div class="photo">
							<button class="photo-open" onclick={() => openLightbox(p.url, 'Progress photo')} aria-label="View photo">
								<img src={p.url} alt="Progress {p.created_at.slice(0, 10)}" loading="lazy" decoding="async" />
							</button>
							<span class="photo-date">{p.created_at.slice(0, 10)}</span>
							<button class="photo-x" onclick={() => removePhoto(p.id, p.path)} aria-label="Delete photo">
								<X class="size-3.5" />
							</button>
						</div>
					{/each}
				</div>
			{:else}
				<p class="py-6 text-center text-sm text-muted-foreground">No photos yet. Add your first.</p>
			{/if}
		</Card.Content>
	</Card.Root>

	<Card.Root>
		<Card.Header>
			<Card.Description>This week</Card.Description>
			<Card.Title class="text-2xl">{weekMin} min active</Card.Title>
		</Card.Header>
	</Card.Root>

	<div class="grid gap-3 lg:grid-cols-2">
		<Card.Root>
			<Card.Header><Card.Title class="text-base">Recent workouts</Card.Title></Card.Header>
			<Card.Content class="divide-y divide-border">
				{#each fitness.data ?? [] as l (l.id)}
					<div class="flex flex-wrap items-center gap-x-4 py-2 text-sm">
						<span class="w-24 font-medium">{l.logged_on}</span>
						<span class="capitalize">{l.activity}</span>
						<span>{l.duration_min} min</span>
						{#if l.distance_m != null}<span>{mToKm(l.distance_m)} km</span>{/if}
						{#if l.calories != null}<span>{l.calories} cal</span>{/if}
					</div>
				{:else}
					<p class="py-6 text-center text-sm text-muted-foreground">No workouts logged.</p>
				{/each}
			</Card.Content>
		</Card.Root>

		<Card.Root>
			<Card.Header><Card.Title class="text-base">Recent days</Card.Title></Card.Header>
			<Card.Content class="divide-y divide-border">
				{#each health.data ?? [] as l (l.id)}
					<div class="flex flex-wrap items-center gap-x-4 py-2 text-sm">
						<span class="w-24 font-medium">{l.logged_on}</span>
						{#if l.weight_g != null}<span>{gToKg(l.weight_g)} kg</span>{/if}
						{#if l.sleep_min != null}<span>{minToHours(l.sleep_min)} h sleep</span>{/if}
						{#if l.water_ml != null}<span>{l.water_ml} ml</span>{/if}
						{#if l.mood}<span class="capitalize text-muted-foreground">{l.mood}</span>{/if}
					</div>
				{:else}
					<p class="py-6 text-center text-sm text-muted-foreground">No logs yet.</p>
				{/each}
			</Card.Content>
		</Card.Root>
	</div>
</div>

<style>
	.photo {
		position: relative;
		display: block;
		aspect-ratio: 1;
		overflow: hidden;
		border-radius: var(--radius-md);
		border: 1px solid var(--border);
	}
	.photo-open {
		display: block;
		height: 100%;
		width: 100%;
		padding: 0;
		border: none;
		background: none;
		cursor: pointer;
	}
	.photo img {
		height: 100%;
		width: 100%;
		object-fit: cover;
	}
	.photo-x {
		position: absolute;
		right: 4px;
		top: 4px;
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
	.photo:hover .photo-x {
		opacity: 1;
	}
	.photo-x:hover {
		background: var(--destructive);
	}
	.photo-date {
		position: absolute;
		bottom: 0;
		left: 0;
		right: 0;
		padding: 2px 5px;
		font-size: 0.65rem;
		color: #fff;
		background: linear-gradient(0deg, rgb(0 0 0 / 0.65), transparent);
	}
</style>
