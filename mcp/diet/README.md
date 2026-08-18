# Native MyOS diet MCP

Talks to the **Swift** Mac app (and through it, iPhone). Not the Tauri/SvelteKit project.

1. Keep native MyOS open and unlocked on this Mac.
2. The app listens on `127.0.0.1:17881`.
3. Grok loads `myos-diet` from `.mcp.json` / `~/.grok/config.toml`.

Weekday `0` = Sunday … `6` = Saturday. Meal keys: `breakfast`, `lunch`, `dinner`, `snacks`.

If the Mac app is closed, set `MYOS_PASSWORD` + `MYOS_VAULT_PASSPHRASE` in `.env` (see `.env.example`) and the MCP uses the production API instead.
