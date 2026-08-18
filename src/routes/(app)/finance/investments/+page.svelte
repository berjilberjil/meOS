<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { toPaise, formatINR } from '$lib/money';
	import { nextMonthlyOn, todayIso } from '$lib/finance/dates';
	import { investmentsRepo, setCurrentValue } from '$lib/finance/investments';
	import { recurringRepo } from '$lib/finance/recurring';
	import { accountsRepo } from '$lib/finance/accounts';
	import type { Investment, InvestmentType, Recurring } from '$lib/finance/types';

	const qc = useQueryClient();
	const investments = createQuery(() => ({ queryKey: ['finance', 'investments'], queryFn: () => investmentsRepo.list() }));
	const accounts = createQuery(() => ({ queryKey: ['finance', 'accounts'], queryFn: () => accountsRepo.list() }));

	let name = $state('');
	let type = $state<InvestmentType>('sip');
	let invested = $state('');
	let sipAmount = $state('');
	let sipDay = $state('1');
	let sipAccount = $state<string | null>(null);

	$effect(() => {
		if (!sipAccount && accounts.data?.length) sipAccount = accounts.data[0].id;
	});

	const add = createMutation(() => ({
		mutationFn: async () => {
			const inv = await investmentsRepo.create({
				name,
				type,
				invested_paise: toPaise(Number(invested) || 0),
				current_value_paise: toPaise(Number(invested) || 0),
				sip_amount_paise: type === 'sip' ? toPaise(Number(sipAmount) || 0) : null,
				sip_day: type === 'sip' ? Number(sipDay) : null
			} as Partial<Investment>);
			// Wire a monthly SIP recurring so catch-up auto-posts contributions.
			if (type === 'sip' && Number(sipAmount) > 0 && sipAccount) {
				await recurringRepo.create({
					kind: 'expense',
					name: `SIP: ${name}`,
					amount_paise: toPaise(Number(sipAmount)),
					account_id: sipAccount,
					category_id: null,
					cadence: 'monthly',
					interval_days: null,
					next_run_on: nextMonthlyOn(Number(sipDay), todayIso()),
					active: true,
					investment_id: inv.id
				} as Partial<Recurring>);
			}
			return inv;
		},
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['finance'] });
			name = '';
			invested = '';
			sipAmount = '';
		}
	}));

	const updateValue = createMutation(() => ({
		mutationFn: ({ id, rupees }: { id: string; rupees: number }) => setCurrentValue(id, toPaise(rupees)),
		onSuccess: () => qc.invalidateQueries({ queryKey: ['finance', 'investments'] })
	}));

	const gain = (i: Investment) => i.current_value_paise - i.invested_paise;
</script>

<div class="flex flex-col gap-4">
	<Card.Root>
		<Card.Header><Card.Title>Add investment</Card.Title></Card.Header>
		<Card.Content class="flex flex-wrap items-end gap-2">
			<Input placeholder="Name" bind:value={name} class="w-40" />
			<select bind:value={type} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				{#each ['sip', 'mutual_fund', 'stock', 'other'] as t}<option value={t}>{t}</option>{/each}
			</select>
			<Input type="number" placeholder="Invested ₹" bind:value={invested} class="w-32" />
			{#if type === 'sip'}
				<Input type="number" placeholder="SIP ₹/mo" bind:value={sipAmount} class="w-28" />
				<Input type="number" placeholder="Day (1-28)" bind:value={sipDay} class="w-24" />
				<select bind:value={sipAccount} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
					{#each accounts.data ?? [] as a (a.id)}<option value={a.id}>{a.name}</option>{/each}
				</select>
			{/if}
			<Button disabled={!name || add.isPending} onclick={() => add.mutate()}>Add</Button>
		</Card.Content>
	</Card.Root>

	<div class="kn-stagger grid gap-2 sm:grid-cols-2">
		{#each investments.data ?? [] as i (i.id)}
			<Card.Root>
				<Card.Header>
					<Card.Title class="text-base">{i.name} <span class="text-xs text-muted-foreground">({i.type})</span></Card.Title>
				</Card.Header>
				<Card.Content class="flex flex-col gap-1 text-sm">
					<span>Invested: {formatINR(i.invested_paise)}</span>
					<span>Current: {formatINR(i.current_value_paise)}
						<span class={gain(i) >= 0 ? 'text-emerald-500' : 'text-rose-500'}>({formatINR(gain(i))})</span>
					</span>
					<div class="flex gap-1">
						<Input type="number" placeholder="Update value ₹" class="h-7 w-32 text-xs"
							onchange={(e) => updateValue.mutate({ id: i.id, rupees: Number((e.currentTarget as HTMLInputElement).value) })} />
					</div>
				</Card.Content>
			</Card.Root>
		{/each}
	</div>
</div>
