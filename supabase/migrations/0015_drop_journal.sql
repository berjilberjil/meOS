-- The journal (diary) feature was removed from MeOS on 2026-11-01.
--
-- `0003_journal.sql` stays in history because it already ran; this migration
-- brings existing and fresh databases to the same shape by dropping the table.
-- Journal media reused `media_assets` with owner_type = 'journal'; those rows
-- are left in place (the table is still used by events and belongings).
drop table if exists journal_entries;
