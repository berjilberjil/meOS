<script lang="ts">
	import { onMount, type Component } from 'svelte';
	import type { Vitality } from '$lib/mindmap/graph';

	interface Props {
		label: string;
		href: string;
		count: number;
		level: number;
		status: Vitality;
		icon?: Component;
	}
	let { label, href, count, level, status, icon: Icon }: Props = $props();

	let mounted = $state(false);
	onMount(() => {
		mounted = true;
	});

	const fill = $derived(Math.round((mounted ? level : 0) * 100));
	const word = $derived(
		status === 'good' ? 'Thriving' : status === 'warn' ? 'Topping up' : 'Needs you'
	);
</script>

<a class="tank state-{status}" href={href} aria-label="{label}: {word}, {count} items">
	<div class="head">
		{#if Icon}<Icon class="ic" />{/if}
		<span class="label">{label}</span>
	</div>

	<div class="vessel">
		<div class="liquid" style="height: {fill}%">
			<svg class="wave wave-a" viewBox="0 0 240 20" preserveAspectRatio="none" aria-hidden="true">
				<path d="M0 10 Q15 4 30 10 T60 10 T90 10 T120 10 T150 10 T180 10 T210 10 T240 10 V20 H0 Z" />
			</svg>
			<svg class="wave wave-b" viewBox="0 0 240 20" preserveAspectRatio="none" aria-hidden="true">
				<path d="M0 10 Q15 4 30 10 T60 10 T90 10 T120 10 T150 10 T180 10 T210 10 T240 10 V20 H0 Z" />
			</svg>
		</div>

		{#if status === 'bad'}
			<div class="fire" aria-hidden="true">
				<span class="flame f1"></span>
				<span class="flame f2"></span>
				<span class="flame f3"></span>
				<span class="ember e1"></span>
				<span class="ember e2"></span>
				<span class="ember e3"></span>
			</div>
		{/if}

		<div class="readout">
			<span class="count">{count}</span>
			<span class="word">{word}</span>
		</div>
	</div>
</a>

<style>
	.tank {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		border-radius: var(--radius-lg);
		border: 1px solid var(--border);
		background: var(--card);
		padding: 0.75rem;
		text-decoration: none;
		color: var(--foreground);
		transition:
			transform var(--duration-normal) var(--ease-entrance),
			border-color var(--duration-fast) ease,
			box-shadow var(--duration-normal) ease;
	}
	.tank:hover {
		transform: translateY(-3px);
		border-color: color-mix(in oklch, var(--accent-color) 60%, var(--border));
		box-shadow: 0 16px 36px -18px var(--accent-color);
	}
	.tank:focus-visible {
		outline: 2px solid var(--ring);
		outline-offset: 2px;
	}

	.head {
		display: flex;
		align-items: center;
		gap: 0.45rem;
	}
	.head :global(.ic) {
		height: 1rem;
		width: 1rem;
		color: var(--accent-color);
	}
	.label {
		font-size: var(--text-sm);
		font-weight: 500;
	}

	.vessel {
		position: relative;
		height: 124px;
		overflow: hidden;
		border-radius: var(--radius-md);
		background: color-mix(in oklch, var(--accent-color) 7%, var(--muted));
		border: 1px solid color-mix(in oklch, var(--accent-color) 18%, var(--border));
	}

	.liquid {
		position: absolute;
		inset: auto 0 0 0;
		color: var(--accent-color);
		background: linear-gradient(
			180deg,
			var(--accent-color),
			color-mix(in oklch, var(--accent-color) 70%, black)
		);
		transition: height 1.1s var(--ease-entrance);
		will-change: height;
	}
	.wave {
		position: absolute;
		top: -9px;
		left: 0;
		height: 14px;
		width: 200%;
		fill: currentColor;
	}
	.wave-a {
		animation: wave-x 2.6s linear infinite;
		opacity: 0.95;
	}
	.wave-b {
		top: -6px;
		animation: wave-x 4.1s linear infinite reverse;
		opacity: 0.45;
	}

	.readout {
		position: absolute;
		left: 10px;
		bottom: 8px;
		display: flex;
		flex-direction: column;
		line-height: 1;
		text-shadow: 0 1px 6px rgb(0 0 0 / 0.45);
		color: white;
	}
	.count {
		font-size: var(--text-2xl);
		font-weight: 700;
	}
	.word {
		margin-top: 3px;
		font-size: var(--text-xs);
		font-weight: 500;
		opacity: 0.95;
	}

	.state-good {
		--accent-color: #0ea5e9;
	}
	.state-warn {
		--accent-color: #f59e0b;
	}
	.state-bad {
		--accent-color: #ef4444;
	}
	.state-bad .vessel {
		background: linear-gradient(180deg, #1c1110, #2a0f0d);
		border-color: color-mix(in oklch, #ef4444 45%, transparent);
		box-shadow: inset 0 -24px 40px -16px rgb(239 68 68 / 0.5);
	}

	.fire {
		position: absolute;
		inset: 0;
		pointer-events: none;
	}
	.flame {
		position: absolute;
		bottom: 6px;
		width: 16px;
		height: 26px;
		border-radius: 50% 50% 50% 50% / 68% 68% 40% 40%;
		background: linear-gradient(180deg, #fde047 0%, #fb923c 45%, #ef4444 100%);
		transform-origin: bottom center;
		filter: blur(0.4px);
		box-shadow: 0 0 22px 2px rgb(249 115 22 / 0.55);
	}
	.f1 {
		left: calc(50% - 22px);
		animation: flick 0.9s ease-in-out infinite;
	}
	.f2 {
		left: calc(50% - 8px);
		height: 34px;
		animation: flick 0.7s ease-in-out infinite 0.15s;
	}
	.f3 {
		left: calc(50% + 8px);
		animation: flick 1.05s ease-in-out infinite 0.3s;
	}
	.ember {
		position: absolute;
		bottom: 18px;
		height: 3px;
		width: 3px;
		border-radius: 9999px;
		background: #fbbf24;
		box-shadow: 0 0 6px 1px rgb(251 191 36 / 0.8);
	}
	.e1 {
		left: 38%;
		animation: rise 1.9s linear infinite;
	}
	.e2 {
		left: 52%;
		animation: rise 2.4s linear infinite 0.5s;
	}
	.e3 {
		left: 62%;
		animation: rise 2.1s linear infinite 1s;
	}

	@keyframes wave-x {
		from {
			transform: translateX(0);
		}
		to {
			transform: translateX(-50%);
		}
	}
	@keyframes flick {
		0%,
		100% {
			transform: scaleY(1) scaleX(1);
			opacity: 0.9;
		}
		50% {
			transform: scaleY(1.25) scaleX(0.92) translateY(-2px);
			opacity: 1;
		}
	}
	@keyframes rise {
		0% {
			transform: translateY(0);
			opacity: 0;
		}
		20% {
			opacity: 1;
		}
		100% {
			transform: translateY(-72px);
			opacity: 0;
		}
	}
</style>
