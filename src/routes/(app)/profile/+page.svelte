<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { toast } from 'svelte-sonner';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import * as Card from '$lib/components/ui/card';
	import { supabaseBrowser } from '$lib/supabase/client';
	import {
		profileState,
		setAvatar,
		resetAvatar,
		setName,
		fileToAvatar,
		DEFAULT_AVATAR
	} from '$lib/stores/profile.svelte';
	import { setTheme, themeState, type Theme } from '$lib/stores/theme.svelte';
	import Camera from '@lucide/svelte/icons/camera';
	import RotateCcw from '@lucide/svelte/icons/rotate-ccw';
	import LogOut from '@lucide/svelte/icons/log-out';
	import Bell from '@lucide/svelte/icons/bell';
	import { getPersonal, savePersonal, BLOOD_GROUPS, EMPTY_PERSONAL, type Personal } from '$lib/profile/personal';
	import { enableNotifications, disableNotifications, notifyEnabled, notifySupported } from '$lib/notify';
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import { listInvites, createInvite, revokeInvite } from '$lib/auth/invites';
	import { inviteStatus } from '$lib/auth/inviteLogic';

	let fileEl: HTMLInputElement;
	let name = $state('');
	let email = $state('');
	let status = $state('');
	let busy = $state(false);

	let personal = $state<Personal>({ ...EMPTY_PERSONAL });
	let savingPersonal = $state(false);

	let notifSupported = $state(true);
	let notifOn = $state(false);

	const qc = useQueryClient();
	const invitesQ = createQuery(() => ({ queryKey: ['invites'], queryFn: () => listInvites() }));
	const genInvite = createMutation(() => ({
		mutationFn: () => createInvite(),
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['invites'] });
			toast.success('Invite created');
		}
	}));
	const revInvite = createMutation(() => ({
		mutationFn: (id: string) => revokeInvite(id),
		onSuccess: () => qc.invalidateQueries({ queryKey: ['invites'] })
	}));
	const nowIso = new Date().toISOString();
	function copyInvite(code: string) {
		navigator.clipboard.writeText(`${location.origin}/signup?invite=${code}`);
		toast.success('Invite link copied');
	}

	onMount(async () => {
		name = profileState.name;
		notifSupported = notifySupported();
		notifOn = notifyEnabled();
		const { data } = await supabaseBrowser().auth.getUser();
		email = data.user?.email ?? '';
		personal = await getPersonal();
	});

	async function turnOnNotif() {
		const ok = await enableNotifications();
		notifOn = ok;
		if (ok) toast.success('Reminders on');
		else toast.error('Permission denied — allow notifications in your browser');
	}
	function turnOffNotif() {
		disableNotifications();
		notifOn = false;
		toast.success('Reminders off');
	}

	async function savePersonalData() {
		savingPersonal = true;
		try {
			await savePersonal($state.snapshot(personal) as Personal);
			toast.success('Personal details saved');
		} catch {
			toast.error('Could not save details');
		}
		savingPersonal = false;
	}

	async function onPick(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		if (!file) return;
		busy = true;
		status = '';
		try {
			setAvatar(await fileToAvatar(file));
			status = 'Photo updated.';
			toast.success('Profile photo updated');
		} catch (err) {
			status = err instanceof Error ? err.message : 'Could not update photo.';
			toast.error('Could not update photo');
		}
		busy = false;
	}

	function reset() {
		resetAvatar();
		status = 'Photo reset to default.';
		toast.success('Photo reset to default');
	}

	function saveName() {
		setName(name);
		name = profileState.name;
		status = 'Name saved.';
		toast.success('Name saved');
	}

	const themes: { key: Theme; label: string }[] = [
		{ key: 'light', label: 'Light' },
		{ key: 'dark', label: 'Dark' },
		{ key: 'system', label: 'System' }
	];
	function pickTheme(t: Theme) {
		themeState.current = t;
		setTheme(t);
	}

	async function logout() {
		await supabaseBrowser().auth.signOut();
		await goto('/login');
	}

	const isDefault = $derived(profileState.avatar === DEFAULT_AVATAR);
</script>

