<script lang="ts">
	import { onMount } from 'svelte';
	import { replaceState } from '$app/navigation';
	import { page } from '$app/state';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { toast } from 'svelte-sonner';
	import { profileState } from '$lib/stores/profile.svelte';
	import { setTheme, themeState, type Theme } from '$lib/stores/theme.svelte';
	import { enableNotifications, disableNotifications, notifyEnabled, notifySupported } from '$lib/notify';
	import { listTodos } from '$lib/planner/todos';
	import { goalsRepo } from '$lib/planner/goals';
	import { listActiveSorted } from '$lib/finance/recurring';
	import { loggedJournalDates, getStreakSettings, entryIdForDate } from '$lib/streak/data';
	import { computeStreak, localToday } from '$lib/streak/streak';
	import { recentFitness } from '$lib/health/logs';
	import { listSessions, listPlans, listPlanDays } from '$lib/gym/gym';
	import { listLogFor } from '$lib/nutrition/foods';
	import {
		greetingForHour,
		formatTodayHeading,
		pickDoNow,
		comingUp,
		productivity,
		whenLabel
	} from '$lib/today/today';
	import { categorizeEvent } from '$lib/ai/gemini';
	import { applyCategorizedEvent } from '$lib/ai/applyEvent';
	import { getGeminiKey, setGeminiKey, hasGeminiKey } from '$lib/ai/gemini';
	import Flame from '@lucide/svelte/icons/flame';
	import Mic from '@lucide/svelte/icons/mic';
	import ArrowUp from '@lucide/svelte/icons/arrow-up';
	import Settings2 from '@lucide/svelte/icons/settings-2';
	import Bell from '@lucide/svelte/icons/bell';
	import ChevronRight from '@lucide/svelte/icons/chevron-right';

	const qc = useQueryClient();
	const now = new Date();
	const today = localToday(now);
	const heading = formatTodayHeading(today);
	const greet = greetingForHour(now.getHours());
	const weekday = now.getDay();

	const todosQ = createQuery(() => ({ queryKey: ['todos'], queryFn: () => listTodos() }));
	const goalsQ = createQuery(() => ({ queryKey: ['goals'], queryFn: () => goalsRepo.list() }));
	const billsQ = createQuery(() => ({ queryKey: ['finance', 'recurring'], queryFn: () => listActiveSorted() }));
	const fitnessQ = createQuery(() => ({ queryKey: ['fitness'], queryFn: () => recentFitness() }));
	const sessionsQ = createQuery(() => ({ queryKey: ['sessions'], queryFn: () => listSessions() }));
	const plansQ = createQuery(() => ({ queryKey: ['plans'], queryFn: () => listPlans() }));
	const daysQ = createQuery(() => ({ queryKey: ['plan_days'], queryFn: () => listPlanDays() }));
	const foodQ = createQuery(() => ({ queryKey: ['food_log', today], queryFn: () => listLogFor(today) }));
	const streakQ = createQuery(() => ({
		queryKey: ['dashboard', 'streak'],
		queryFn: async () => {
			const [logged, settings] = await Promise.all([loggedJournalDates(today), getStreakSettings()]);
			return { logged, settings, id: await entryIdForDate(today) };
		}
	}));

	const todos = $derived(todosQ.data ?? []);
	const journalDone = $derived(streakQ.data?.logged.has(today) ?? false);
	const streakN = $derived(
		streakQ.data
			? computeStreak(streakQ.data.logged, today, streakQ.data.settings.freezes_total).current
			: 0
	);
	const journalHref = $derived(streakQ.data?.id ? `/journal/${streakQ.data.id}` : '/journal/new');

	const activePlan = $derived((plansQ.data ?? []).find((p) => p.active) ?? (plansQ.data ?? [])[0] ?? null);
	const todayDay = $derived(
		(daysQ.data ?? []).find((d) => d.plan_id === activePlan?.id && d.weekday === weekday) ?? null
	);
	const workoutDone = $derived(
		(fitnessQ.data ?? []).some((l) => l.logged_on === today) ||
			(sessionsQ.data ?? []).some((s) => s.logged_on === today)
	);

	const doNow = $derived(
		pickDoNow({
			today,
			journalDone,
			workoutPlanned: todayDay?.name ?? null,
			workoutDone,
			todos
		})
	);

	const upcoming = $derived(
		comingUp({
			today,
			horizonDays: 7,
			todos,
			bills: (billsQ.data ?? []).map((r) => ({ id: r.id, name: r.name, next_run_on: r.next_run_on })),
			workoutToday: todayDay && !workoutDone ? todayDay.name : null,
			goals: (goalsQ.data ?? []).map((g) => ({
				id: g.id,
				title: g.title,
				target_date: g.target_date,
				status: g.status
			}))
		})
	);

	const todayWork = $derived(
		todos.filter((t) => t.due_on === today || (!t.done && t.due_on && t.due_on < today))
	);
	const prod = $derived(
		productivity({
			journalDone,
			todosDone: todayWork.filter((t) => t.done).length,
			todosToday: todayWork.length,
			workoutDone,
			foodLogged: (foodQ.data ?? []).length > 0
		})
	);

	let capture = $state('');
	let capturing = $state(false);
	let listening = $state(false);
	let keyDraft = $state('');
	let notifOn = $state(false);
	let notifSupported = $state(true);

	const themes: { key: Theme; label: string }[] = [
		{ key: 'light', label: 'Light' },
		{ key: 'dark', label: 'Dark' },
		{ key: 'system', label: 'System' }
	];

	onMount(() => {
		notifSupported = notifySupported();
		notifOn = notifyEnabled();
		keyDraft = getGeminiKey();
		const params = page.url.searchParams;
		const spoken = params.get('capture') ?? params.get('event') ?? params.get('siri') ?? params.get('text');
		if (spoken) {
			capture = spoken;
			void submitCapture(spoken);
			// SvelteKit owns history; the native call warns and desyncs the router.
			replaceState(page.url.pathname, {});
		}
	});

	async function submitCapture(text = capture) {
		const spoken = text.trim();
		if (!spoken || capturing) return;
		capturing = true;
		try {
			const ev = await categorizeEvent(spoken, today);
			const result = await applyCategorizedEvent(ev);
			await qc.invalidateQueries();
			capture = '';
			toast.success(result.message);
		} catch (err) {
			toast.error(err instanceof Error ? err.message : 'Could not add that');
		}
		capturing = false;
	}

	type SpeechCtor = new () => {
		lang: string;
		interimResults: boolean;
		onresult: ((e: { results: ArrayLike<ArrayLike<{ transcript: string }>> }) => void) | null;
		onerror: (() => void) | null;
		onend: (() => void) | null;
		start: () => void;
	};

	function listen() {
		const w = window as unknown as { SpeechRecognition?: SpeechCtor; webkitSpeechRecognition?: SpeechCtor };
		const SR = w.SpeechRecognition ?? w.webkitSpeechRecognition;
		if (!SR) {
			toast.error('Voice isn’t available here — type it, or ask Siri to open this page with the event.');
			return;
		}
		const rec = new SR();
		rec.lang = 'en-IN';
		rec.interimResults = false;
		listening = true;
		rec.onresult = (e) => {
			const said = e.results[0]?.[0]?.transcript ?? '';
			capture = said;
			listening = false;
			if (said) void submitCapture(said);
		};
		rec.onerror = () => {
			listening = false;
			toast.error('Could not hear that');
		};
		rec.onend = () => {
			listening = false;
		};
		rec.start();
	}

	async function turnOnNotif() {
		notifOn = await enableNotifications();
		if (notifOn) toast.success('Reminders on');
		else toast.error('Permission denied');
	}
	function turnOffNotif() {
		disableNotifications();
		notifOn = false;
		toast.success('Reminders off');
	}

	function saveKey() {
		setGeminiKey(keyDraft);
		toast.success(hasGeminiKey() ? 'Gemini key saved on this device' : 'Gemini key cleared');
	}

	function pickTheme(t: Theme) {
		themeState.current = t;
		setTheme(t);
	}

	function cycleTheme() {
		const order: Theme[] = ['system', 'light', 'dark'];
		const next = order[(order.indexOf(themeState.current) + 1) % order.length];
		pickTheme(next);
	}
