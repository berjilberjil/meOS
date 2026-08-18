# MyOS — Design Spec (Foundation + Finance)

**Date:** 2026-06-26
**Status:** Approved for Phase 0 + Phase 1
**Owner:** Berjil

---

## 1. Purpose

MyOS is a private, daily-driver personal life operating system — one tool for finance, health, fitness, to-dos, goals, notes, and journaling, with a mindmap dashboard that visualizes how everything in life connects.

It is a **brand-new, standalone project** at `/Users/berjilskcript/Documents/myos`, with its own git repository. The existing monorepo at `/Users/berjilskcript/Documents/monorepo` ("Knol") is used as a **read-only reference** for theme, color, animation, and the content-studio interaction flow. The monorepo is never modified.

### Primary goals
- **Finance from rupee #1** — track every rupee of income/expense from day 1 of the salary month. No transaction missed.
- **Daily journaling** with images and video, growing storage-heavy over years.
- **Strong privacy** — only the owner can ever access the data; nothing leaks or is publicly exposed.
- **Mindmap life-dashboard** — a visual graph of how money, goals, health, and journal connect.
- Built like a durable system, not a throwaway project: modular, scalable, testable.

---

## 2. Scope

This spec covers **Phase 0 (Foundation)** and **Phase 1 (Finance module — MVP)**.

Later modules (Journal, To-do + Goals, Health + Fitness, Notes, Mindmap dashboard) are **designed-for** in the data model and architecture but each gets its **own brainstorm → spec → build cycle**. This keeps every phase small, shippable, and clean.

---

## 3. Decisions (locked)

| Decision | Choice | Reason |
|---|---|---|
| Platform | Responsive web (phone + laptop equally) | Used both on the go and at a desk |
| Stack | SvelteKit 2 + Svelte 5 (runes) + Tailwind v4 + shadcn-svelte ("luma") + TipTap + HugeIcons | Matches monorepo exactly → identical theme/animation/color |
| Backend | Supabase (Postgres + Auth + Storage + Realtime) | Relational DB for exact money + entity relationships; bundled auth/storage/sync; open-source + self-hostable later (no lock-in) |
| Privacy | Locked cloud: single account, RLS, private buckets, encryption at rest, 2FA | Strong + standard; keeps finance/mindmap fully queryable. No client-side E2E for now |
| Offline | Installable PWA, offline-capable with background sync | Log expenses + journal with no signal; daily driver |
| Money input | Manual entry (UPI-SMS helper + bank sync deferred) | Fast, fully private, owner sees every rupee |
| Currency | INR, stored as integer paise | Zero floating-point rounding — guarantees no rupee lost |

---

## 4. Architecture

```
Frontend (responsive web + installable PWA)
  SvelteKit 2 · Svelte 5 runes · Tailwind v4
  shadcn-svelte "luma" · TipTap · HugeIcons
  Design tokens lifted from monorepo (light / dark / Tokyo Night "tui")
  Offline cache (IndexedDB) + background sync
        │  HTTPS, signed sessions
Supabase (hardened)
  Postgres · Auth + 2FA (single user) · Storage (private buckets) · Realtime
```

- **Offline-first:** a local store (IndexedDB) mirrors the user's data so the app works with no connection; mutations queue and sync to Supabase when back online.
- **Hosting:** frontend on Vercel (free tier); backend on Supabase cloud. Both self-hostable later with no rewrite.
- **Design system source of truth:** port `monorepo/webapp/src/routes/layout.css` tokens (OKLCH palette, 3 themes, motion tokens `--duration-fast/normal/slow`, `--ease-entrance`, `kn-` entrance/stagger classes, radius `10px`, 13px UI type) into MyOS.

---

## 5. Data model

**Money is stored as integer paise (BIGINT), never floats.** All arithmetic in paise; format to INR only at display. This is the mechanism that guarantees "not 1 rupee missed."

### Foundation
- `profile` — the single owner (display name, preferences, theme).
- `links` — generic graph edge connecting any entity to any entity: `(source_type, source_id, relation, target_type, target_id)`. This is the mindmap backbone; it exists from day 1 so connections accumulate even before the mindmap UI is built.
- `media_assets` — `(id, owner_type, owner_id, storage_path, mime, size_bytes, width, height, duration_ms, thumbnail_path, created_at)`.

