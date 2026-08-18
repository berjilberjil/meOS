<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { listNotes } from '$lib/notes/notes';
	import { toCsv, downloadCsv } from '$lib/export/csv';
	import { toast } from 'svelte-sonner';
	import Download from '@lucide/svelte/icons/download';

	const notes = createQuery(() => ({ queryKey: ['notes'], queryFn: () => listNotes() }));

	let selected = $state<Set<string>>(new Set());
	function toggle(id: string) {
		const s = new Set(selected);
		s.has(id) ? s.delete(id) : s.add(id);
		selected = s;
	}
	function clear() {
		selected = new Set();
	}
	function exportCsv() {
		const rows = (notes.data ?? [])
			.filter((n) => selected.has(n.id))
			.map((n) => [n.title || 'Untitled', n.pinned ? 'yes' : 'no', n.updated_at, n.body_text]);
		downloadCsv(
			`notes-${new Date().toISOString().slice(0, 10)}.csv`,
			toCsv(['Title', 'Pinned', 'Updated', 'Body'], rows)
		);
		toast.success(`Exported ${rows.length} note${rows.length === 1 ? '' : 's'} to CSV`);
	}
</script>

<div class="kn-stagger flex flex-col gap-4">
	<div class="flex items-center justify-between gap-2">
		<div class="flex items-center gap-2">
			{#if selected.size}
				<span class="text-sm text-muted-foreground">{selected.size} selected</span>
				<Button variant="outline" size="sm" class="gap-1.5" onclick={exportCsv}>
					<Download class="size-3.5" /> Export CSV
				</Button>
				<Button variant="ghost" size="sm" onclick={clear}>Clear</Button>
			{/if}
		</div>
		<Button href="/notes/new">New note</Button>
	</div>

	<div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
		{#each notes.data ?? [] as n (n.id)}
			<div class="relative">
				<input
					type="checkbox"
					class="absolute left-2.5 top-3 z-10 size-4 cursor-pointer"
					style="accent-color: var(--primary);"
					checked={selected.has(n.id)}
					onclick={(e) => e.stopPropagation()}
					onchange={() => toggle(n.id)}
					aria-label="Select note"
				/>
				<a href="/notes/{n.id}">
					<Card.Root class="h-full transition-colors hover:bg-secondary/40">
						<Card.Header>
							<Card.Title class="pl-7 text-base">{n.pinned ? '📌 ' : ''}{n.title || 'Untitled'}</Card.Title>
						</Card.Header>
						{#if n.body_text}
							<Card.Content><p class="line-clamp-4 text-sm text-muted-foreground">{n.body_text}</p></Card.Content>
						{/if}
					</Card.Root>
				</a>
			</div>
		{:else}
			<p class="py-8 text-center text-sm text-muted-foreground sm:col-span-2 lg:col-span-3">No notes yet.</p>
		{/each}
	</div>
</div>
