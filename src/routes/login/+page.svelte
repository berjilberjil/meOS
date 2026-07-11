<script lang="ts">
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { supabaseBrowser } from '$lib/supabase/client';
	import { goto, invalidateAll } from '$app/navigation';
	import { profileState } from '$lib/stores/profile.svelte';
	import Eye from '@lucide/svelte/icons/eye';
	import EyeOff from '@lucide/svelte/icons/eye-off';

	let email = $state('');
	let password = $state('');
	let showPw = $state(false);
	let code = $state('');
	let needMfa = $state(false);
	let factorId = $state('');
	let error = $state('');
	let busy = $state(false);

	function greetWord(): string {
		const h = new Date().getHours();
		if (h < 5) return 'Still up';
		if (h < 12) return 'Good morning';
		if (h < 17) return 'Good afternoon';
		if (h < 21) return 'Good evening';
		return 'Good night';
	}
	const hello = greetWord();

	async function signIn() {
		busy = true;
		error = '';
		const sb = supabaseBrowser();
		const { error: e } = await sb.auth.signInWithPassword({ email, password });
		if (e) {
			error = e.message;
			busy = false;
			return;
		}
		const { data } = await sb.auth.mfa.listFactors();
		const totp = data?.totp?.[0];
		if (totp) {
			factorId = totp.id;
			needMfa = true;
			busy = false;
		} else {
			await invalidateAll();
			await goto('/');
		}
	}

	async function verify() {
		busy = true;
		error = '';
		const sb = supabaseBrowser();
		const { data: ch, error: ce } = await sb.auth.mfa.challenge({ factorId });
		if (ce || !ch) {
			error = ce?.message ?? 'Challenge failed';
			busy = false;
			return;
		}
		const { error: e } = await sb.auth.mfa.verify({ factorId, challengeId: ch.id, code });
		if (e) {
			error = e.message;
			busy = false;
			return;
		}
		await invalidateAll();
		await goto('/');
	}
</script>

<svelte:head>
	<link rel="preload" as="image" href="/me.webp" />
</svelte:head>