### Finance (Phase 1)
- `accounts` — `(id, name, type[bank|cash|upi|credit_card|wallet], balance_paise, currency='INR', archived, created_at)`.
- `categories` — `(id, name, kind[expense|income], icon, color, monthly_budget_paise, created_at)`.
- `transactions` — `(id, account_id, category_id, type[income|expense|transfer], amount_paise, transfer_account_id, note, occurred_on, recurring_id, created_at)`. Attachments via `media_assets`.
- `recurring` — `(id, kind[income|expense|subscription], name, amount_paise, account_id, category_id, cadence[monthly|weekly|custom], next_run_on, active)`. Covers salary, rent, subscriptions.
- `subscriptions` — modeled as `recurring.kind='subscription'` plus optional fields `(vendor, plan, renews_on)`.
- `savings_goals` — `(id, name, target_paise, saved_paise, deadline, account_id, created_at)`.
- `investments` — `(id, name, type[sip|mutual_fund|stock|other], invested_paise, current_value_paise, sip_amount_paise, sip_day, created_at)`.

### Designed-for (later phases, not built now)
`journal_entries`, `notes`, `todos`, `goals`, `health_logs`, `fitness_logs`. Schema and naming leave clean room so no rework is needed when added.

---

## 6. Security

The owner's hard requirement: nobody but the owner can ever access the data.

- **Single account.** Public signup disabled at the database level.
- **Row-Level Security (RLS) on every table:** policy `user_id = auth.uid()`. Postgres itself rejects any non-owner request — even a leaked anon key returns nothing.
- **Private storage buckets.** No public URLs; media accessed only via short-lived signed URLs. Storage RLS scoped to owner.
- **2FA / passkey** login via Supabase MFA.
- **Encryption at rest** (Supabase default). HTTPS-only. Secure, http-only session cookies.
- **RLS policy tests** in the test suite — data isolation is proven, not assumed.

---

## 7. Storage strategy (media-heavy, multi-year)

- Photos/videos live in **object storage**, never in the database. DB stores only path + metadata in `media_assets`.
- **On upload:** compress images client-side; generate thumbnails. Videos store a poster frame and lazy-stream the original.
- UI lazy-loads media via cached signed URLs.
- **Abstracted `StorageService` interface** so the provider can swap (Supabase Storage → Cloudflare R2 / Backblaze B2) with no app changes when the tier is outgrown.
- A usage meter surfaces total storage footprint.

---

## 8. Finance UX (adapts the monorepo content-studio flow)

- **Finance dashboard** — month navigation (prev/next, like content-studio dashboard): net worth, this-month income/expense, **budget rings** (reuse `MiniRingChart`), **spend-by-category donut** (reuse `DonutChart`), account balances, upcoming recurring + subscriptions, SIP/investment summary. Reuse monorepo INR formatter (`Intl.NumberFormat('en-IN')`).
- **Transactions list** — like the content list: filter by account / category / month, search.
- **3-second quick-add** — amount pad → category chip → account → save; date defaults to today. Optimized for logging every rupee instantly.
- **Module views** — Accounts, Budgets, Goals, Investments. Reuse shadcn-svelte primitives (pill-tabs, cards, calendar popover, donut/ring charts) and `kn-` entrance animations.

---

## 9. Mindmap life-dashboard (Phase 6, last)

Reuse the monorepo `MindMapCanvas` + `treeLayout` (and `@xyflow/svelte`). Center node = "You"; branches = modules; nodes connect through the `links` table — e.g. a Goal → its Savings goal → its linked Transactions, or a Health habit → Journal mentions. Renders the "what's going on in my life" view. Built last because it visualizes the other modules.

---

## 10. Build order

| Phase | Deliverable |
|---|---|
| **0 — Foundation** | Scaffold SvelteKit; port design tokens + 3 themes; app shell (floating panels, sidebar, mobile drawer, theme switch); Supabase project; auth (single user + 2FA); RLS; offline cache + sync; PWA install |
| **1 — Finance (MVP)** | Accounts, transactions, 3-second quick-add, categories + budgets, recurring + salary, subscriptions, savings goals, investments/SIPs, finance dashboard |
| 2 | Journal (TipTap + media pipeline) |
| 3 | To-do + Goals |
| 4 | Health + Fitness |
| 5 | Notes |
| 6 | Mindmap life-dashboard |

---

## 11. Testing

- **Vitest** — money math is tested hard: paise arithmetic, balances, budget rollups, transfers. This is where "not 1 rupee" is enforced.
- **Playwright** — add-transaction flow; offline-then-sync.
- **RLS tests** — prove owner-only data isolation.

---

## 12. Non-goals (YAGNI for now)

- No bank auto-sync / Account Aggregator (deferred).
- No UPI-SMS parsing yet (deferred helper).
- No client-side end-to-end encryption (locked-cloud chosen).
- No multi-user / sharing — single owner only.
- No native mobile app — responsive PWA covers it.
