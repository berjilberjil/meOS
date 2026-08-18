<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { supabaseBrowser } from '$lib/supabase/client';
	import { redeemInvite, REDEEM_ERROR_COPY } from '$lib/auth/redeem';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';

	let code = $state((page.url.searchParams.get('invite') ?? '').toUpperCase());
	let email = $state(page.url.searchParams.get('email') ?? '');
	let password = $state('');
	let confirm = $state('');
	let error = $state('');
	let busy = $state(false);

	async function submit() {
		error = '';
		if (password !== confirm) {
			error = 'Passwords do not match.';
			return;
		}
		busy = true;
		const r = await redeemInvite({ code: code.trim().toUpperCase(), email: email.trim(), password });
		if (!r.ok) {
			error = REDEEM_ERROR_COPY[r.error] ?? REDEEM_ERROR_COPY.unknown;
			busy = false;
			return;
		}
		const { error: signInErr } = await supabaseBrowser().auth.signInWithPassword({
			email: email.trim(),
			password
		});
		busy = false;
		if (signInErr) {
			error = 'Account created — please sign in.';
			await goto('/login');
			return;
		}
		await goto('/');
	}
</script>

<div class="wrap">
	<div class="formbox kn-enter">
		<h1 class="title">Join MyOS</h1>
		<p class="hint">You need an invite code to create an account.</p>
		<div class="form">
			<Input placeholder="Invite code" bind:value={code} onblur={() => (code = code.trim().toUpperCase())} />
			<Input type="email" placeholder="Email" bind:value={email} autocomplete="username" />
			<Input type="password" placeholder="Password (min 8)" bind:value={password} autocomplete="new-password" />
			<Input type="password" placeholder="Confirm password" bind:value={confirm} autocomplete="new-password"
				onkeydown={(e) => e.key === 'Enter' && submit()} />
			{#if error}<p class="err">{error}</p>{/if}
			<Button class="mt-1 w-full" disabled={busy || !code || !email || !password} onclick={submit}>
				{busy ? 'Creating…' : 'Create account'}
			</Button>
			<a class="link" href="/login">Already have an account? Sign in</a>
		</div>
	</div>
</div>

<style>
	.wrap {
		display: grid;
		min-height: 100dvh;
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
	.title {
		font-size: var(--text-xl);
		font-weight: 600;
		color: #fff;
	}
	.hint {
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
	.err {
		font-size: var(--text-sm);
		color: var(--destructive);
	}
	.link {
		margin-top: 0.4rem;
		text-align: center;
		font-size: var(--text-sm);
		color: rgb(255 255 255 / 0.55);
	}
	.link:hover {
		color: #fff;
	}
</style>
