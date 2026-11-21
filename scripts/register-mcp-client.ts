#!/usr/bin/env bun
/**
 * Register an MCP OAuth client without dynamic client registration.
 *
 * Use this only when a client cannot call /oauth/register itself. The client
 * still has to go through /oauth/authorize and the owner's consent; this does
 * not grant any data scope.
 *
 *   bun scripts/register-mcp-client.ts \
 *     --name "My client" \
 *     --redirect "https://client.example/callback" \
 *     --scope "meos.profile.read offline_access"
 */
import { OAuthStore, isValidRedirectUri } from '../mcp/meos/src/oauth/store.ts';

function arg(name: string): string {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? (process.argv[i + 1] ?? '') : '';
}

const name = arg('name').trim() || 'MCP client';
const redirect = arg('redirect').trim();
const scope = arg('scope').trim() || 'meos.profile.read offline_access';

if (!redirect || !isValidRedirectUri(redirect)) {
  console.error('Provide --redirect with an exact https:// or loopback http:// URI (no fragment).');
  process.exit(1);
}

const store = new OAuthStore();
const client = store.registerClient({
  clientName: name,
  redirectUris: [redirect],
  scope,
  accountId: 'owner'
});

console.log(JSON.stringify({ client_id: client.clientId, redirect_uri: redirect, scope, store: store.path }, null, 2));
console.log('\nNext: start the gateway with the same MEOS_MCP_OAUTH_STORE, point the client at https://<public>/mcp, and approve it at /oauth/authorize.');
