import type { AccountConfig } from '../config/types.ts';
import { MeosMcpError, errors } from '../utils/errors.ts';
import { totp } from '../auth/totp.ts';

export interface MeosUser {
  id: number;
  username: string;
}

export interface MeosDevice {
  id: string;
  name: string;
  system_name: string;
  platform: string;
  kind: string;
  app_version: string;
  created_at: string;
  last_seen: string;
}

export interface MeosAiKey {
  id: number;
  provider: string;
  label: string;
  masked: string;
  enabled: boolean;
  models: string[];
}

export interface MeosBodyPhoto {
  id: string;
  date: string;
  url: string | null;
  updatedAt: string | null;
  bytes?: number;
  totalBytes?: number;
}

interface StateResponse {
  [key: string]: unknown;
}

/**
 * Thin, authenticated client for the existing MeOS backend.
 *
 * It signs in with the account's own credentials from server-side config and
 * carries the resulting `meos_session` cookie. No service-role credential, no
 * database connection string, and no SQL ever leaves this process. Every query
 * the backend runs is already scoped to the session's user.
 */
export class MeosApiClient {
  private cookie: string | null = null;
  private loginPromise: Promise<void> | null = null;
  private stateCache: { at: number; value: StateResponse } | null = null;
  private readonly account: AccountConfig;
  private readonly fetchImpl: typeof fetch;
  private readonly now: () => number;

  constructor(account: AccountConfig, fetchImpl: typeof fetch = fetch, now: () => number = Date.now) {
    this.account = account;
    this.fetchImpl = fetchImpl;
    this.now = now;
  }

  get baseUrl(): string {
    return this.account.baseUrl;
  }

  get username(): string {
    return this.account.username;
  }

  invalidateState(): void {
    this.stateCache = null;
  }

