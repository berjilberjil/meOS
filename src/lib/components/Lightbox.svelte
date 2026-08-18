<script lang="ts">
	import { lightbox, closeLightbox } from '$lib/stores/lightbox.svelte';
	import ZoomIn from '@lucide/svelte/icons/zoom-in';
	import ZoomOut from '@lucide/svelte/icons/zoom-out';
	import Maximize from '@lucide/svelte/icons/maximize';
	import RotateCcw from '@lucide/svelte/icons/rotate-ccw';
	import X from '@lucide/svelte/icons/x';

	let scale = $state(1);
	let tx = $state(0);
	let ty = $state(0);
	let dragging = false;
	let sx = 0;
	let sy = 0;
	let container: HTMLDivElement;

	// Reset transform whenever a new image opens.
	$effect(() => {
		if (lightbox.url) {
			scale = 1;
			tx = 0;
			ty = 0;
		}
	});

	function zoom(d: number) {
		scale = Math.min(6, Math.max(1, +(scale + d).toFixed(2)));
		if (scale === 1) {
			tx = 0;
			ty = 0;
		}
	}
	function reset() {
		scale = 1;
		tx = 0;
		ty = 0;
	}
	function onWheel(e: WheelEvent) {
		e.preventDefault();
		zoom(e.deltaY < 0 ? 0.25 : -0.25);
	}
	function down(e: MouseEvent) {
		if (scale === 1) return;
		dragging = true;
		sx = e.clientX - tx;
		sy = e.clientY - ty;
	}
	function move(e: MouseEvent) {
		if (!dragging) return;
		tx = e.clientX - sx;
		ty = e.clientY - sy;
	}
	function up() {
		dragging = false;
	}
	function key(e: KeyboardEvent) {
		if (!lightbox.url) return;
		if (e.key === 'Escape') closeLightbox();
		else if (e.key === '+' || e.key === '=') zoom(0.25);
		else if (e.key === '-') zoom(-0.25);
	}
	async function fullscreen() {
		try {
			if (!document.fullscreenElement) await container.requestFullscreen();
			else await document.exitFullscreen();
		} catch {
			/* ignore */
		}
	}
</script>

<svelte:window onkeydown={key} onmousemove={move} onmouseup={up} />

{#if lightbox.url}
	<div class="lb" bind:this={container}>
		<button class="backdrop" onclick={closeLightbox} aria-label="Close"></button>
		<img
			class="img"
			src={lightbox.url}
			alt={lightbox.alt}
			draggable="false"
			style="transform: translate({tx}px, {ty}px) scale({scale}); cursor: {scale > 1 ? (dragging ? 'grabbing' : 'grab') : 'default'};"
			onwheel={onWheel}
			onmousedown={down}
		/>
		<div class="bar">
			<button onclick={() => zoom(-0.3)} aria-label="Zoom out"><ZoomOut class="size-5" /></button>
			<span class="pct">{Math.round(scale * 100)}%</span>
			<button onclick={() => zoom(0.3)} aria-label="Zoom in"><ZoomIn class="size-5" /></button>
			<button onclick={reset} aria-label="Reset zoom"><RotateCcw class="size-5" /></button>
			<button onclick={fullscreen} aria-label="Full screen"><Maximize class="size-5" /></button>
			<button onclick={closeLightbox} aria-label="Close"><X class="size-5" /></button>
		</div>
	</div>
{/if}

<style>
	.lb {
		position: fixed;
		inset: 0;
		z-index: 100;
		display: grid;
		place-items: center;
		background: rgb(0 0 0 / 0.92);
		overflow: hidden;
	}
	.backdrop {
		position: absolute;
		inset: 0;
		background: transparent;
		border: none;
	}
	.img {
		position: relative;
		max-height: 92vh;
		max-width: 94vw;
		object-fit: contain;
		user-select: none;
		transition: transform 0.06s linear;
		box-shadow: 0 30px 80px -20px rgb(0 0 0 / 0.8);
	}
	.bar {
		position: fixed;
		bottom: calc(1.25rem + env(safe-area-inset-bottom));
		left: 50%;
		display: flex;
		align-items: center;
		gap: 0.25rem;
		transform: translateX(-50%);
		border-radius: 9999px;
		border: 1px solid rgb(255 255 255 / 0.14);
		background: rgb(20 20 22 / 0.9);
		backdrop-filter: blur(12px);
		padding: 0.35rem;
		box-shadow: 0 18px 40px -16px rgb(0 0 0 / 0.6);
	}
	.bar button {
		display: grid;
		height: 38px;
		width: 38px;
		place-items: center;
		border-radius: 9999px;
		color: #fff;
	}
	.bar button:hover {
		background: rgb(255 255 255 / 0.12);
	}
	.pct {
		min-width: 3rem;
		text-align: center;
		font-size: var(--text-xs);
		color: rgb(255 255 255 / 0.7);
	}
</style>
