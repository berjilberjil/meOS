/** An error that is safe to show to an MCP client. */
export class MeosMcpError extends Error {
  readonly code: string;
  readonly status?: number;
  readonly hint?: string;

  constructor(code: string, message: string, options: { status?: number; hint?: string } = {}) {
    super(message);
    this.name = 'MeosMcpError';
    this.code = code;
    this.status = options.status;
    this.hint = options.hint;
  }
}

export function isMeosMcpError(e: unknown): e is MeosMcpError {
  return e instanceof MeosMcpError;
}

export const errors = {
  unauthenticated: (hint = 'Send a valid Authorization: Bearer <token> header.') =>
    new MeosMcpError('unauthenticated', `This MCP request is not authenticated. ${hint}`, { status: 401, hint }),

  forbidden: (needed: string, hint?: string) =>
    new MeosMcpError('forbidden', `This client does not have the required permission: ${needed}.`, {
      status: 403,
      hint: hint ?? 'Ask the MeOS owner to grant the scope to this client in the MCP server configuration.'
    }),

  rateLimited: (retryAfterSeconds: number) =>
    new MeosMcpError('rate_limited', 'Too many MCP requests. Try again shortly.', {
      status: 429,
      hint: `Retry after ${retryAfterSeconds}s.`
    }),

  confirmationRequired: (action: string) =>
    new MeosMcpError('confirmation_required', `${action} is irreversible and requires explicit confirmation.`, {
      hint: 'Call the tool again with "confirm": true after the user has approved the action.'
    }),

  vaultLocked: () =>
    new MeosMcpError(
      'vault_locked',
      'The MeOS vault is locked, so encrypted data cannot be read.',
      { hint: 'Set MEOS_VAULT_PASSPHRASE (or MEOS_VAULT_RECOVERY) on the MCP server, then retry.' }
    ),

  notFound: (what: string) => new MeosMcpError('not_found', `${what} was not found.`),

  conflict: (message: string) => new MeosMcpError('conflict', message),

  invalidInput: (message: string) => new MeosMcpError('invalid_input', message),

  upstream: (message: string, status?: number) =>
    new MeosMcpError('upstream_error', message, { status }),

  unsupported: (feature: string, reason: string) =>
    new MeosMcpError('unsupported', `${feature} is not available in this MeOS build.`, { hint: reason })
};
