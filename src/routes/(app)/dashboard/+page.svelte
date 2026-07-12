<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Input } from '$lib/components/ui/input';
	import { formatINR, sumPaise } from '$lib/money';
	import { todayIso, monthKey } from '$lib/finance/dates';
	import { accountsRepo, netWorth } from '$lib/finance/accounts';
	import { listByMonth as txnsByMonth } from '$lib/finance/transactions';
	import { categoriesRepo } from '$lib/finance/categories';
	import { listTodos, todoBucket, addTodo } from '$lib/planner/todos';
	import { goalsRepo } from '$lib/planner/goals';
	import { listNotes } from '$lib/notes/notes';
	import { recentHealth, recentFitness, totalDuration } from '$lib/health/logs';
	import { gToKg } from '$lib/health/units';
	import { listBelongings } from '$lib/belongings/belongings';
	import { loggedJournalDates, getStreakSettings } from '$lib/streak/data';
	import { computeStreak, localToday } from '$lib/streak/streak';
	import Donut from '$lib/dashboard/Donut.svelte';
	import WeightChart from '$lib/health/WeightChart.svelte';
	import Flame from '@lucide/svelte/icons/flame';
	import Wallet from '@lucide/svelte/icons/wallet';
	import TrendingDown from '@lucide/svelte/icons/trending-down';
	import TrendingUp from '@lucide/svelte/icons/trending-up';
	import ListChecks from '@lucide/svelte/icons/list-checks';
	import Target from '@lucide/svelte/icons/target';

	const today = localToday(new Date());
	const month = monthKey(todayIso());
	const PALETTE = ['#60a5fa', '#f59e0b', '#34d399', '#f472b6', '#a78bfa', '#fb7185', '#22d3ee', '#fbbf24'];

	const accountsQ = createQuery(() => ({ queryKey: ['accounts'], queryFn: () => accountsRepo.list() }));
	const txnsQ = createQuery(() => ({ queryKey: ['txns', month], queryFn: () => txnsByMonth(month) }));
	const catsQ = createQuery(() => ({ queryKey: ['categories'], queryFn: () => categoriesRepo.list() }));
	const todosQ = createQuery(() => ({ queryKey: ['todos'], queryFn: () => listTodos() }));
	const goalsQ = createQuery(() => ({ queryKey: ['goals'], queryFn: () => goalsRepo.list() }));
	const notesQ = createQuery(() => ({ queryKey: ['notes'], queryFn: () => listNotes() }));
	const healthQ = createQuery(() => ({ queryKey: ['health'], queryFn: () => recentHealth(120) }));
	const fitnessQ = createQuery(() => ({ queryKey: ['fitness'], queryFn: () => recentFitness(60) }));
	const belongingsQ = createQuery(() => ({ queryKey: ['belongings'], queryFn: () => listBelongings() }));
	const streakQ = createQuery(() => ({
		queryKey: ['dashboard', 'streak'],
		queryFn: async () => {
			const [logged, settings] = await Promise.all([loggedJournalDates(today), getStreakSettings()]);
			return computeStreak(logged, today, settings.freezes_total).current;
		}
	}));

	const qc = useQueryClient();
	let newTodo = $state('');
	const addTodoM = createMutation(() => ({
		mutationFn: (title: string) => addTodo(title, null, 0),
		onSuccess: () => qc.invalidateQueries({ queryKey: ['todos'] })
	}));
	function quickAddTodo() {
		const t = newTodo.trim();
		if (!t) return;
		newTodo = '';
		addTodoM.mutate(t);
	}

	const accounts = $derived(accountsQ.data ?? []);
	const txns = $derived(txnsQ.data ?? []);
	const cats = $derived(catsQ.data ?? []);
	const todos = $derived(todosQ.data ?? []);
	const goals = $derived(goalsQ.data ?? []);

	const worth = $derived(netWorth(accounts));
	const expenses = $derived(txns.filter((t) => t.type === 'expense'));
	const income = $derived(txns.filter((t) => t.type === 'income'));
	const spent = $derived(sumPaise(expenses.map((t) => t.amount_paise)));
	const earned = $derived(sumPaise(income.map((t) => t.amount_paise)));

	const catName = $derived(new Map(cats.map((c) => [c.id, c.name])));
	const catColor = $derived(new Map(cats.map((c) => [c.id, c.color])));
	const spendByCat = $derived.by(() => {
		const m = new Map<string, number>();
		for (const t of expenses) {
			const key = t.category_id ?? '_';
			m.set(key, (m.get(key) ?? 0) + t.amount_paise);
		}
		return [...m.entries()]
			.map(([id, value], i) => ({
				label: id === '_' ? 'Uncategorized' : (catName.get(id) ?? 'Uncategorized'),
				value,
				color: (id !== '_' && catColor.get(id)) || PALETTE[i % PALETTE.length]
			}))
			.sort((a, b) => b.value - a.value);
	});

	const todosActive = $derived(todos.filter((t) => !t.done));
	const todosDue = $derived(
		todos.filter((t) => {
			const b = todoBucket(t.due_on, t.done, today);
			return b === 'overdue' || b === 'today';
		})
	);
	const upcoming = $derived(
		[...todosActive]
			.filter((t) => t.due_on)
			.sort((a, b) => (a.due_on ?? '').localeCompare(b.due_on ?? ''))
			.slice(0, 6)
	);
	const goalsActive = $derived(goals.filter((g) => g.status === 'active').length);

	const recentTxns = $derived(
		[...txns].sort((a, b) => b.occurred_on.localeCompare(a.occurred_on)).slice(0, 7)
	);

	const weightPoints = $derived(
		(healthQ.data ?? [])
			.filter((l) => l.weight_g != null)
			.map((l) => ({ iso: l.logged_on, kg: gToKg(l.weight_g!) }))
			.reverse()
	);
	const weekMin = $derived(totalDuration(fitnessQ.data ?? [], todayIso(), 7));
	const belongingsSpent = $derived(
		sumPaise((belongingsQ.data ?? []).filter((b) => b.kind === 'purchase').map((b) => b.cost_paise ?? 0))
	);
	const wardrobeCount = $derived(
		(belongingsQ.data ?? []).filter((b) => b.kind === 'clothing').reduce((s, b) => s + b.qty, 0)
	);
	const notesCount = $derived((notesQ.data ?? []).length);

	const monthName = new Date().toLocaleDateString('en-US', { month: 'long' });

	const stats = $derived([
		{ label: 'Net worth', value: formatINR(worth), sub: `${accounts.length} accounts`, icon: Wallet, tone: 'var(--foreground)', href: undefined as string | undefined },
		{ label: `Spent · ${monthName}`, value: formatINR(spent), sub: `${expenses.length} expenses`, icon: TrendingDown, tone: '#fb7185', href: undefined as string | undefined },
		{ label: `Income · ${monthName}`, value: formatINR(earned), sub: `${income.length} credits`, icon: TrendingUp, tone: '#34d399', href: undefined as string | undefined },
		{ label: 'Journal streak', value: `${streakQ.data ?? 0}`, sub: 'days in a row', icon: Flame, tone: '#ff8c1a', href: undefined as string | undefined },
		{ label: 'To-dos due', value: `${todosDue.length}`, sub: `${todosActive.length} active`, icon: ListChecks, tone: '#60a5fa', href: '/todos' },
		{ label: 'Goals active', value: `${goalsActive}`, sub: `${goals.length} total`, icon: Target, tone: '#a78bfa', href: '/goals' }
	]);
