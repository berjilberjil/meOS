import '@testing-library/jest-dom/vitest';
import 'fake-indexeddb/auto';

// Node 25 ships an experimental global `localStorage` that shadows jsdom's and
// lacks a working Storage API. Install a deterministic in-memory Storage so
// theme/persistence tests run consistently.
class MemoryStorage implements Storage {
	#data = new Map<string, string>();
	get length() {
		return this.#data.size;
	}
	clear(): void {
		this.#data.clear();
	}
	getItem(key: string): string | null {
		return this.#data.has(key) ? this.#data.get(key)! : null;
	}
	key(index: number): string | null {
		return [...this.#data.keys()][index] ?? null;
	}
	removeItem(key: string): void {
		this.#data.delete(key);
	}
	setItem(key: string, value: string): void {
		this.#data.set(key, String(value));
	}
}

const storage = new MemoryStorage();
Object.defineProperty(globalThis, 'localStorage', { value: storage, configurable: true });
if (typeof window !== 'undefined') {
	Object.defineProperty(window, 'localStorage', { value: storage, configurable: true });
}