<div class="auth">
	<!-- Left — colored brand panel -->
	<section class="brandside">
		<div class="dots" aria-hidden="true"></div>
		<div class="brand-inner kn-enter">
			<div class="float">
				<img
					class="ava"
					src={profileState.avatar}
					alt="{profileState.name}'s avatar"
					width="200"
					height="200"
					fetchpriority="high"
					decoding="async"
				/>
			</div>
			<h1 class="greet">{hello},<br /><span class="name">{profileState.name}</span></h1>
			<p class="sub">Welcome back to your OS.</p>
		</div>
	</section>

	<!-- Right — black form panel -->
	<section class="formside">
		<div class="formbox kn-enter">
			<h2 class="form-title">{needMfa ? 'Verify it’s you' : 'Sign in'}</h2>
			<p class="form-hint">
				{needMfa ? 'Enter your authenticator code.' : 'Use your owner credentials.'}
			</p>

			<div class="form">
				{#if !needMfa}
					<Input bind:value={email} placeholder="email" type="email" autocomplete="username" />
					<div class="pw">
						<Input
							bind:value={password}
							placeholder="password"
							type={showPw ? 'text' : 'password'}
							autocomplete="current-password"
							onkeydown={(e) => e.key === 'Enter' && signIn()}
						/>
						<button type="button" class="eye" onclick={() => (showPw = !showPw)} aria-label={showPw ? 'Hide password' : 'Show password'}>
							{#if showPw}<EyeOff class="size-4" />{:else}<Eye class="size-4" />{/if}
						</button>
					</div>
					<Button class="mt-1 w-full" disabled={busy} onclick={signIn}>
						{busy ? 'Signing in…' : 'Sign in'}
					</Button>
				{:else}
					<Input
						bind:value={code}
						placeholder="6-digit code"
						inputmode="numeric"
						onkeydown={(e) => e.key === 'Enter' && verify()}
					/>
					<Button class="mt-1 w-full" disabled={busy} onclick={verify}>
						{busy ? 'Verifying…' : 'Verify'}
					</Button>
				{/if}
				{#if error}<p class="err">{error}</p>{/if}
			</div>

			<a class="signup" href="/signup">Have an invite? Sign up</a>
			<p class="foot">Private · invite-only</p>
		</div>
	</section>
</div>

<style>
	.auth {
		display: flex;
		min-height: 100dvh;
		flex-direction: column;
	}
	@media (min-width: 768px) {
		.auth {
			flex-direction: row;
		}
	}

	/* Left — colored */
	.brandside {
		position: relative;
		display: grid;
		place-items: center;
		overflow: hidden;
		padding: 2.5rem 1.5rem;
		background: linear-gradient(155deg, #1d4ed8 0%, #2563eb 45%, #06b6d4 100%);
	}
	@media (min-width: 768px) {
		.brandside {
			flex: 1.1;
		}
	}
	.dots {
		position: absolute;
		inset: 0;
		background-image: radial-gradient(circle, rgba(255, 255, 255, 0.16) 1px, transparent 1.5px);
		background-size: 24px 24px;
	}
	.brand-inner {
		position: relative;
		display: flex;
		flex-direction: column;
		align-items: center;
		text-align: center;
		gap: 0.5rem;
	}
	@media (min-width: 768px) {
		.brand-inner {
			align-items: flex-start;
			text-align: left;
		}
	}
	.float {
		animation: float 5.5s ease-in-out infinite;
	}
	.ava {
		display: block;
		height: clamp(130px, 22vw, 200px);
		width: clamp(130px, 22vw, 200px);
		object-fit: contain;
		filter: drop-shadow(0 18px 32px rgb(0 0 0 / 0.45));
	}
	.greet {
		margin-top: 0.5rem;
		font-size: clamp(1.8rem, 4vw, 2.6rem);
		font-weight: 700;
		line-height: 1.05;
		letter-spacing: -0.02em;
		color: #fff;
	}
	.greet .name {
		color: rgb(255 255 255 / 0.78);
	}
	.sub {
		font-size: var(--text-sm);
		color: rgb(255 255 255 / 0.75);
	}

	/* Right — black */
	.formside {
		display: grid;
		flex: 1;
		place-items: center;
		padding: 2.5rem 1.5rem;
		background: #000;
	}
	.formbox {
		display: flex;
		width: 100%;
		max-width: 22rem;
		flex-direction: column;
		gap: 0.6rem;
	}
	.form-title {
		font-size: var(--text-xl);
		font-weight: 600;
		color: #fff;
	}
	.form-hint {
		margin-top: -0.2rem;
		margin-bottom: 0.6rem;
		font-size: var(--text-sm);
		color: rgb(255 255 255 / 0.5);
	}
	.form {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
	}
	.pw {
		position: relative;
	}
	.eye {
		position: absolute;
		right: 8px;
		top: 50%;
		display: grid;
		height: 28px;
		width: 28px;
		transform: translateY(-50%);
		place-items: center;
		border-radius: var(--radius-md);
		color: rgb(255 255 255 / 0.55);
	}
	.eye:hover {
		color: #fff;
		background: rgb(255 255 255 / 0.08);
	}
	.err {
		font-size: var(--text-sm);
		color: var(--destructive);
	}
	.foot {
		margin-top: 1.1rem;
		font-size: var(--text-xs);
		color: rgb(255 255 255 / 0.4);
	}
	.signup {
		margin-top: 0.9rem;
		font-size: var(--text-sm);
		color: rgb(255 255 255 / 0.55);
	}
	.signup:hover {
		color: #fff;
	}

	@keyframes float {
		0%,
		100% {
			transform: translateY(0);
		}
		50% {
			transform: translateY(-7px);
		}
	}
</style>
