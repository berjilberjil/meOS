# Legacy Supabase schema — NOT used by the running MeOS app

This directory is the schema and edge function from the pre-Cloudflare web
application. The live app runs on Cloudflare Workers + D1 and keeps encrypted
module documents in `app_state`; it does not connect to Supabase and has no RLS.

The finance tables in `0002_finance.sql` are a useful **data-model reference**
for the upcoming Personal Finance expansion, but they do not describe any
running system. Do not apply these migrations to a new environment.

Kept rather than deleted because:

- it records the intended relationships of the old modules, and
- deleting migration history is not reversible.

If you need to retire it fully, move the directory to an archive branch instead
of editing or reordering the files. The live D1 schema is
`apps/api/db/schema.sqlite.sql`.
