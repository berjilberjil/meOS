<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { openSectionFromQuery, focusSection } from '$lib/openFromQuery';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { cn } from '$lib/utils';
	import { todayIso } from '$lib/finance/dates';
	import { formatINR, toPaise } from '$lib/money';
	import {
		listAssets,
		createAsset,
		removeAsset,
		updateAsset,
		getAssetSettings,
		saveAssetSettings
	} from '$lib/assets/assets';
	import {
		dashboard,
		humanDays,
		type AssetMetrics,
		type Band,
		type Dashboard
	} from '$lib/assets/calc';
	import { ASSET_CATEGORIES, LIABILITY_CATEGORIES, type AssetKind, type Period } from '$lib/assets/types';
	import { toast } from 'svelte-sonner';
	import Trash2 from '@lucide/svelte/icons/trash-2';
	import Archive from '@lucide/svelte/icons/archive';
	import Plus from '@lucide/svelte/icons/plus';

	const qc = useQueryClient();
	const today = todayIso();

	const assetsQ = createQuery(() => ({ queryKey: ['assets'], queryFn: () => listAssets() }));
	const settingsQ = createQuery(() => ({ queryKey: ['asset_settings'], queryFn: () => getAssetSettings() }));
	function invalidate() {
		qc.invalidateQueries({ queryKey: ['assets'] });
	}

	const settings = $derived(
		settingsQ.data ?? { income_amount_paise: 0, income_period: 'monthly' as Period, global_target_cpd_paise: 1000 }
	);
	const dash = $derived<Dashboard>(dashboard(assetsQ.data ?? [], settings, today));
	const active = $derived(dash.items.filter((m) => !m.retired));
	const retired = $derived(dash.items.filter((m) => m.retired));

	// Sort: "worst" keeps the dashboard's worst-first order; "timeline" is newest-first.
	let sortMode = $state<'worst' | 'timeline'>('worst');
	const shown = $derived(
		sortMode === 'timeline'
			? [...active].sort((a, b) => b.asset.purchase_date.localeCompare(a.asset.purchase_date))
			: active
	);

	const BAND: Record<Band, { label: string; color: string; note: string }> = {
		good: { label: 'Healthy', color: 'var(--status-success)', note: "You're living well within your means." },
		warning: { label: 'Getting heavy', color: 'var(--status-warning)', note: 'Ease up before it becomes a habit.' },
		bad: { label: 'Overspending', color: 'var(--destructive)', note: 'Your stuff is eating your income.' },
		unset: { label: '', color: 'var(--muted-foreground)', note: '' }
	};

	function perDay(paise: number): string {
		return `${formatINR(paise)}/day`;
	}
	function verdict(m: AssetMetrics): string {
		if (m.retired) return `Retired · cost ${perDay(m.costPerDayPaise)} over its life`;
		if (m.isLiability)
			return `Costs ${perDay(m.costPerDayPaise)}, every day${m.asset.end_date ? ` until ${m.asset.end_date}` : ''}`;
		if (m.isPaidOff) {
			const ago = m.daysOwned - m.daysNeeded;
			return `✓ Paid for itself ${ago <= 0 ? 'just now' : humanDays(ago) + ' ago'} — ${perDay(m.costPerDayPaise)} and falling`;
		}
		return `Cheap (≤ ${perDay(m.impliedTargetPaise)}) in ${humanDays(m.daysRemaining)}`;
	}
	function accent(m: AssetMetrics): string {
		if (m.retired) return 'var(--muted-foreground)';
		if (m.isLiability) return 'var(--status-info)';
		if (m.isPaidOff) return 'var(--status-success)';
		return m.progressPct >= 50 ? 'var(--status-warning)' : 'var(--primary)';
	}

	// ---- Add form ----
	let kind = $state<AssetKind>('asset');
	let name = $state('');
	let priceStr = $state('');
	let date = $state(todayIso());
	let category = $state(ASSET_CATEGORIES[0]);
	let billingPeriod = $state<Period>('monthly');
	let endDate = $state('');
	let targetStr = $state('');
	let lifespanStr = $state('');
	let salvageStr = $state('');
	let saving = $state(false);
	let showAdvanced = $state(false);

	const cats = $derived(kind === 'liability' ? LIABILITY_CATEGORIES : ASSET_CATEGORIES);
	$effect(() => {
		if (!cats.includes(category)) category = cats[0];
	});

	async function addItem() {
		if (!name.trim() || !priceStr) return;
		saving = true;
		try {
			await createAsset({
				name: name.trim(),
				kind,
				price_paise: toPaise(Number(priceStr)),
				purchase_date: date,
				category,
				billing_period: kind === 'liability' ? billingPeriod : null,
				end_date: kind === 'liability' && endDate ? endDate : null,
				expected_lifespan_days: kind === 'asset' && lifespanStr ? Number(lifespanStr) : null,
				target_cost_per_day_paise: kind === 'asset' && targetStr ? toPaise(Number(targetStr)) : null,
				salvage_value_paise: kind === 'asset' && salvageStr ? toPaise(Number(salvageStr)) : 0
			});
			invalidate();
			name = '';
			priceStr = '';
			targetStr = '';
			lifespanStr = '';
			salvageStr = '';
			endDate = '';
			toast.success(kind === 'liability' ? 'Liability added' : 'Asset added');
		} catch {
			toast.error('Could not add — is the table migrated?');
		}
		saving = false;
	}
	async function del(id: string) {
		await removeAsset(id);
		invalidate();
		toast.success('Removed');
	}
	async function retire(id: string) {
		await updateAsset(id, { retired_on: today });
		invalidate();
		toast.success('Retired');
	}
	async function unretire(id: string) {
		await updateAsset(id, { retired_on: null });
		invalidate();
	}

	// ---- Settings editor (income + global target) ----
	let incomeStr = $state('');
	let incomePeriod = $state<Period>('monthly');
	let targetCpdStr = $state('');
	let seeded = false;
	let savingSettings = $state(false);
	$effect(() => {
		if (seeded || !settingsQ.data) return;
		incomeStr = settingsQ.data.income_amount_paise ? String(settingsQ.data.income_amount_paise / 100) : '';
		incomePeriod = settingsQ.data.income_period;
		targetCpdStr = String(settingsQ.data.global_target_cpd_paise / 100);
		seeded = true;
	});
	async function saveSettings() {
		savingSettings = true;
		try {
			await saveAssetSettings({
				income_amount_paise: incomeStr ? toPaise(Number(incomeStr)) : 0,
				income_period: incomePeriod,
				global_target_cpd_paise: targetCpdStr ? toPaise(Number(targetCpdStr)) : 1000
			});
			qc.invalidateQueries({ queryKey: ['asset_settings'] });
			toast.success('Saved');
		} catch {
			toast.error('Could not save settings');
		}
		savingSettings = false;
	}

	// Bottom-nav quick actions: /assets?add=asset|liability|income
	let settingsOpen = $state(false);
	onMount(() =>
		openSectionFromQuery(page.url.searchParams.get('add'), {
			asset: () => {
				kind = 'asset';
				focusSection('asset-add');
			},
			liability: () => {
				kind = 'liability';
				focusSection('asset-add');
			},
			income: () => {
				settingsOpen = true;
				focusSection('asset-settings');
			}
		})
	);
