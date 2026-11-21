import type { AccountConfig } from '../config/types.ts';
import type { Logger } from './logger.ts';
import { MeosApiClient } from './meosClient.ts';
import { StateStore } from './stateStore.ts';
import { VaultService } from './vault.ts';

export interface AccountServices {
  account: AccountConfig;
  api: MeosApiClient;
  vault: VaultService;
  store: StateStore;
}

/**
 * One service graph per account, created once per process. Tool calls for
 * different configured accounts therefore cannot share a session cookie, a DEK,
 * or a cached state document.
 */
export function createAccountServices(account: AccountConfig, logger: Logger, fetchImpl?: typeof fetch): AccountServices {
  const api = new MeosApiClient(account, fetchImpl);
  const vault = new VaultService(api, account, () => api.getState(true));
  const store = new StateStore(api, vault);
  logger.debug('account_services_ready', { account: account.id });
  return { account, api, vault, store };
}

export class ServiceRegistry {
  private readonly services = new Map<string, AccountServices>();
  private readonly accounts: Map<string, AccountConfig>;
  private readonly logger: Logger;
  private readonly fetchImpl?: typeof fetch;

  constructor(accounts: Map<string, AccountConfig>, logger: Logger, fetchImpl?: typeof fetch) {
    this.accounts = accounts;
    this.logger = logger;
    this.fetchImpl = fetchImpl;
  }

  get(accountId: string): AccountServices {
    const existing = this.services.get(accountId);
    if (existing) return existing;
    const account = this.accounts.get(accountId);
    if (!account) throw new Error(`Unknown account "${accountId}"`);
    const created = createAccountServices(account, this.logger, this.fetchImpl);
    this.services.set(accountId, created);
    return created;
  }
}
