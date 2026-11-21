#!/usr/bin/env bash
# Local security gate. Mirrors .github/workflows/security.yml and adds a fast
# repository-specific secret grep. Read-only: it never deploys, migrates or
# touches production data.
set -euo pipefail

cd "$(dirname "$0")/.."
fail=0

echo "== dependency audits =="
if command -v bun >/dev/null 2>&1; then
  # Production dependency trees only. Dev-server advisories (Vite/Vitest) do
  # not ship in the Worker or the MCP process; they are tracked separately.
  (cd apps/api && bun install --frozen-lockfile >/dev/null && bun audit --production) || fail=1
  (cd mcp/diet && bun install --frozen-lockfile >/dev/null && bun audit --production) || fail=1
  (cd mcp/stuff && bun install --frozen-lockfile >/dev/null && bun audit --production) || fail=1
fi
if command -v npm >/dev/null 2>&1; then
  (cd mcp/meos && npm ci >/dev/null 2>&1 && npm audit --omit=dev --audit-level=high) || fail=1
fi

echo "== secret grep (tracked source only) =="
# Deliberately narrow: real key shapes, not generic words. Test fixtures use
# obvious placeholders and are excluded where they would otherwise match.
if git grep -nE \
  'AIza[0-9A-Za-z_-]{35}|sk-(proj-)?[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' \
  -- ':!*.example' ':!*.test.ts' ':!**/tests/**' ':!**/*.lock' ':!**/node_modules/**' ':!**/.svelte-kit/**' ':!**/build/**'; then
  echo "Potential secret material found above." >&2
  fail=1
else
  echo "No hardcoded key patterns found."
fi

if command -v semgrep >/dev/null 2>&1; then
  echo "== semgrep =="
  semgrep scan --config p/owasp-top-ten --config p/secrets --severity ERROR --error \
    apps/api/src mcp/meos/src mcp/diet/src mcp/stuff/src || fail=1
else
  echo "semgrep not installed; skipping (CI runs it)."
fi

if command -v trivy >/dev/null 2>&1; then
  echo "== trivy (advisory; production audit is the blocking gate) =="
  trivy fs --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 . || true
else
  echo "trivy not installed; skipping (CI runs it)."
fi

if [ "$fail" -ne 0 ]; then
  echo "Security gate FAILED." >&2
  exit 1
fi
echo "Security gate passed."