  private async signIn(): Promise<void> {
    const body: Record<string, string> = {
      username: this.account.username,
      password: this.account.password
    };
    if (this.account.mfaSecret) body.code = totp(this.account.mfaSecret);

    const res = await this.fetchImpl(`${this.account.baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(this.account.requestTimeoutMs)
    }).catch(() => {
      throw errors.upstream('Could not reach the MeOS backend.');
    });

    if (!res.ok) {
      if (res.status === 429) throw errors.rateLimited(60);
      if (res.status >= 500) throw errors.upstream('The MeOS backend is temporarily unavailable.');
      if (res.status === 401) {
        const text = (await res.text().catch(() => '')).slice(0, 2_000);
        let mfaRequired = false;
        try {
          const body = JSON.parse(text) as { mfaRequired?: unknown };
          mfaRequired = body.mfaRequired === true;
        } catch {
          /* not JSON; generic error below */
        }
        if (mfaRequired) {
          throw errors.unauthenticated(
            'MeOS MFA is enabled for this account. Set MEOS_MCP_MFA_SECRET to the same TOTP seed (or disable MFA for the gateway account).'
          );
        }
      }
      // Never distinguish "no such user" from "wrong password".
      throw errors.unauthenticated('The configured MeOS account could not sign in. Check MEOS_USERNAME / MEOS_PASSWORD.');
    }

    const setCookies =
      typeof res.headers.getSetCookie === 'function'
        ? res.headers.getSetCookie()
        : [res.headers.get('set-cookie') ?? ''].filter(Boolean);
    const session = setCookies
      .flatMap((c) => c.split(/,(?=\s*[A-Za-z0-9_-]+=)/))
      .map((c) => c.split(';')[0]!.trim())
      .find((c) => c.startsWith('meos_session='));
    if (!session) {
      throw errors.upstream('MeOS signed in but returned no session cookie.');
    }
    this.cookie = session;
    this.stateCache = null;
  }

  private async ensureSession(): Promise<void> {
    if (this.cookie) return;
    this.loginPromise ??= this.signIn().finally(() => {
      this.loginPromise = null;
    });
    await this.loginPromise;
  }

  private async raw(path: string, init: RequestInit = {}, allowRetry = true): Promise<Response> {
    await this.ensureSession();
    const headers = new Headers(init.headers);
    headers.set('Accept', 'application/json');
    headers.set('Cookie', this.cookie!);
    if (init.body != null) headers.set('Content-Type', 'application/json');

    let res: Response;
    try {
      res = await this.fetchImpl(`${this.account.baseUrl}${path}`, {
        ...init,
        headers,
        signal: AbortSignal.timeout(this.account.requestTimeoutMs)
      });
    } catch {
      throw errors.upstream('The MeOS backend did not respond in time.');
    }

    if (res.status === 401 && allowRetry) {
      this.cookie = null;
      await this.ensureSession();
      return this.raw(path, init, false);
    }
    if (res.status === 429) {
      throw errors.rateLimited(30);
    }
    if (!res.ok) {
      // Never echo an upstream body here: a 4xx message can contain a record's
      // title or another user's input, and MCP errors are shown to the model.
      throw new MeosMcpError(
        res.status >= 500 ? 'upstream_unavailable' : 'upstream_error',
        res.status >= 500
          ? 'The MeOS backend is temporarily unavailable.'
          : `The MeOS backend rejected the request (HTTP ${res.status}).`,
        { status: res.status }
      );
    }
    return res;
  }

  private async json<T>(path: string, init: RequestInit = {}): Promise<T> {
    const res = await this.raw(path, init);
    try {
      return (await res.json()) as T;
    } catch {
      throw errors.upstream('The MeOS backend returned an unreadable response.');
    }
  }

  /** Fresh state, cached for two seconds inside a single tool call. */
  async getState(force = false): Promise<StateResponse> {
    if (!force && this.stateCache && this.now() - this.stateCache.at < 2000) {
      return this.stateCache.value;
    }
    const value = await this.json<StateResponse>('/api/state');
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw errors.upstream('The MeOS state response had an unexpected shape.');
    }
    this.stateCache = { at: this.now(), value };
    return value;
  }

  async putState(key: string, value: unknown): Promise<void> {
    await this.raw(`/api/state/${encodeURIComponent(key)}`, {
      method: 'PUT',
      body: JSON.stringify(value)
    });
    this.invalidateState();
  }

  async getMe(): Promise<MeosUser> {
    return this.json<MeosUser>('/api/me');
  }

  async listDevices(): Promise<MeosDevice[]> {
    const out = await this.json<{ devices?: MeosDevice[] }>('/api/devices');
    return Array.isArray(out.devices) ? out.devices : [];
  }

  async listAiKeys(): Promise<MeosAiKey[]> {
    const out = await this.json<{ keys?: MeosAiKey[] }>('/api/ai/keys');
    return Array.isArray(out.keys) ? out.keys : [];
  }

  async getAiRoutes(): Promise<Record<string, unknown>> {
    const out = await this.json<Record<string, unknown>>('/api/ai/routes');
    return out && typeof out === 'object' ? out : {};
  }

  async listBodyPhotos(): Promise<MeosBodyPhoto[]> {
    const out = await this.json<MeosBodyPhoto[]>('/api/body-photos');
    return Array.isArray(out) ? out : [];
  }

  /** Release the sealed R2 object behind one event photo/video. */
  async deleteEventMedia(id: string): Promise<void> {
    await this.raw(`/api/event-media/${encodeURIComponent(id)}`, { method: 'DELETE' });
  }

  /** Release the sealed R2 object behind one progress photo. */
  async deleteBodyPhoto(id: string): Promise<void> {
    await this.raw(`/api/body-photos/${encodeURIComponent(id)}`, { method: 'DELETE' });
  }

  async ping(): Promise<boolean> {
    try {
      await this.getMe();
      return true;
    } catch {
      return false;
    }
  }
}
