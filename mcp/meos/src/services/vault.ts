import { isEnvelope, openValue, sealValue, unlockDek, unlockDekWithRecovery, type CryptoMeta } from '../../../diet/src/crypto.ts';
import type { AccountConfig } from '../config/types.ts';
import { errors, MeosMcpError } from '../utils/errors.ts';
import type { MeosApiClient } from './meosClient.ts';

const META_KEYS = ['meos.crypto', 'myos.crypto'];
const PLAINTEXT_KEYS = new Set(['meos.crypto', 'myos.crypto', 'meos.ai.routes', 'myos.ai.routes']);

export function isSealed(value: unknown): boolean {
  return isEnvelope(value);
}

/**
 * The zero-knowledge vault, unlocked server-side.
 *
 * The passphrase never crosses the MCP boundary — it is read from the server's
 * own environment, exactly as `mcp/diet` already does. The DEK lives only in this
 * process's memory. A client without the passphrase can still list module
 * presence but cannot read or write sealed data.
 */
export class VaultService {
  private meta: CryptoMeta | null = null;
  private dek: Buffer | null = null;
  private loaded = false;
  private metaLoad: Promise<CryptoMeta | null> | null = null;
  private readonly api: MeosApiClient;
  private readonly account: AccountConfig;
  private readonly rawState: () => Promise<Record<string, unknown>>;

  constructor(
    api: MeosApiClient,
    account: AccountConfig,
    rawState: () => Promise<Record<string, unknown>>
  ) {
    this.api = api;
    this.account = account;
    this.rawState = rawState;
  }

  get isConfigured(): boolean {
    return this.meta != null;
  }

  get isUnlocked(): boolean {
    return this.dek != null;
  }

  private async loadMeta(): Promise<CryptoMeta | null> {
    if (this.loaded) return this.meta;
    // A failed fetch must not be remembered as "this account has no vault":
    // treating sealed data as plaintext on the next write would corrupt it.
    this.metaLoad ??= (async () => {
      const raw = await this.rawState();
      for (const key of META_KEYS) {
        const value = raw[key];
        if (value && typeof value === 'object' && !Array.isArray(value) && !isEnvelope(value)) {
          const meta = value as Partial<CryptoMeta>;
          if (
            typeof meta.passSalt === 'string' &&
            typeof meta.wrappedByPass === 'string' &&
            typeof meta.iterations === 'number'
          ) {
            this.meta = meta as CryptoMeta;
            this.loaded = true;
            return this.meta;
          }
        }
      }
      this.meta = null;
      this.loaded = true;
      return null;
    })().finally(() => {
      this.metaLoad = null;
    });
    return this.metaLoad;
  }

  async unlock(): Promise<Buffer | null> {
    if (this.dek) return this.dek;
    const meta = await this.loadMeta();
    if (!meta) return null;

    const passphrase = this.account.vaultPassphrase;
    const recovery = this.account.vaultRecovery;
    if (!passphrase && !recovery) throw errors.vaultLocked();

    try {
      this.dek = passphrase ? await unlockDek(meta, passphrase) : await unlockDekWithRecovery(meta, recovery!);
      return this.dek;
    } catch {
      // The underlying error is intentionally generic; keep it that way so a
      // wrong passphrase is indistinguishable from a corrupt wrap.
      throw errors.vaultLocked();
    }
  }

  /** Read one logical key, transparently handling `myos.*` legacy values. */
  async read(raw: Record<string, unknown>, key: string): Promise<{ value: unknown; storedKey: string | null; sealed: boolean }> {
    const legacy = key.startsWith('meos.') ? `myos.${key.slice(5)}` : null;
    const candidates = legacy ? [key, legacy] : [key];
    for (const candidate of candidates) {
      if (!Object.prototype.hasOwnProperty.call(raw, candidate)) continue;
      const value = raw[candidate];
      if (!isEnvelope(value)) return { value: value ?? null, storedKey: candidate, sealed: false };
      const dek = await this.unlock();
      if (!dek) throw errors.vaultLocked();
      try {
        const plain = openValue(value, dek, candidate).toString('utf8');
        return { value: JSON.parse(plain), storedKey: candidate, sealed: true };
      } catch {
        throw new MeosMcpError('decrypt_failed', 'A MeOS record could not be decrypted with the configured vault key.', {
          hint: 'Check MEOS_VAULT_PASSPHRASE / MEOS_VAULT_RECOVERY. No data was changed.'
        });
      }
    }
    return { value: null, storedKey: null, sealed: false };
  }

  /** Write one logical key, sealing it when the account has a vault. */
  async write(key: string, value: unknown): Promise<void> {
    if (PLAINTEXT_KEYS.has(key)) {
      await this.api.putState(key, value);
      return;
    }
    const meta = await this.loadMeta();
    if (!meta) {
      await this.api.putState(key, value);
      return;
    }
    const dek = await this.unlock();
    if (!dek) throw errors.vaultLocked();
    const envelope = sealValue(Buffer.from(JSON.stringify(value), 'utf8'), dek, key);
    await this.api.putState(key, envelope);
  }

  /** Presence + seal state for `meos_get_module_status`, without decrypting. */
  async describe(raw: Record<string, unknown>, key: string): Promise<{ present: boolean; stored_key: string | null; sealed: boolean }> {
    const legacy = key.startsWith('meos.') ? `myos.${key.slice(5)}` : null;
    const candidates = legacy ? [key, legacy] : [key];
    for (const candidate of candidates) {
      if (!Object.prototype.hasOwnProperty.call(raw, candidate)) continue;
      return { present: true, stored_key: candidate, sealed: isEnvelope(raw[candidate]) };
    }
    return { present: false, stored_key: null, sealed: false };
  }
}
