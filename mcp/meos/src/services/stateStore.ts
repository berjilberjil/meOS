import type { MeosApiClient } from './meosClient.ts';
import { VaultService } from './vault.ts';

/**
 * Per-key read-modify-write serialisation inside this process.
 *
 * It cannot coordinate with the Mac or iPhone — MeOS sync is last-write-wins by
 * design — but it prevents two concurrent MCP calls from reading the same note
 * list and each writing back a version that has lost the other's change.
 */
export class StateStore {
  private locks = new Map<string, Promise<unknown>>();
  private readonly api: MeosApiClient;
  private readonly vault: VaultService;

  constructor(api: MeosApiClient, vault: VaultService) {
    this.api = api;
    this.vault = vault;
  }

  raw(force = false): Promise<Record<string, unknown>> {
    return this.api.getState(force);
  }

  async read<T>(key: string, force = false): Promise<T | null> {
    const raw = await this.raw(force);
    const { value } = await this.vault.read(raw, key);
    return (value ?? null) as T | null;
  }

  async readWithMeta<T>(key: string): Promise<{ value: T | null; sealed: boolean; storedKey: string | null }> {
    const raw = await this.raw();
    const read = await this.vault.read(raw, key);
    return { value: (read.value ?? null) as T | null, sealed: read.sealed, storedKey: read.storedKey };
  }

  async write(key: string, value: unknown): Promise<void> {
    await this.vault.write(key, value);
  }

  async describe(key: string): Promise<{ present: boolean; stored_key: string | null; sealed: boolean }> {
    const raw = await this.raw();
    return this.vault.describe(raw, key);
  }

  /** Atomic read → transform → write for one key. */
  async update<T>(key: string, transform: (current: T | null) => T | Promise<T>): Promise<T> {
    const previous = this.locks.get(key) ?? Promise.resolve();
    let release!: () => void;
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    const chained = previous.then(() => gate);
    this.locks.set(key, chained);
    await previous;
    try {
      // Writes always start from a fresh snapshot. A two-second read cache is
      // fine for analysis but would let a concurrent change be overwritten.
      const current = await this.read<T>(key, true);
      const next = await transform(current);
      await this.write(key, next);
      return next;
    } finally {
      release();
      if (this.locks.get(key) === chained) this.locks.delete(key);
    }
  }
}