</script>

<div class="kn-stagger flex flex-col gap-4">
	<div>
		<h1 class="text-xl font-semibold tracking-tight">Assets</h1>
		<p class="text-sm text-muted-foreground">
			What you own, what it costs per day, and whether you're overspending.
		</p>
	</div>

	<!-- Hero: daily-burn health -->
	<Card.Root>
		<Card.Content class="flex flex-col gap-4 pt-6">
			{#if dash.band === 'unset'}
				<div class="flex flex-col gap-2">
					<div class="text-sm text-muted-foreground">
						Your things burn <span class="font-semibold text-foreground">{perDay(dash.trueDailyBurnPaise)}</span>.
					</div>
					<button
						class="w-fit text-sm font-semibold text-primary underline-offset-2 hover:underline"
						onclick={() => {
							settingsOpen = true;
							focusSection('asset-settings');
						}}>Set your income to see if that's sustainable →</button
					>
				</div>
			{:else}
				<div class="flex items-end justify-between gap-4">
					<div>
						<div class="flex items-baseline gap-2">
							<span class="text-5xl font-bold tracking-tight" style="color: {BAND[dash.band].color}"
								>{dash.burnPct}%</span
							>
							<span class="text-lg font-semibold" style="color: {BAND[dash.band].color}"
								>{BAND[dash.band].label}</span
							>
						</div>
						<div class="text-xs text-muted-foreground">of your daily income goes to things you own</div>
					</div>
				</div>
				<div class="h-2 w-full overflow-hidden rounded-full bg-secondary">
					<div
						class="h-full rounded-full transition-[width] duration-500"
						style="width: {Math.min(100, dash.burnPct ?? 0)}%; background: {BAND[dash.band].color}"
					></div>
				</div>
				<div class="grid grid-cols-3 gap-2 text-center">
					<div>
						<div class="text-xs text-muted-foreground">True burn</div>
						<div class="text-base font-bold">{perDay(dash.trueDailyBurnPaise)}</div>
					</div>
					<div>
						<div class="text-xs text-muted-foreground">Income</div>
						<div class="text-base font-bold">{perDay(dash.dailyIncomePaise)}</div>
					</div>
					<div>
						<div class="text-xs text-muted-foreground">Left over</div>
						<div class="text-base font-bold" style={dash.leftoverPaise < 0 ? 'color: var(--destructive)' : ''}>
							{perDay(dash.leftoverPaise)}
						</div>
					</div>
				</div>
				<p class="text-xs text-muted-foreground">{BAND[dash.band].note}</p>
			{/if}

			<div class="flex flex-wrap items-center gap-2 text-xs">
				<span class="rounded-full border border-border px-2.5 py-1">
					assets <span class="font-semibold">{perDay(dash.assetBurnPaise)}</span>
				</span>
				<span class="rounded-full border border-border px-2.5 py-1">
					liabilities <span class="font-semibold">{perDay(dash.liabilityBurnPaise)}</span>
				</span>
				{#if dash.basisPaise > 0}
					<span class="text-muted-foreground">
						Cost of ownership now {perDay(dash.currentOwnershipPaise)} and falling ·
						{formatINR(dash.recoveredPaise)} of {formatINR(dash.basisPaise)} recovered
					</span>
				{/if}
			</div>

			<!-- Income & target editor -->
			<details id="asset-settings" bind:open={settingsOpen} class="border-t border-border pt-3">
				<summary class="cursor-pointer text-xs font-medium text-muted-foreground select-none">
					Income &amp; target
				</summary>
				<div class="mt-3 flex flex-wrap items-end gap-2">
					<label class="flex flex-col gap-1 text-xs text-muted-foreground">
						Income
						<Input type="number" step="1" placeholder="₹" bind:value={incomeStr} class="w-32" />
					</label>
					<select
						bind:value={incomePeriod}
						class="h-9 rounded-md border border-border bg-background px-2 text-sm"
					>
						<option value="monthly">per month</option>
						<option value="yearly">per year</option>
						<option value="weekly">per week</option>
						<option value="daily">per day</option>
					</select>
					<label class="flex flex-col gap-1 text-xs text-muted-foreground">
						"Cheap" at (₹/day)
						<Input type="number" step="1" placeholder="10" bind:value={targetCpdStr} class="w-28" />
					</label>
					<Button variant="outline" disabled={savingSettings} onclick={saveSettings}>Save</Button>
				</div>
			</details>
		</Card.Content>
	</Card.Root>

	<!-- Add asset / liability -->
	<Card.Root id="asset-add">
		<Card.Header class="pb-2"><Card.Title>Add something</Card.Title></Card.Header>
		<Card.Content class="flex flex-col gap-3">
			<div class="flex gap-1 rounded-lg bg-secondary p-1 text-sm">
				<button
					class={cn('flex-1 rounded-md py-1.5', kind === 'asset' && 'bg-card font-semibold shadow-sm')}
					onclick={() => (kind = 'asset')}>Asset</button
				>
				<button
					class={cn('flex-1 rounded-md py-1.5', kind === 'liability' && 'bg-card font-semibold shadow-sm')}
					onclick={() => (kind = 'liability')}>Liability</button
				>
			</div>
			<div class="flex flex-wrap items-end gap-2">
				<Input placeholder={kind === 'liability' ? 'What subscription / loan?' : 'What did you buy?'} bind:value={name} class="w-56" />
				<Input
					type="number"
					step="1"
					placeholder={kind === 'liability' ? '₹ per period' : '₹ price'}
					bind:value={priceStr}
					class="w-28"
				/>
				<Input type="date" bind:value={date} class="w-40" />
				<select bind:value={category} class="h-9 rounded-md border border-border bg-background px-2 text-sm">
					{#each cats as c (c)}<option value={c}>{c}</option>{/each}
				</select>
				{#if kind === 'liability'}
					<select bind:value={billingPeriod} class="h-9 rounded-md border border-border bg-background px-2 text-sm">
						<option value="monthly">monthly</option>
						<option value="yearly">yearly</option>
						<option value="weekly">weekly</option>
						<option value="daily">daily</option>
					</select>
					<label class="flex flex-col gap-1 text-xs text-muted-foreground">
						ends (optional)
						<Input type="date" bind:value={endDate} class="w-40" />
					</label>
				{/if}
				<Button disabled={!name.trim() || !priceStr || saving} onclick={addItem}>
					<Plus class="size-4" /> Add
				</Button>
			</div>

			{#if kind === 'asset'}
				<details bind:open={showAdvanced}>
					<summary class="cursor-pointer text-xs text-muted-foreground select-none">
						Advanced — set your own ROI target, lifespan or resale value
					</summary>
					<div class="mt-2 flex flex-wrap items-end gap-2">
						<label class="flex flex-col gap-1 text-xs text-muted-foreground">
							"Cheap" at (₹/day)
							<Input type="number" step="1" placeholder="global default" bind:value={targetStr} class="w-32" />
						</label>
						<label class="flex flex-col gap-1 text-xs text-muted-foreground">
							Lifespan (days)
							<Input type="number" step="1" placeholder="optional" bind:value={lifespanStr} class="w-28" />
						</label>
						<label class="flex flex-col gap-1 text-xs text-muted-foreground">
							Resale value (₹)
							<Input type="number" step="1" placeholder="0" bind:value={salvageStr} class="w-28" />
						</label>
					</div>
				</details>
			{/if}
		</Card.Content>
	</Card.Root>

	<!-- Timeline -->
	<div class="flex items-center justify-between">
		<h2 class="text-sm font-semibold">Your things — {active.length}</h2>
		<div class="flex gap-1 rounded-lg bg-secondary p-0.5 text-xs">
			<button
				class={cn('rounded-md px-2.5 py-1', sortMode === 'worst' && 'bg-card font-semibold shadow-sm')}
				onclick={() => (sortMode = 'worst')}>Worst first</button
			>
			<button
				class={cn('rounded-md px-2.5 py-1', sortMode === 'timeline' && 'bg-card font-semibold shadow-sm')}
				onclick={() => (sortMode = 'timeline')}>Timeline</button
			>
		</div>
	</div>

	<div class="flex flex-col gap-2.5">
		{#each shown as m (m.asset.id)}
			<div class="item" style="--row-accent: {accent(m)}">
				<div class="flex items-start justify-between gap-3">
					<div class="min-w-0">
						<div class="flex items-center gap-2">
							<span class="truncate font-semibold">{m.asset.name}</span>
							<span class="rounded-full bg-secondary px-2 py-0.5 text-[11px]">{m.asset.category}</span>
							{#if m.isLiability}
								<span class="rounded-full border border-border px-2 py-0.5 text-[11px] text-muted-foreground"
									>liability</span
								>
							{/if}
						</div>
						<div class="text-xs text-muted-foreground">
							{#if m.isLiability}
								{formatINR(m.asset.price_paise)}/{m.asset.billing_period} · since {m.asset.purchase_date}
							{:else}
								{formatINR(m.asset.price_paise)} · owned {m.daysOwned} day{m.daysOwned === 1 ? '' : 's'} (since {m.asset.purchase_date})
							{/if}
						</div>
					</div>
					<div class="shrink-0 text-right">
						<div class="text-xl font-bold leading-none">{formatINR(m.costPerDayPaise)}</div>
						<div class="text-[11px] text-muted-foreground">per day</div>
					</div>
				</div>

				{#if !m.isLiability}
					<div class="mt-2.5">
						<div class="h-1.5 w-full overflow-hidden rounded-full bg-secondary">
							<div
								class="h-full rounded-full"
								style="width: {m.progressPct}%; background: var(--row-accent)"
							></div>
						</div>
						<div class="mt-1 text-[11px] text-muted-foreground">
							{m.daysOwned} of {m.daysNeeded} days @ {perDay(m.impliedTargetPaise)}
						</div>
					</div>
				{/if}

				<div class="mt-2 flex items-center justify-between gap-2">
					<span class="text-xs font-medium" style="color: var(--row-accent)">{verdict(m)}</span>
					<div class="flex items-center gap-1">
						<button class="icon-btn" title="Retire (sold / binned)" onclick={() => retire(m.asset.id)} aria-label="Retire">
							<Archive class="size-4" />
						</button>
						<button class="icon-btn hover:text-destructive" title="Delete" onclick={() => del(m.asset.id)} aria-label="Delete">
							<Trash2 class="size-4" />
						</button>
					</div>
				</div>
			</div>
		{:else}
			<Card.Root>
				<Card.Content class="py-10 text-center text-sm text-muted-foreground">
					Nothing yet. Add your first thing above — a ₹300 bottle, ₹14,200 headphones, a subscription…
				</Card.Content>
			</Card.Root>
		{/each}
	</div>

	{#if retired.length}
		<details class="mt-1">
			<summary class="cursor-pointer text-sm font-medium text-muted-foreground select-none">
				Retired — {retired.length}
			</summary>
			<div class="mt-2 flex flex-col gap-2">
				{#each retired as m (m.asset.id)}
					<div class="flex items-center gap-3 rounded-lg border border-border px-3 py-2 text-sm opacity-70">
						<span class="truncate font-medium">{m.asset.name}</span>
						<span class="ml-auto text-xs text-muted-foreground">{verdict(m)}</span>
						<button class="icon-btn" title="Un-retire" onclick={() => unretire(m.asset.id)} aria-label="Un-retire">
							<Archive class="size-4" />
						</button>
						<button class="icon-btn hover:text-destructive" onclick={() => del(m.asset.id)} aria-label="Delete">
							<Trash2 class="size-4" />
						</button>
					</div>
				{/each}
			</div>
		</details>
	{/if}
</div>

<style>
	.item {
		border: 1px solid var(--border);
		border-left: 3px solid var(--row-accent);
		border-radius: var(--radius-lg);
		background: var(--card);
		padding: 12px 14px;
		transition: border-color var(--duration-fast) ease;
	}
	.icon-btn {
		display: grid;
		place-items: center;
		padding: 4px;
		border-radius: var(--radius-md);
		color: var(--muted-foreground);
		transition:
			color var(--duration-fast) ease,
			background-color var(--duration-fast) ease;
	}
	.icon-btn:hover {
		background: var(--secondary);
	}
</style>
