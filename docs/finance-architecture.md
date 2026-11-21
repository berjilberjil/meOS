# MeOS Finance — architecture and invariants

Finance is a first-class native module (`Finance` in the Mac sidebar and an
iPhone tab). The screens are SwiftUI and run on both targets from the same
files under `apps/apple/MeOS/MeFinance*.swift`.

## Source of truth

The live source is the encrypted, synced `meos.finance` document, persisted by
the established MeOS state store (`/api/state`) exactly like every other module.
It contains separate keyed collections — accounts, categories, transactions,
transfers, budgets, investments, valuations, liabilities, debt payments, goals,
recurring commitments, statements, imports, reconciliations, audit history,
snapshots and milestones — with stable IDs and foreign-key-style string IDs.

There is **no server-side finance table and no plaintext finance data** on the
server. MeOS is zero-knowledge, so the ledger stays on-device and syncs as
ciphertext. The API allowlist already reserves `meos.finance` and a
`meos.finance.<shard>` prefix for the next storage step.

### Size and sharding

D1 stores one value per key and the API caps a write at 1.9 MB (with a lower
byte cap in `stateKeys.ts`). A single document is therefore a bridge, not the
final shape. `financeCommit` refuses a growing write above a plaintext guard
(`1,300,000` bytes) instead of claiming a save the server will reject.

Before the first real multi-year import, split the document by year:

```
meos.finance                 settings, accounts, categories, budgets, goals,
                             recurring rules, import metadata
meos.finance.tx.<yyyy>       transactions for one year
meos.finance.tx.<yyyy>.<n>   overflow page
meos.finance.audit.<yyyy>    append-only audit entries
meos.finance.import.<id>     one staged import batch
```

The model and IDs stay unchanged; only the storage boundary moves. The prefix
is already allowlisted and tested on the server.

## Money, time and identity

- All money is `Int64` paise. No `Double` arithmetic is used for balances or
  totals. Percentages are display-only.
- Currency is explicit (`INR`), dates are civil `yyyy-MM-dd` keys in
  `Asia/Kolkata`, timestamps are ISO-8601.
- Every entity has a stable string ID. Seeded categories use deterministic IDs
  so two devices cannot duplicate them.
- Account numbers, card numbers, CVV, PINs and credentials are not collected.

## Classification rules (enforced by `FinanceEngine`)

- Internal transfers are neither income nor expense. A paired transfer creates
  one outflow and one inflow with a shared `transferID`.
- A credit-card purchase is the expense. Paying the card is a transfer to the
  card account; it is never a second expense. The card balance is signed
  negative in net worth and positive as outstanding debt.
- Refunds reduce spending. They are never income.
- Investment purchases and sales are capital movements, not spending. A sale
  records proceeds, cost basis and realised gain explicitly.
- Loan principal repayment reduces the liability. Only the interest portion is
  an expense. A loan disbursement is cash and debt, not income.
- A transaction belongs to exactly one account. A transfer has two rows.
- Derived values are never written back as facts.

## Certainty

Every balance, valuation and historical point carries a `FinCertainty`:

- **Verified** — a statement balance, explicit valuation, or captured snapshot.
- **Calculated** — derived from recorded transactions.
- **Estimated** — carried forward from an older valuation.
- **Unknown** — no supporting record.

Account balances anchor on the latest statement balance (or the opening
balance), so no movement is counted twice. A valuation later than a historical
date is never leaked backwards; the cost basis is used and marked estimated.
Missing months are skipped, not interpolated.

## Audit

Corrections append an immutable `FinAuditEntry` with entity, field, previous
value, new value, actor, timestamp and reason. Imported records keep
`source = imported`; a correction returns them to `needsReview`. Deleting a
transaction writes its full snapshot into the audit log. The Audit screen
surfaces duplicates, uncategorised rows, unmatched transfers, reconciliation
mismatches, missing references, invalid dates, large amount corrections and
unverified imports, each with a review path.

## Demo data

`FinanceDemo.build()` is deterministic and fictional. Every row is flagged
`isDemo`; the document also carries `settings.demoMode`. Loading is only
possible on an empty document or an existing demo document. Removal filters
exclusively on the demo flag, so real rows are never touched.

## Statement import

This phase implements the complete UI architecture and the safety contract, not
a parser. Choosing a file records only its name, size and type, then states that
nothing was read, parsed or imported. The 12-stage pipeline is visible and
honest about what is deferred. Import batch/row models and the audit contract
are ready for the next phase; staged rows never post automatically.

## AI

The native assistant gains read-only finance tools and a compact finance context
section. The MeOS MCP gateway additionally exposes the encrypted ledger to
authorised external agents through `meos_finance_ledger_*`: summary, accounts,
transactions, search, spending, net worth, investments, liabilities, budgets,
goals, timeline, and writes for accounts, transactions, transfers, investments,
valuations and liabilities. The gateway unlocks the same `meos.finance` document
with the owner's vault passphrase; the server never sees plaintext. Fold remains
a separate read-only snapshot and must never be mixed with ledger totals. Every
answer carries certainty and must state missing data. No credentials or account
numbers exist to expose.

## Tests

`apps/apple/Package.swift` builds the pure finance domain as a Swift package and
runs `Tests/FinanceCoreTests`. It compiles the same source files as the app.
Coverage includes transfers, credit cards, refunds, loan principal/interest,
investment valuation and history, net worth, statement anchors, budgets,
duplicates, transfer matching, date filtering, currency precision, tax
classification, CSV escaping and demo-data flags.

```bash
cd apps/apple
swift test
xcodebuild -scheme MeOS-macOS build
xcodebuild -scheme MeOS -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

## Known limits

- No live market feed. Investment values are manually or statement-entered.
- No statement parser yet; the UI says so.
- A single encrypted module document is the current bridge. Year-sharded keys
  must ship before the first real multi-year import; the size guard makes that
  limit visible now.
- Tax liability is never calculated; the Tax Centre only reports recorded facts.