</script>

<div class="today kn-stagger">
	<header class="hello">
		<p class="greet">{greet}, {profileState.name}</p>
		<h1 class="dow">{heading.weekday}</h1>
		<p class="date">{heading.dateLabel}</p>
	</header>

	<form
		class="capture"
		onsubmit={(e) => {
			e.preventDefault();
			void submitCapture();
		}}
	>
		<input
			bind:value={capture}
			placeholder="Add anything — “dentist Friday” or “spent 400 on lunch”"
			aria-label="Add an event"
			disabled={capturing}
		/>
		<button type="button" class="icon" class:on={listening} onclick={listen} aria-label="Speak">
			<Mic class="size-4" />
		</button>
		<button type="submit" class="icon send" disabled={!capture.trim() || capturing} aria-label="Add">
			<ArrowUp class="size-4" />
		</button>
	</form>

	<a class="now" href={doNow.href}>
		<span class="kicker">Do now</span>
		<span class="now-title">{doNow.title}</span>
		<span class="now-why">{doNow.why}</span>
	</a>

	<section class="block">
		<h2>Coming up</h2>
		{#if upcoming.length}
			<ul>
				{#each upcoming as item (item.id)}
					<li>
						<a href={item.href}>
							<span class="dot" data-kind={item.kind}></span>
							<span class="item-title">{item.title}</span>
							<span class="when">{whenLabel(item.when, today)}</span>
						</a>
					</li>
				{/each}
			</ul>
		{:else}
			<p class="empty">Nothing in the next week. Clear runway.</p>
		{/if}
	</section>

	<section class="prod">
		<div class="prod-head">
			<div>
				<h2>Today</h2>
				<p>How the day is going</p>
			</div>
			<strong>{prod.score}</strong>
		</div>
		<div class="rings">
			{#each prod.rings as r (r.key)}
				<div class="ring">
					<div class="ring-meta">
						<span>{r.label}</span>
						<span>{r.detail}</span>
					</div>
					<div class="bar" aria-hidden="true">
						<span style="width:{Math.round(r.value * 100)}%"></span>
					</div>
				</div>
			{/each}
		</div>
	</section>

	<a class="streak" href={journalHref}>
		<Flame class="flame" />
		<div>
			<strong>{streakN} day{streakN === 1 ? '' : 's'}</strong>
			<span>{journalDone ? 'Written today — open it' : 'Tap to write today’s journal'}</span>
		</div>
		<ChevronRight class="chev" />
	</a>

	<section class="block settings">
		<h2 class="settings-head">
			<Settings2 class="size-4" />
			Settings
		</h2>
		<div class="settings-body">
			<div class="row">
				<span>Theme</span>
				<div class="pills">
					{#each themes as t (t.key)}
						<button
							type="button"
							class:on={themeState.current === t.key}
							onclick={() => pickTheme(t.key)}
						>
							{t.label}
						</button>
					{/each}
					<button type="button" class="text-btn" data-testid="theme-toggle" onclick={cycleTheme}>
						Theme: {themeState.current}
					</button>
				</div>
			</div>
				<div class="row">
					<span>Reminders</span>
					{#if !notifSupported}
						<span class="muted">Not supported here</span>
					{:else if notifOn}
						<button type="button" class="text-btn" onclick={turnOffNotif}>
							<Bell class="size-3.5" /> On — turn off
						</button>
					{:else}
						<button type="button" class="text-btn" onclick={turnOnNotif}>Enable</button>
					{/if}
				</div>
				<label class="row col">
					<span>Gemini key</span>
					<div class="keyline">
						<input type="password" bind:value={keyDraft} placeholder="AIza…" autocomplete="off" />
						<button type="button" onclick={saveKey}>Save</button>
					</div>
					<span class="muted">Used to categorize events and read scans. Stays on this device.</span>
				</label>
			<a class="profile-link" href="/profile">
				Full profile
				<ChevronRight class="size-4" />
			</a>
		</div>
	</section>
</div>

<style>
	.today {
		display: flex;
		flex-direction: column;
		gap: 1.15rem;
		max-width: 560px;
		padding-bottom: 1.5rem;
	}

	.hello {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		min-width: 0;
		padding-top: 0.25rem;
	}
	.greet {
		margin: 0;
		font-size: var(--text-sm);
		color: var(--muted-foreground);
	}
	.dow {
		margin: 0;
		font-size: clamp(2rem, 9vw, 2.75rem);
		font-weight: 650;
		letter-spacing: -0.045em;
		line-height: 1.05;
	}
	.date {
		margin: 0;
		font-size: var(--text-base);
		color: var(--muted-foreground);
	}

	.capture {
		display: flex;
		align-items: center;
		gap: 0.35rem;
		min-width: 0;
		border: 1px solid var(--border);
		border-radius: 9999px;
		background: var(--card);
		padding: 0.3rem 0.35rem 0.3rem 0.9rem;
	}
	.capture input {
		min-width: 0;
		flex: 1;
		border: 0;
		background: transparent;
		color: var(--foreground);
		font-size: var(--text-sm);
		outline: none;
	}
	.capture input::placeholder {
		color: var(--muted-foreground);
	}
	.icon {
		display: grid;
		height: 32px;
		width: 32px;
		flex-shrink: 0;
		place-items: center;
		border: 0;
		border-radius: 9999px;
		background: transparent;
		color: var(--muted-foreground);
	}
	.icon.on,
	.icon.send:not(:disabled) {
		background: var(--primary);
		color: var(--primary-foreground);
	}
	.icon:disabled {
		opacity: 0.35;
	}

	.now {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		min-width: 0;
		border-radius: 1.15rem;
		background: var(--foreground);
		color: var(--background);
		padding: 1rem 1.1rem 1.1rem;
		text-decoration: none;
	}
	.kicker {
		font-size: 10px;
		font-weight: 600;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		opacity: 0.55;
	}
	.now-title {
		font-size: 1.25rem;
		font-weight: 600;
		letter-spacing: -0.03em;
		line-height: 1.2;
		overflow-wrap: anywhere;
	}
	.now-why {
		font-size: var(--text-sm);
		opacity: 0.7;
	}

	.block h2,
	.prod-head h2 {
		margin: 0;
		font-size: var(--text-sm);
		font-weight: 600;
	}
	.block ul {
		margin: 0.55rem 0 0;
		padding: 0;
		list-style: none;
	}
	.block li + li {
		border-top: 1px solid var(--border);
	}
	.block a {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		min-width: 0;
		padding: 0.65rem 0;
		color: inherit;
		text-decoration: none;
	}
	.dot {
		height: 7px;
		width: 7px;
		flex-shrink: 0;
		border-radius: 9999px;
		background: var(--muted-foreground);
	}
	.dot[data-kind='workout'] {
		background: #34d399;
	}
	.dot[data-kind='bill'] {
		background: #fb7185;
	}
	.dot[data-kind='goal'] {
		background: #a78bfa;
	}
	.dot[data-kind='todo'] {
		background: var(--primary);
	}
	.item-title {
		min-width: 0;
		flex: 1;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: var(--text-sm);
	}
	.when {
		flex-shrink: 0;
		font-size: var(--text-xs);
		color: var(--muted-foreground);
	}
	.empty {
		margin: 0.5rem 0 0;
		font-size: var(--text-sm);
		color: var(--muted-foreground);
	}

	.prod {
		display: flex;
		flex-direction: column;
		gap: 0.85rem;
	}
	.prod-head {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: 1rem;
	}
	.prod-head p {
		margin: 0.15rem 0 0;
		font-size: var(--text-xs);
		color: var(--muted-foreground);
	}
	.prod-head strong {
		font-size: 2.4rem;
		font-weight: 650;
		letter-spacing: -0.05em;
		line-height: 0.9;
		font-variant-numeric: tabular-nums;
	}
	.rings {
		display: flex;
		flex-direction: column;
		gap: 0.55rem;
	}
	.ring-meta {
		display: flex;
		justify-content: space-between;
		font-size: var(--text-xs);
		color: var(--muted-foreground);
	}
	.bar {
		height: 5px;
		overflow: hidden;
		border-radius: 9999px;
		background: var(--secondary);
	}
	.bar span {
		display: block;
		height: 100%;
		border-radius: inherit;
		background: var(--foreground);
	}

	.streak {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		min-width: 0;
		border-radius: 1.15rem;
		border: 1px solid var(--border);
		background: var(--card);
		padding: 0.85rem 0.95rem;
		color: inherit;
		text-decoration: none;
	}
	.streak :global(.flame) {
		height: 22px;
		width: 22px;
		flex-shrink: 0;
		color: #ff8c1a;
	}
	.streak div {
		display: flex;
		min-width: 0;
		flex: 1;
		flex-direction: column;
	}
	.streak strong {
		font-size: var(--text-base);
	}
	.streak span {
		font-size: var(--text-xs);
		color: var(--muted-foreground);
	}
	.streak :global(.chev) {
		height: 16px;
		width: 16px;
		flex-shrink: 0;
		color: var(--muted-foreground);
	}

	.settings-head {
		display: flex;
		align-items: center;
		gap: 0.45rem;
	}
	.muted {
		font-size: var(--text-xs);
		font-weight: 400;
		color: var(--muted-foreground);
	}
	.settings-body {
		display: flex;
		flex-direction: column;
		gap: 0.9rem;
		padding-top: 0.85rem;
	}
	.row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
		font-size: var(--text-sm);
	}
	.row.col {
		flex-direction: column;
		align-items: stretch;
	}
	.pills {
		display: flex;
		flex-wrap: wrap;
		gap: 0.3rem;
	}
	.pills button {
		border: 1px solid var(--border);
		border-radius: 9999px;
		background: transparent;
		padding: 0.25rem 0.7rem;
		font-size: var(--text-xs);
		color: var(--muted-foreground);
	}
	.pills button.on {
		background: var(--foreground);
		border-color: var(--foreground);
		color: var(--background);
	}
	.text-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		border: 0;
		background: none;
		color: var(--primary);
		font-size: var(--text-sm);
	}
	.keyline {
		display: flex;
		gap: 0.4rem;
	}
	.keyline input {
		min-width: 0;
		flex: 1;
		height: 34px;
		border: 1px solid var(--border);
		border-radius: 0.6rem;
		background: var(--background);
		padding: 0 0.65rem;
		color: var(--foreground);
		font-size: var(--text-sm);
	}
	.keyline button {
		flex-shrink: 0;
		height: 34px;
		border: 0;
		border-radius: 0.6rem;
		background: var(--secondary);
		padding: 0 0.75rem;
		font-size: var(--text-sm);
	}
	.profile-link {
		display: flex;
		align-items: center;
		justify-content: space-between;
		border-top: 1px solid var(--border);
		padding-top: 0.75rem;
		color: inherit;
		font-size: var(--text-sm);
		text-decoration: none;
	}

	@media (min-width: 768px) {
		.today {
			max-width: 640px;
		}
	}
</style>
