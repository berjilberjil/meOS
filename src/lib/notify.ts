// Opt-in notifications for the daily journal/to-do nudge.
// Dual path: native Tauri notifications on the desktop app (WKWebView has no
// Web Notifications API), Web Notifications API in the browser/PWA.
const KEY = 'notify';
const PERM = 'notify-perm'; // cached Tauri permission state (granted/denied)

/** Running inside the Tauri (macOS desktop) shell. */
function isTauri(): boolean {
	return typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
}

export function notifySupported(): boolean {
	if (typeof window === 'undefined') return false;
	return isTauri() || typeof Notification !== 'undefined';
}

export function notifyEnabled(): boolean {
	if (!notifySupported()) return false;
	if (typeof localStorage === 'undefined' || localStorage.getItem(KEY) !== 'on') return false;
	if (isTauri()) return localStorage.getItem(PERM) === 'granted';
	return Notification.permission === 'granted';
}

export async function enableNotifications(): Promise<boolean> {
	if (!notifySupported()) return false;
	if (isTauri()) {
		const { isPermissionGranted, requestPermission } = await import(
			'@tauri-apps/plugin-notification'
		);
		let granted = await isPermissionGranted();
		if (!granted) granted = (await requestPermission()) === 'granted';
		localStorage.setItem(KEY, granted ? 'on' : 'off');
		localStorage.setItem(PERM, granted ? 'granted' : 'denied');
		return granted;
	}
	const ok = (await Notification.requestPermission()) === 'granted';
	localStorage.setItem(KEY, ok ? 'on' : 'off');
	return ok;
}

export function disableNotifications(): void {
	localStorage.setItem(KEY, 'off');
}

export async function notify(title: string, body: string): Promise<void> {
	if (!notifyEnabled()) return;
	if (isTauri()) {
		const { sendNotification } = await import('@tauri-apps/plugin-notification');
		sendNotification({ title, body });
		return;
	}
	try {
		new Notification(title, { body });
	} catch {
		/* ignore */
	}
}
