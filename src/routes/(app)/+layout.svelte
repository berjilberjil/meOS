<script lang="ts">
	import AppTopBar from '$lib/components/layout/MobileTopBar.svelte';
	import BottomNav from '$lib/components/layout/MobileNav.svelte';
	import Lightbox from '$lib/components/Lightbox.svelte';
	import QuickAdd from '$lib/components/finance/QuickAdd.svelte';
	import { onMount } from 'svelte';
	import { useQueryClient } from '@tanstack/svelte-query';
	import { initFinanceSync } from '$lib/finance/sync';
	import { notify, notifyEnabled } from '$lib/notify';
	import { loggedJournalDates } from '$lib/streak/data';
	import { localToday } from '$lib/streak/streak';
	import { listTodos } from '$lib/planner/todos';
	import { ensureProfile } from '$lib/profile/personal';

	let { children } = $props();

	const qc = useQueryClient();
	onMount(() => {
		// Multi-user: ensure this account has a profile row on first login.
		ensureProfile().catch(() => {});
		const stop = initFinanceSync(() => qc.invalidateQueries({ queryKey: ['finance'] }));
		// One combined daily reminder (journal streak + to-dos due), at most once a day.
		if (notifyEnabled()) {
			const today = localToday(new Date());
			if (localStorage.getItem('notify-last') !== today) {
				Promise.all([loggedJournalDates(today), listTodos()])
					.then(([logged, todos]) => {
						const parts: string[] = [];
						if (!logged.has(today)) parts.push("write today's journal");
						const due = todos.filter((t) => !t.done && t.due_on && t.due_on <= today).length;
						if (due) parts.push(`${due} to-do${due > 1 ? 's' : ''} due`);
						if (parts.length) {
							setTimeout(() => {
								notify('MyOS reminder', `Don't forget: ${parts.join(' · ')} 🔥`);
								localStorage.setItem('notify-last', today);
							}, 4000);
						}
					})
					.catch(() => {});
			}
		}
		return stop;
	});
</script>

<div class="flex h-dvh flex-col">
	<AppTopBar />
	<div
		class="kn-enter min-h-0 flex-1 overflow-y-auto overflow-x-hidden p-4 pb-[calc(5.25rem+env(safe-area-inset-bottom))] md:px-6 md:pb-6"
		style="scrollbar-gutter: stable;"
	>
		<div class="mx-auto w-full max-w-[1500px]">
			{@render children()}
		</div>
	</div>
</div>

<BottomNav />
<QuickAdd />
<Lightbox />
