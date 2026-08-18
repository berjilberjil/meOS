// Local profile (avatar + display name). Kept in localStorage so it is available
// even before sign-in (the login screen greets you), and "reset" falls back to
// the bundled default avatar. Per-device for now; cloud sync can layer on later.

const AVATAR_KEY = 'myos:avatar';
const NAME_KEY = 'myos:name';

export const DEFAULT_AVATAR = '/me.webp';
export const DEFAULT_NAME = 'Berjil';

function read(key: string, fallback: string): string {
	if (typeof localStorage === 'undefined') return fallback;
	return localStorage.getItem(key) || fallback;
}

export const profileState = $state<{ avatar: string; name: string }>({
	avatar: DEFAULT_AVATAR,
	name: DEFAULT_NAME
});

export function initProfile(): void {
	profileState.avatar = read(AVATAR_KEY, DEFAULT_AVATAR);
	profileState.name = read(NAME_KEY, DEFAULT_NAME);
}

export function setAvatar(dataUrl: string): void {
	profileState.avatar = dataUrl;
	try {
		localStorage.setItem(AVATAR_KEY, dataUrl);
	} catch {
		// storage full or unavailable — keep the in-memory value
	}
}

export function resetAvatar(): void {
	profileState.avatar = DEFAULT_AVATAR;
	try {
		localStorage.removeItem(AVATAR_KEY);
	} catch {
		/* ignore */
	}
}

export function setName(name: string): void {
	profileState.name = name.trim() || DEFAULT_NAME;
	try {
		localStorage.setItem(NAME_KEY, profileState.name);
	} catch {
		/* ignore */
	}
}

// Downscale + square-crop an uploaded image to a small data URL for storage.
export function fileToAvatar(file: File, size = 256): Promise<string> {
	return new Promise((resolve, reject) => {
		const url = URL.createObjectURL(file);
		const img = new Image();
		img.onload = () => {
			URL.revokeObjectURL(url);
			const canvas = document.createElement('canvas');
			canvas.width = size;
			canvas.height = size;
			const ctx = canvas.getContext('2d');
			if (!ctx) return reject(new Error('Canvas unavailable'));
			const side = Math.min(img.width, img.height);
			const sx = (img.width - side) / 2;
			const sy = (img.height - side) / 2;
			ctx.drawImage(img, sx, sy, side, side, 0, 0, size, size);
			resolve(canvas.toDataURL('image/jpeg', 0.9));
		};
		img.onerror = () => {
			URL.revokeObjectURL(url);
			reject(new Error('Could not read image'));
		};
		img.src = url;
	});
}