</script>

<div class="kn-stagger flex flex-col gap-4">
	<div>
		<h1 class="text-xl font-semibold tracking-tight">Dashboard</h1>
		<p class="text-sm text-muted-foreground">Your real numbers, {today}.</p>
	</div>

	<!-- Stat cards -->
	<div class="grid grid-cols-2 gap-3 lg:grid-cols-3 xl:grid-cols-6">
		{#each stats as s (s.label)}
			<svelte:element this={s.href ? 'a' : 'div'} href={s.href} class="block">
				<Card.Root class={s.href ? 'h-full transition-colors hover:border-primary/50' : 'h-full'}>
					<Card.Content class="flex flex-col gap-1 pt-5">
						<div class="flex items-center gap-1.5 text-xs text-muted-foreground">
							<s.icon class="size-3.5" style="color:{s.tone}" />
							{s.label}
						</div>
						<div class="text-2xl font-bold tracking-tight">{s.value}</div>
						<div class="text-xs text-muted-foreground">{s.sub}</div>
					</Card.Content>
				</Card.Root>
			</svelte:element>
		{/each}
	</div>

	<!-- Charts -->
	<div class="grid gap-3 lg:grid-cols-2">
		<Card.Root>
			<Card.Header>
				<Card.Title class="text-base">Spending · {monthName}</Card.Title>
				<Card.Description>Where the money went</Card.Description>
			</Card.Header>
			<Card.Content>
				{#if spendByCat.length}
					<div class="flex flex-col items-center gap-4 sm:flex-row">
						<Donut segments={spendByCat} centerTop={formatINR(spent)} centerBottom="spent" />
						<div class="flex flex-1 flex-col gap-1.5">
							{#each spendByCat.slice(0, 6) as s (s.label)}
								<div class="flex items-center gap-2 text-sm">
									<span class="size-3 rounded-sm" style="background:{s.color}"></span>
									<span class="truncate">{s.label}</span>
									<span class="ml-auto font-medium">{formatINR(s.value)}</span>
								</div>
							{/each}
						</div>
					</div>
				{:else}
					<p class="py-10 text-center text-sm text-muted-foreground">No spending logged this month.</p>
				{/if}
			</Card.Content>
		</Card.Root>

		<Card.Root>
			<Card.Header>
				<Card.Title class="text-base">Weight trend</Card.Title>
				<Card.Description>
					{weightPoints.length ? `${weightPoints.at(-1)?.kg} kg latest` : 'Log weight in Fitness'}
				</Card.Description>
			</Card.Header>
			<Card.Content>
				<WeightChart points={weightPoints} />
			</Card.Content>
		</Card.Root>
	</div>

	<!-- Lists -->
	<div class="grid gap-3 lg:grid-cols-2">
		<Card.Root>
			<Card.Header class="flex flex-row items-center justify-between">
				<Card.Title class="text-base">Upcoming to-dos</Card.Title>
				<a href="/todos" class="text-xs text-muted-foreground hover:text-foreground">See all →</a>
			</Card.Header>
			<Card.Content class="divide-y divide-border">
				{#each upcoming as t (t.id)}
					{@const b = todoBucket(t.due_on, t.done, today)}
					<div class="flex min-w-0 items-center gap-3 py-2 text-sm">
						<span class="truncate font-medium">{t.title}</span>
						<span class="ml-auto shrink-0 rounded-full px-2 py-0.5 text-xs" class:overdue={b === 'overdue'} style={b === 'overdue' ? '' : 'background:var(--secondary)'}>
							{t.due_on}
						</span>
					</div>
				{:else}
					<p class="py-6 text-center text-sm text-muted-foreground">Nothing scheduled. Clear runway.</p>
				{/each}
				<div class="flex gap-2 pt-3">
					<Input
						bind:value={newTodo}
						placeholder="Quick add a to-do…"
						class="h-8 text-sm"
						onkeydown={(e) => e.key === 'Enter' && quickAddTodo()}
					/>
				</div>
			</Card.Content>
		</Card.Root>

		<Card.Root>
			<Card.Header><Card.Title class="text-base">Recent transactions</Card.Title></Card.Header>
			<Card.Content class="divide-y divide-border">
				{#each recentTxns as t (t.id)}
					<div class="flex items-center gap-3 py-2 text-sm">
						<span class="truncate">{t.note || (t.category_id ? catName.get(t.category_id) : '') || 'Transaction'}</span>
						<span class="text-xs text-muted-foreground">{t.occurred_on.slice(5)}</span>
						<span class="ml-auto font-semibold" style="color:{t.type === 'income' ? '#34d399' : t.type === 'expense' ? '#fb7185' : 'var(--foreground)'}">
							{t.type === 'income' ? '+' : t.type === 'expense' ? '−' : ''}{formatINR(t.amount_paise)}
						</span>
					</div>
				{:else}
					<p class="py-6 text-center text-sm text-muted-foreground">No transactions this month.</p>
				{/each}
			</Card.Content>
		</Card.Root>
	</div>

	<!-- Mini strip -->
	<div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
		<Card.Root><Card.Content class="flex flex-col gap-0.5 pt-5">
			<div class="text-xs text-muted-foreground">Active this week</div>
			<div class="text-xl font-bold">{weekMin} min</div>
		</Card.Content></Card.Root>
		<Card.Root><Card.Content class="flex flex-col gap-0.5 pt-5">
			<div class="text-xs text-muted-foreground">Spent on belongings</div>
			<div class="text-xl font-bold">{formatINR(belongingsSpent)}</div>
		</Card.Content></Card.Root>
		<Card.Root><Card.Content class="flex flex-col gap-0.5 pt-5">
			<div class="text-xs text-muted-foreground">Wardrobe items</div>
			<div class="text-xl font-bold">{wardrobeCount}</div>
		</Card.Content></Card.Root>
		<Card.Root><Card.Content class="flex flex-col gap-0.5 pt-5">
			<div class="text-xs text-muted-foreground">Notes</div>
			<div class="text-xl font-bold">{notesCount}</div>
		</Card.Content></Card.Root>
	</div>
</div>

<style>
	.overdue {
		background: color-mix(in oklch, #fb7185 22%, transparent);
		color: #fb7185;
	}
</style>
