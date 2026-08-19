# MyOS Stuff MCP

Log what you buy, straight from a receipt screenshot.

Point an assistant at an Amazon order page or a bill image and it records the
**product link, title, category, purchase date, price** and the **payback window
(36 months by default)** — with the bill kept alongside the item. Everything
lands in the same encrypted store the **Stuff** tab uses, so it syncs to the
iPhone on its own.

## Requirements

Native MyOS must be **open and unlocked on this Mac**. The MCP talks to the app's
loopback bridge on `127.0.0.1:17881`.

Unlike `mcp/diet`, there is no remote/vault fallback: the ROI maths, the category
guesser and the bill downscaling all live in Swift, and a second copy in
TypeScript would be a second thing to keep correct. If the app is closed, every
tool says so plainly instead of half-working.

## Tools

| Tool | What it does |
| --- | --- |
| `get_spending` | Totals, monthly ownership burn vs salary, per-category breakdown. Start here. |
| `list_categories` | The shelves, with each one's default payback months. |
| `list_purchases` | Logged purchases newest first, each with ROI progress and true cost/day. |
| `add_purchase` | Log a purchase from a receipt. Only `name` is required. |
| `update_purchase` | Change a purchase. Only the fields you pass are touched. |
| `delete_purchase` | Remove one for good (prefer `retired: true` for things simply no longer owned). |

## Reading a receipt

Prices and dates go in **exactly as the receipt writes them** — the parsing is
handled here:

- `₹2,499.00`, `Rs. 1,09,999`, `INR 799.50` → whole rupees
- `19 August 2026`, `19th Aug, 2026`, `August 19, 2026`, `2026-08-19`
- `08/09/2026` → **8 September** — numeric dates are read day-first, the way
  Indian invoices write them
- Amazon links collapse to `https://www.amazon.in/dp/<ASIN>`, so two links to the
  same product stop looking like two products

Anything missing is inferred and **reported back** in an `inferred` list, so a
wrong guess can be corrected in one follow-up:

- category — from the product name
- date — today
- payback — 36 months
- price — `₹0` when the receipt gave nothing usable

Bill images can be passed as `bill_image_path` (a file on this Mac) or
`bill_image_base64`. They are downscaled to ≤1280px JPEG before being stored —
every byte here is encrypted, synced to every device and kept forever.

## Run

```bash
bun install
bun test        # the receipt parser
bun run start   # stdio MCP
```

Registered for Claude in `.mcp.json` and for Grok in `.grok/config.toml`, both at
the repo root.