<div class="kn-stagger mx-auto flex w-full max-w-2xl flex-col gap-4">
	<div>
		<h1 class="text-xl font-semibold tracking-tight">Profile</h1>
		<p class="text-sm text-muted-foreground">How you show up across MyOS.</p>
	</div>

	<Card.Root>
		<Card.Content class="flex flex-col gap-5 pt-6 sm:flex-row sm:items-center">
			<div class="ava-wrap">
				<img class="ava" src={profileState.avatar} alt={profileState.name} />
				<button
					class="ava-edit"
					onclick={() => fileEl.click()}
					disabled={busy}
					aria-label="Change photo"
				>
					<Camera class="size-4" />
				</button>
			</div>

			<div class="flex flex-1 flex-col gap-3">
				<div class="flex flex-wrap gap-2">
					<Button variant="outline" size="sm" class="gap-2" disabled={busy} onclick={() => fileEl.click()}>
						<Camera class="size-4" /> Change photo
					</Button>
					<Button
						variant="ghost"
						size="sm"
						class="gap-2"
						disabled={busy || isDefault}
						onclick={reset}
					>
						<RotateCcw class="size-4" /> Reset
					</Button>
				</div>
				<p class="text-xs text-muted-foreground">JPG or PNG. Cropped to a square, stored on this device.</p>
				{#if status}<p class="text-xs text-primary">{status}</p>{/if}
			</div>

			<input
				bind:this={fileEl}
				type="file"
				accept="image/png,image/jpeg,image/webp"
				class="hidden"
				onchange={onPick}
			/>
		</Card.Content>
	</Card.Root>

	<Card.Root>
		<Card.Header>
			<Card.Title>Display name</Card.Title>
			<Card.Description>Shown on the lock screen and sidebar.</Card.Description>
		</Card.Header>
		<Card.Content class="flex gap-2">
			<Input bind:value={name} placeholder="Your name" class="max-w-xs" onkeydown={(e) => e.key === 'Enter' && saveName()} />
			<Button size="sm" disabled={!name.trim() || name === profileState.name} onclick={saveName}>Save</Button>
		</Card.Content>
	</Card.Root>

	<Card.Root>
		<Card.Header>
			<Card.Title>Body &amp; personal</Card.Title>
			<Card.Description>One-time details — only your weight tends to change.</Card.Description>
		</Card.Header>
		<Card.Content class="flex flex-col gap-3">
			<div class="grid gap-3 sm:grid-cols-2">
				<label class="flex flex-col gap-1">
					<span class="text-xs text-muted-foreground">Current weight (kg)</span>
					<Input type="number" step="0.1" bind:value={personal.current_weight_kg} placeholder="—" />
				</label>
				<label class="flex flex-col gap-1">
					<span class="text-xs text-muted-foreground">Goal weight (kg)</span>
					<Input type="number" step="0.1" bind:value={personal.goal_weight_kg} placeholder="—" />
				</label>
				<label class="flex flex-col gap-1">
					<span class="text-xs text-muted-foreground">Height (cm)</span>
					<Input type="number" step="0.1" bind:value={personal.height_cm} placeholder="—" />
				</label>
				<label class="flex flex-col gap-1">
					<span class="text-xs text-muted-foreground">Blood group</span>
					<select bind:value={personal.blood_group} class="h-9 rounded-md border border-border bg-background px-2 text-sm">
						<option value={null}>—</option>
						{#each BLOOD_GROUPS as bg}<option value={bg}>{bg}</option>{/each}
					</select>
				</label>
				<label class="flex flex-col gap-1">
					<span class="text-xs text-muted-foreground">Date of birth</span>
					<Input type="date" bind:value={personal.dob} />
				</label>
				<label class="flex flex-col gap-1">
					<span class="text-xs text-muted-foreground">Sex</span>
					<select bind:value={personal.sex} class="h-9 rounded-md border border-border bg-background px-2 text-sm">
						<option value={null}>—</option>
						<option value="male">Male</option>
						<option value="female">Female</option>
						<option value="other">Other</option>
					</select>
				</label>
			</div>
			<div>
				<Button size="sm" disabled={savingPersonal} onclick={savePersonalData}>
					{savingPersonal ? 'Saving…' : 'Save details'}
				</Button>
			</div>
		</Card.Content>
	</Card.Root>

	<Card.Root>
		<Card.Header>
			<Card.Title>Appearance</Card.Title>
			<Card.Description>Theme used everywhere.</Card.Description>
		</Card.Header>
		<Card.Content class="flex flex-wrap gap-2">
			{#each themes as t (t.key)}
				<Button
					variant={themeState.current === t.key ? 'default' : 'outline'}
					size="sm"
					onclick={() => pickTheme(t.key)}
				>
					{t.label}
				</Button>
			{/each}
		</Card.Content>
	</Card.Root>

	<Card.Root>
		<Card.Header>
			<Card.Title>Notifications</Card.Title>
			<Card.Description>A daily nudge to keep your journal streak alive.</Card.Description>
		</Card.Header>
		<Card.Content class="flex flex-wrap items-center gap-3">
			{#if !notifSupported}
				<p class="text-sm text-muted-foreground">This browser doesn't support notifications.</p>
			{:else if notifOn}
				<span class="flex items-center gap-1.5 text-sm text-primary"><Bell class="size-4" /> Enabled</span>
				<Button variant="outline" size="sm" onclick={turnOffNotif}>Turn off</Button>
			{:else}
				<Button size="sm" class="gap-2" onclick={turnOnNotif}><Bell class="size-4" /> Enable reminders</Button>
			{/if}
		</Card.Content>
	</Card.Root>

	<Card.Root>
		<Card.Header class="flex-row items-center justify-between">
			<div>
				<Card.Title>Invites</Card.Title>
				<Card.Description>Bring people onto MyOS. Each code works once.</Card.Description>
			</div>
			<Button size="sm" disabled={genInvite.isPending} onclick={() => genInvite.mutate()}>Generate</Button>
		</Card.Header>
		<Card.Content class="flex flex-col gap-2">
			{#each invitesQ.data ?? [] as inv (inv.id)}
				{@const st = inviteStatus(inv, nowIso)}
				<div class="flex items-center gap-2 text-sm">
					<span class="font-mono font-semibold">{inv.code}</span>
					<span class="rounded-full bg-secondary px-2 py-0.5 text-xs">{st}</span>
					{#if st === 'active'}
						<button class="text-xs text-muted-foreground hover:underline" onclick={() => copyInvite(inv.code)}>Copy link</button>
						<button class="ml-auto text-xs text-muted-foreground hover:text-destructive" onclick={() => revInvite.mutate(inv.id)}>Revoke</button>
					{/if}
				</div>
			{:else}
				<p class="text-sm text-muted-foreground">No invites yet. Generate one to add someone.</p>
			{/each}
		</Card.Content>
	</Card.Root>

	<Card.Root>
		<Card.Header>
			<Card.Title>Account</Card.Title>
			<Card.Description>{email || 'Signed in'}</Card.Description>
		</Card.Header>
		<Card.Content>
			<Button variant="outline" size="sm" class="gap-2" onclick={logout}>
				<LogOut class="size-4" /> Log out
			</Button>
		</Card.Content>
	</Card.Root>
</div>

<style>
	.ava-wrap {
		position: relative;
		flex-shrink: 0;
		width: 96px;
		height: 96px;
	}
	.ava {
		height: 96px;
		width: 96px;
		border-radius: 9999px;
		object-fit: cover;
		object-position: center 18%;
		background: radial-gradient(
			circle at 50% 32%,
			color-mix(in oklch, var(--primary) 16%, var(--card)),
			var(--card)
		);
		box-shadow:
			0 0 0 1.5px color-mix(in oklch, var(--primary) 35%, transparent),
			0 0 0 5px color-mix(in oklch, var(--primary) 10%, transparent);
	}
	.ava-edit {
		position: absolute;
		right: -2px;
		bottom: -2px;
		display: grid;
		height: 30px;
		width: 30px;
		place-items: center;
		border-radius: 9999px;
		border: 2px solid var(--card);
		background: var(--primary);
		color: var(--primary-foreground);
		transition: transform var(--duration-fast) var(--ease-entrance);
	}
	.ava-edit:hover {
		transform: scale(1.08);
	}
	.ava-edit:focus-visible {
		outline: 2px solid var(--ring);
		outline-offset: 2px;
	}
	.ava-edit:disabled {
		opacity: 0.6;
	}
</style>
