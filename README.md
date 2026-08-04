# MyOS — your personal operating system

Your second brain. One app for **money, body, and mind** — and later, everything.

**One product, one backend, native clients on top.** The SvelteKit app in
`apps/web` is a *headless* backend (auth + a per-user `key → JSON` store + one AI
route). The native macOS app in `apps/mac` is the only front-end you touch; it
reads and writes the same JSON keys, so a future iPhone/iPad client stays in sync
for free.

> This is **not** fitOS. fitOS is the commercial gym product. MyOS is personal —
> it reuses fitOS's *architecture* (and some fitness code), nothing else.

```
apps/
  web/    Headless SvelteKit /api — auth, key→JSON state store, AI parse. Netlify + Supabase.
  mac/    Native macOS SwiftUI app. The only UI. Talks to apps/web's /api/*.
```

## The one idea (same as fitOS)

There is **no per-feature backend.** The server is:

1. **Auth** — username/password → an httpOnly cookie session.
2. **A per-user key→JSON store** — `GET /api/state`, `PUT /api/state/{key}`.
3. **One AI helper** — `POST /api/parse` (one line of life → structured entries).

All app data is JSON documents under string keys:

| Key             | Holds                                                             |
|-----------------|------------------------------------------------------------------|
| `myos.profile`  | name, currency, targets, insurance checklist                     |
| `myos.finance`  | `{ txns: [...], meta: {...} }` — cashflow, gold-loan, emergency fund |
| `myos.fitness`  | per-date weight / calories / protein / water                     |
| `myos.journal`  | per-date morning/night, wins/mistakes/lessons, gratitude, mood   |
| `myos.notes`    | quick-capture notes                                              |
| `myos.days`     | per-date focus priorities + habit ticks (the Today spine)        |

**Add a module = add a key + a view.** The server doesn't change.

## v1 scope

Daily spine (Today) + **Finance**, **Fitness**, **Journal**, **Notes** + AI quick-log.
Everything else in the PRD (Content Hub, Knowledge Vault, Goals, Tasks, Reading,
Documents, Analytics, the AI analyst) is Phase 2.

## Run it

```bash
# backend
cd apps/web && npm install && npm run dev      # http://localhost:5173

# mac app (needs xcodegen: brew install xcodegen)
cd apps/mac && xcodegen generate && open MyOS.xcodeproj
```

Point the mac app at your backend by editing `APIClient.baseURL` in
`apps/mac/Sources/MyOS/Support/APIClient.swift`.

## Secrets

Never commit secrets. `apps/web/.env` (gitignored) holds `DATABASE_URL` and
`GEMINI_API_KEY`. In production these are Netlify env vars.
