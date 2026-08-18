<script lang="ts">
	import type { Snippet } from 'svelte';
	import { page } from '$app/state';
	import ArrowLeft from '@lucide/svelte/icons/arrow-left';
	import PanelLeft from '@lucide/svelte/icons/panel-left';
	import MoreHorizontal from '@lucide/svelte/icons/ellipsis';
	import Plus from '@lucide/svelte/icons/plus';

	interface Entry {
		id: string;
		href: string;
		title: string;
		sub?: string;
	}
	interface Props {
		entries?: Entry[];
		listTitle?: string;
		newHref?: string;
		backHref: string;
		status?: string;
		actions: Snippet<[() => void]>;
		header: Snippet;
		children: Snippet;
	}
	let {
		entries = [],
		listTitle = 'Entries',
		newHref,
		backHref,
		status,
		actions,
		header,
		children
	}: Props = $props();

	// Collapse the entry list by default on phones so the editor gets full width.
	let collapsed = $state(typeof window !== 'undefined' && window.innerWidth < 768);
	let menuOpen = $state(false);

	function isActive(href: string): boolean {
		return page.url.pathname === href.split('?')[0];
	}
</script>

<div class="shell">
	{#if !collapsed}
		<aside class="list">
			<div class="list-head">
				<span class="list-title">{listTitle}</span>
				{#if newHref}
					<a class="list-new" href={newHref} aria-label="New"><Plus class="size-4" /></a>
				{/if}
			</div>
			<div class="list-items">
				{#each entries as e (e.id)}
					<a class="list-item" class:active={isActive(e.href)} href={e.href}>
						<span class="li-title">{e.title || 'Untitled'}</span>
						{#if e.sub}<span class="li-sub">{e.sub}</span>{/if}
					</a>
				{:else}
					<p class="li-empty">Nothing here yet.</p>
				{/each}
			</div>
		</aside>
	{/if}

	<main class="main">
		<div class="bar no-print">
			<div class="bar-left">
				<button class="icon-btn" onclick={() => (collapsed = !collapsed)} aria-label="Toggle list" title="Toggle list">
					<PanelLeft class="size-4" />
				</button>
				<a class="chip" href={backHref}>
					<ArrowLeft class="size-3.5" /> Back
				</a>
			</div>
			<div class="bar-right">
				{#if status}<span class="status">{status}</span>{/if}
				<div class="menu-wrap">
					<button class="icon-btn" onclick={() => (menuOpen = !menuOpen)} aria-label="More actions" aria-expanded={menuOpen}>
						<MoreHorizontal class="size-4" />
					</button>
					{#if menuOpen}
						<button class="backdrop" onclick={() => (menuOpen = false)} aria-label="Close menu"></button>
						<div class="menu" role="menu">
							{@render actions(() => (menuOpen = false))}
						</div>
					{/if}
				</div>
			</div>
		</div>

		<div class="body">
			<div class="content print-area">
				{@render header()}
				{@render children()}
			</div>
		</div>
	</main>
</div>

<style>
	.shell {
		display: flex;
		height: 100%;
		min-height: 0;
		gap: 0;
	}
	.list {
		display: flex;
		width: 240px;
		flex-shrink: 0;
		flex-direction: column;
		gap: 0.25rem;
		border-right: 1px solid var(--border);
		padding: 0 0.6rem 0 0;
		overflow-y: auto;
	}
	.list-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0.1rem 0.4rem 0.4rem;
	}
	.list-title {
		font-size: var(--text-xs);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--muted-foreground);
	}
	.list-new {
		display: grid;
		height: 24px;
		width: 24px;
		place-items: center;
		border-radius: var(--radius-sm);
		color: var(--muted-foreground);
	}
	.list-new:hover {
		background: var(--accent);
		color: var(--foreground);
	}
	.list-items {
		display: flex;
		flex-direction: column;
		gap: 1px;
	}
	.list-item {
		display: flex;
		flex-direction: column;
		gap: 1px;
		border-radius: var(--radius-md);
		padding: 0.4rem 0.5rem;
		text-decoration: none;
		color: var(--foreground);
	}
	.list-item:hover {
		background: var(--accent);
	}
	.list-item.active {
		background: var(--secondary);
	}
	.li-title {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--text-sm);
		font-weight: 500;
	}
	.li-sub {
		font-size: var(--text-xs);
		color: var(--muted-foreground);
	}
	.li-empty {
		padding: 0.5rem;
		font-size: var(--text-xs);
		color: var(--muted-foreground);
	}

	.main {
		display: flex;
		min-width: 0;
		flex: 1;
		flex-direction: column;
		min-height: 0;
	}
	.bar {
		display: flex;
		flex-shrink: 0;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
		padding: 0 0.25rem 0.6rem;
	}
	.bar-left,
	.bar-right {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}
	.icon-btn {
		display: grid;
		height: 30px;
		width: 30px;
		place-items: center;
		border-radius: var(--radius-md);
		color: var(--muted-foreground);
	}
	.icon-btn:hover {
		background: var(--accent);
		color: var(--foreground);
	}
	.chip {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		border-radius: 9999px;
		border: 1px solid var(--border);
		padding: 0.3rem 0.7rem;
		font-size: var(--text-xs);
		color: var(--muted-foreground);
		text-decoration: none;
	}
	.chip:hover {
		background: var(--accent);
		color: var(--accent-foreground);
	}
	.status {
		font-size: var(--text-xs);
		color: var(--muted-foreground);
	}
	.menu-wrap {
		position: relative;
	}
	.backdrop {
		position: fixed;
		inset: 0;
		z-index: 40;
		background: transparent;
		border: none;
	}
	.menu {
		position: absolute;
		right: 0;
		top: calc(100% + 6px);
		z-index: 50;
		display: flex;
		width: 220px;
		flex-direction: column;
		gap: 1px;
		border-radius: var(--radius-lg);
		border: 1px solid var(--border);
		background: var(--popover);
		color: var(--popover-foreground);
		padding: 0.3rem;
		box-shadow: 0 18px 40px -16px rgb(0 0 0 / 0.5);
	}
	.body {
		min-height: 0;
		flex: 1;
		overflow-y: auto;
	}
	.content {
		width: 100%;
		padding: 0 0.5rem 2rem;
	}
</style>
