<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { openSectionFromQuery, focusSection } from '$lib/openFromQuery';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { cn } from '$lib/utils';
	import { goalsRepo, addGoal, setGoalStatus } from '$lib/planner/goals';
	import type { GoalStatus } from '$lib/planner/types';

	const qc = useQueryClient();
	const goals = createQuery(() => ({ queryKey: ['life-goals'], queryFn: () => goalsRepo.list() }));

	// Bottom-nav quick action: /goals?add=1
	onMount(() =>
		openSectionFromQuery(page.url.searchParams.get('add'), { '1': () => focusSection('goal-add') })
	);

	let title = $state('');
	let description = $state('');
	let targetDate = $state('');

	const add = createMutation(() => ({
		mutationFn: () => addGoal(title, description || null, targetDate || null),
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['life-goals'] });
			title = '';
			description = '';
			targetDate = '';
		}
	}));
	const status = createMutation(() => ({
		mutationFn: ({ id, s }: { id: string; s: GoalStatus }) => setGoalStatus(id, s),
		onSuccess: () => qc.invalidateQueries({ queryKey: ['life-goals'] })
	}));

	const active = $derived((goals.data ?? []).filter((g) => g.status === 'active'));
	const others = $derived((goals.data ?? []).filter((g) => g.status !== 'active'));
</script>

<div class="kn-stagger flex flex-col gap-4">
	<Card.Root id="goal-add">
		<Card.Content class="flex flex-wrap items-end gap-2 pt-4">
			<Input placeholder="Goal (e.g. Run a half-marathon)" bind:value={title} class="w-64" />
			<Input placeholder="Why / notes" bind:value={description} class="w-64" />
			<Input type="date" bind:value={targetDate} class="w-40" />
			<Button disabled={!title || add.isPending} onclick={() => add.mutate()}>Add</Button>
		</Card.Content>
	</Card.Root>

	<div class="kn-stagger grid gap-2 sm:grid-cols-2">
		{#each active as g (g.id)}
			<Card.Root>
				<Card.Header>
					<Card.Title class="text-base">{g.title}</Card.Title>
					{#if g.target_date}<Card.Description>by {g.target_date}</Card.Description>{/if}
				</Card.Header>
				<Card.Content class="flex flex-col gap-2">
					{#if g.description}<p class="text-sm text-muted-foreground">{g.description}</p>{/if}
					<div class="flex gap-1">
						<Button size="sm" onclick={() => status.mutate({ id: g.id, s: 'done' })}>Done</Button>
						<Button variant="ghost" size="sm" onclick={() => status.mutate({ id: g.id, s: 'archived' })}>Archive</Button>
					</div>
				</Card.Content>
			</Card.Root>
		{:else}
			<p class="py-6 text-center text-sm text-muted-foreground sm:col-span-2">No active goals. Dream big.</p>
		{/each}
	</div>

	{#if others.length}
		<Card.Root>
			<Card.Header><Card.Title class="text-base">Done / archived</Card.Title></Card.Header>
			<Card.Content class="divide-y divide-border">
				{#each others as g (g.id)}
					<div class="flex items-center justify-between py-2 text-sm">
						<span class={cn(g.status === 'done' ? 'line-through text-muted-foreground' : 'text-muted-foreground')}>{g.title} · {g.status}</span>
						<Button variant="ghost" size="sm" onclick={() => status.mutate({ id: g.id, s: 'active' })}>Reactivate</Button>
					</div>
				{/each}
			</Card.Content>
		</Card.Root>
	{/if}
</div>
