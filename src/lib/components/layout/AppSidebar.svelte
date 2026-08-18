<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { Button } from '$lib/components/ui/button';
	import { setTheme, themeState, type Theme } from '$lib/stores/theme.svelte';
	import { supabaseBrowser } from '$lib/supabase/client';
	import { profileState } from '$lib/stores/profile.svelte';
	import { NAV } from '$lib/nav';
	import Palette from '@lucide/svelte/icons/palette';
	import LogOut from '@lucide/svelte/icons/log-out';

	const themes: Theme[] = ['light', 'dark', 'system'];

	function cycle() {
		const i = themes.indexOf(themeState.current);
		const next = themes[(i + 1) % themes.length];
		themeState.current = next;
		setTheme(next);
	}

	function isActive(item: { href: string; match?: string[] }): boolean {
		const p = page.url.pathname;
		if (item.href === '/') return p === '/';
		const paths = item.match ?? [item.href];
		return paths.some((h) => p === h || p.startsWith(h + '/'));
	}

	let email = $state('');
	let loggingOut = $state(false);
	onMount(async () => {
		const { data } = await supabaseBrowser().auth.getUser();
		email = data.user?.email ?? '';
	});
	async function logout() {
		loggingOut = true;
		await supabaseBrowser().auth.signOut();
		await goto('/login');
	}
</script>

<nav class="flex h-full flex-col gap-1 p-3">
	<div class="px-2 py-1 text-sm font-semibold tracking-tight">MyOS</div>
	<div class="kn-stagger mt-1 flex flex-col gap-0.5">
		{#each NAV as item (item.href)}
			{@const Icon = item.icon}
			{@const active = isActive(item)}
			<a
				href={item.href}
				class="nav-link"
				class:active
				aria-current={active ? 'page' : undefined}
			>
				<span class="rail" aria-hidden="true"></span>
				<Icon class="nav-ic" />
				<span>{item.label}</span>
			</a>
		{/each}
	</div>
	<div class="mt-auto flex flex-col gap-1.5">
		<Button
			variant="ghost"
			size="sm"
			class="w-full justify-start gap-2"
			onclick={cycle}
			data-testid="theme-toggle"
		>
			<Palette class="size-4" />
			Theme: {themeState.current}
		</Button>

		<div class="profile-row">
			<a class="profile" href="/profile" class:active={isActive({ href: '/profile' })}>
				<span class="pf-avatar-wrap">
					<img class="pf-avatar" src={profileState.avatar} alt={profileState.name} width="36" height="36" />
					<span class="pf-dot" aria-hidden="true"></span>
				</span>
				<span class="pf-meta">
					<span class="pf-name">{profileState.name}</span>
					<span class="pf-email">{email}</span>
				</span>
			</a>
			<button
				class="pf-logout"
				onclick={logout}
				disabled={loggingOut}
				aria-label="Log out"
				title="Log out"
			>
				<LogOut class="size-4" />
			</button>
		</div>
	</div>
</nav>

<style>
	.nav-link {
		position: relative;
		display: flex;
		align-items: center;
		gap: 0.625rem;
		border-radius: var(--radius-md);
		padding: 0.375rem 0.625rem;
		font-size: var(--text-base);
		color: var(--sidebar-foreground);
		transition:
			background-color var(--duration-fast) ease,
			color var(--duration-fast) ease;
	}
	.nav-link:hover {
		background: var(--sidebar-accent);
		color: var(--sidebar-accent-foreground);
	}
	.nav-link.active {
		background: var(--sidebar-accent);
		color: var(--sidebar-accent-foreground);
		font-weight: 500;
	}
	.nav-link:focus-visible {
		outline: 2px solid var(--ring);
		outline-offset: -2px;
	}

	.nav-link :global(.nav-ic) {
		height: 1rem;
		width: 1rem;
		flex-shrink: 0;
		color: var(--muted-foreground);
		transition:
			color var(--duration-fast) ease,
			transform var(--duration-fast) var(--ease-entrance);
	}
	.nav-link:hover :global(.nav-ic) {
		transform: translateX(1px);
	}
	.nav-link:hover :global(.nav-ic),
	.nav-link.active :global(.nav-ic) {
		color: var(--primary);
	}

	/* Signature: a primary rail that grows on the active/hovered item. */
	.rail {
		position: absolute;
		left: 0;
		top: 50%;
		height: 0;
		width: 2.5px;
		transform: translateY(-50%);
		border-radius: 9999px;
		background: var(--primary);
		transition: height var(--duration-normal) var(--ease-entrance);
	}
	.nav-link:hover .rail {
		height: 42%;
	}
	.nav-link.active .rail {
		height: 62%;
	}

	.profile-row {
		display: flex;
		align-items: center;
		gap: 0.25rem;
		border-radius: var(--radius-lg);
		border: 1px solid var(--border);
		background: color-mix(in oklch, var(--sidebar-accent) 45%, transparent);
		padding: 0.3rem;
	}
	.profile {
		display: flex;
		min-width: 0;
		flex: 1;
		align-items: center;
		gap: 0.55rem;
		border-radius: var(--radius-md);
		padding: 0.3rem 0.4rem;
		text-decoration: none;
		color: var(--foreground);
		transition: background-color var(--duration-fast) ease;
	}
	.profile:hover,
	.profile.active {
		background: var(--sidebar-accent);
	}
	.profile:focus-visible {
		outline: 2px solid var(--ring);
		outline-offset: -2px;
	}
	.pf-avatar-wrap {
		position: relative;
		flex-shrink: 0;
		line-height: 0;
	}
	.pf-avatar {
		height: 36px;
		width: 36px;
		border-radius: 9999px;
		object-fit: cover;
		object-position: center 18%;
		background: color-mix(in oklch, var(--primary) 14%, var(--card));
		box-shadow: 0 0 0 1.5px color-mix(in oklch, var(--primary) 40%, transparent);
	}
	.pf-dot {
		position: absolute;
		right: -1px;
		bottom: -1px;
		height: 10px;
		width: 10px;
		border-radius: 9999px;
		background: var(--presence-online, #22c55e);
		box-shadow: 0 0 0 2px var(--card);
	}
	.pf-meta {
		display: flex;
		min-width: 0;
		flex: 1;
		flex-direction: column;
		line-height: 1.2;
	}
	.pf-name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--text-sm);
		font-weight: 600;
	}
	.pf-email {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--text-xs);
		color: var(--muted-foreground);
	}
	.pf-logout {
		display: grid;
		height: 30px;
		width: 30px;
		flex-shrink: 0;
		place-items: center;
		border-radius: var(--radius-md);
		color: var(--muted-foreground);
		transition:
			color var(--duration-fast) ease,
			background-color var(--duration-fast) ease;
	}
	.pf-logout:hover {
		color: var(--destructive);
		background: color-mix(in oklch, var(--destructive) 12%, transparent);
	}
	.pf-logout:focus-visible {
		outline: 2px solid var(--ring);
		outline-offset: -2px;
	}
	.pf-logout:disabled {
		opacity: 0.5;
	}
</style>
