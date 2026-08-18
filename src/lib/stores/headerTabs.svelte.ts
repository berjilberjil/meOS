// Section sub-tabs that a route can publish into the global top bar (desktop).
export interface HeaderTab {
	href: string;
	label: string;
}

export const headerTabs = $state<{ tabs: HeaderTab[] }>({ tabs: [] });

// Ownership token. During client-side navigation the incoming section's layout
// mounts (setHeaderTabs) around the same time the outgoing layout unmounts
// (clearHeaderTabs); without ownership the outgoing onDestroy would wipe the
// tabs the incoming layout just set. Each set gets a fresh token; a clear only
// applies if it still owns the current tabs. (Identity comparison won't work —
// Svelte proxies the array — so we track a monotonic token instead.)
let owner = 0;

export function setHeaderTabs(tabs: HeaderTab[]): number {
	headerTabs.tabs = tabs;
	return ++owner;
}

export function clearHeaderTabs(token: number): void {
	if (token === owner) headerTabs.tabs = [];
}
