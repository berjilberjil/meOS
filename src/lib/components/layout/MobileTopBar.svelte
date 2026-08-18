<script lang="ts">
	import { page } from '$app/state';
	import { profileState } from '$lib/stores/profile.svelte';
	import { headerTabs } from '$lib/stores/headerTabs.svelte';
	import { cn } from '$lib/utils';
	import { LIFE_MAP } from '$lib/nav';
	import * as haptics from '$lib/haptics';

	const lifeMapActive = $derived(
		page.url.pathname === LIFE_MAP.href || page.url.pathname.startsWith(LIFE_MAP.href + '/')
	);

	function active(href: string): boolean {
		const p = page.url.pathname;
		const matches = headerTabs.tabs.filter((t) => p === t.href || p.startsWith(t.href + '/'));
		if (!matches.length) return false;
		// Longest matching href wins, so /finance doesn't stay lit on /finance/transactions.
		const best = matches.reduce((a, b) => (b.href.length > a.href.length ? b : a));
		return best.href === href;
	}
</script>

<header class="mtop">
	<div class="left">
		<a href="/" class="brand">MyOS</a>
		{#if headerTabs.tabs.length}
			<nav class="tabs" aria-label="Section">
				{#each headerTabs.tabs as t (t.href)}
					<a href={t.href} class={cn('tab', active(t.href) && 'on')}>{t.label}</a>
				{/each}
			</nav>
		{/if}
	</div>
	<div class="right">
		<a
			href={LIFE_MAP.href}
			class="iconbtn"
			class:on={lifeMapActive}
			aria-label={LIFE_MAP.label}
			aria-current={lifeMapActive ? 'page' : undefined}
			onclick={() => haptics.tick()}
		>
			<LIFE_MAP.icon class="ic" />
		</a>
		<a href="/profile" class="avatar-link" aria-label="Profile" onclick={() => haptics.tick()}>
			<img src={profileState.avatar} alt={profileState.name} width="30" height="30" />
		</a>
	</div>
</header>

<style>
	.mtop {
		position: sticky;
		top: 0;
		z-index: 30;
		display: flex;
		flex-shrink: 0;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		/* Bar = 52px of content BELOW the notch. height is border-box, so the
		   safe-area inset must be added on top — otherwise the inset eats the
		   52px and the row spills past the bottom divider. */
		height: calc(52px + env(safe-area-inset-top));
		padding: 0 14px;
		padding-top: env(safe-area-inset-top);
		border-bottom: 1px solid var(--border);
		background: color-mix(in oklch, var(--card) 88%, transparent);
		backdrop-filter: blur(8px);
	}
	@media (min-width: 768px) {
		.mtop {
			height: calc(56px + env(safe-area-inset-top));
			padding-inline: 24px;
		}
	}
	.left {
		display: flex;
		min-width: 0;
		align-items: center;
		gap: 1.25rem;
	}
	.brand {
		flex-shrink: 0;
		font-size: var(--text-base);
		font-weight: 700;
		letter-spacing: -0.01em;
		color: var(--foreground);
		text-decoration: none;
	}
	/* Section sub-tabs live in the header on desktop; pages keep their own on mobile. */
	.tabs {
		display: none;
		align-items: center;
		gap: 0.25rem;
	}
	@media (min-width: 768px) {
		.tabs {
			display: flex;
		}
	}
	.tab {
		border-radius: var(--radius-md);
		padding: 0.3rem 0.7rem;
		font-size: var(--text-sm);
		color: var(--muted-foreground);
		text-decoration: none;
		transition: background-color var(--duration-fast) ease, color var(--duration-fast) ease;
	}
	.tab:hover {
		background: var(--secondary);
		color: var(--foreground);
	}
	.tab.on {
		background: var(--secondary);
		font-weight: 500;
		color: var(--secondary-foreground);
	}
	.right {
		display: flex;
		flex-shrink: 0;
		align-items: center;
		gap: 0.5rem;
	}
	.iconbtn {
		display: grid;
		height: 34px;
		width: 34px;
		place-items: center;
		border-radius: 9999px;
		color: var(--muted-foreground);
		text-decoration: none;
		-webkit-tap-highlight-color: transparent;
		transition: background-color var(--duration-fast) ease, color var(--duration-fast) ease;
	}
	.iconbtn:hover {
		background: var(--secondary);
		color: var(--foreground);
	}
	.iconbtn.on {
		color: var(--primary);
	}
	.iconbtn :global(.ic) {
		height: 19px;
		width: 19px;
	}
	.avatar-link img {
		height: 30px;
		width: 30px;
		border-radius: 9999px;
		object-fit: cover;
		object-position: center 18%;
		box-shadow: 0 0 0 1.5px color-mix(in oklch, var(--primary) 40%, transparent);
	}
</style>
