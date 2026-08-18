<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { openSectionFromQuery, focusSection } from '$lib/openFromQuery';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { cn } from '$lib/utils';
	import { todayIso } from '$lib/finance/dates';
	import { listTodos, addTodo, toggleTodo, todosRepo, todoBucket } from '$lib/planner/todos';
	import { PRIORITY_LABELS, type Priority, type Todo } from '$lib/planner/types';

	const qc = useQueryClient();
	const todos = createQuery(() => ({ queryKey: ['todos'], queryFn: () => listTodos() }));

	// Bottom-nav quick action: /todos?add=1
	onMount(() =>
		openSectionFromQuery(page.url.searchParams.get('add'), { '1': () => focusSection('todo-add') })
	);

	let title = $state('');
	let dueOn = $state('');
	let priority = $state<Priority>(0);
	const today = todayIso();

	const add = createMutation(() => ({
		mutationFn: () => addTodo(title, dueOn || null, priority),
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['todos'] });
			title = '';
			dueOn = '';
			priority = 0;
		}
	}));
	const toggle = createMutation(() => ({
		mutationFn: (t: Todo) => toggleTodo(t),
		onSuccess: () => qc.invalidateQueries({ queryKey: ['todos'] })
	}));
	const del = createMutation(() => ({
		mutationFn: (t: Todo) => todosRepo.remove(t.id),
		onSuccess: () => qc.invalidateQueries({ queryKey: ['todos'] })
	}));

	const open = $derived((todos.data ?? []).filter((t) => !t.done));
	const done = $derived((todos.data ?? []).filter((t) => t.done));
	const bucketTone: Record<string, string> = {
		overdue: 'text-rose-500',
		today: 'text-amber-500',
		upcoming: 'text-muted-foreground',
		someday: 'text-muted-foreground'
	};
</script>

<div class="kn-stagger flex flex-col gap-4">
	<Card.Root id="todo-add">
		<Card.Content class="flex flex-wrap items-end gap-2 pt-4">
			<Input placeholder="What needs doing?" bind:value={title} class="w-64" />
			<Input type="date" bind:value={dueOn} class="w-40" />
			<select bind:value={priority} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				<option value={0}>No priority</option>
				<option value={1}>Low</option>
				<option value={2}>Medium</option>
				<option value={3}>High</option>
			</select>
			<Button disabled={!title || add.isPending} onclick={() => add.mutate()}>Add</Button>
		</Card.Content>
	</Card.Root>

	<Card.Root>
		<Card.Content class="divide-y divide-border">
			{#each open as t (t.id)}
				{@const bucket = todoBucket(t.due_on, t.done, today)}
				<div class="flex items-center gap-3 py-2 text-sm">
					<input type="checkbox" checked={t.done} onchange={() => toggle.mutate(t)} class="size-4" />
					<div class="flex flex-1 flex-col">
						<span>{t.title}</span>
						<span class="text-xs {bucketTone[bucket]}">
							{bucket}{t.due_on ? ` · ${t.due_on}` : ''}{t.priority ? ` · ${PRIORITY_LABELS[t.priority]}` : ''}
						</span>
					</div>
					<Button variant="ghost" size="sm" onclick={() => del.mutate(t)} aria-label="Delete">✕</Button>
				</div>
			{:else}
				<p class="py-6 text-center text-sm text-muted-foreground">Nothing to do. Nice.</p>
			{/each}
		</Card.Content>
	</Card.Root>

	{#if done.length}
		<Card.Root>
			<Card.Header><Card.Title class="text-base">Done ({done.length})</Card.Title></Card.Header>
			<Card.Content class="divide-y divide-border">
				{#each done as t (t.id)}
					<div class="flex items-center gap-3 py-2 text-sm">
						<input type="checkbox" checked={t.done} onchange={() => toggle.mutate(t)} class="size-4" />
						<span class={cn('flex-1 line-through text-muted-foreground')}>{t.title}</span>
						<Button variant="ghost" size="sm" onclick={() => del.mutate(t)} aria-label="Delete">✕</Button>
					</div>
				{/each}
			</Card.Content>
		</Card.Root>
	{/if}
</div>
