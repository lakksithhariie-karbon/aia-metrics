# Product shadow ingestion canary

This Function is cloned from deployed `sync-incremental` v11 and calls service-role-only `public.shadow_product_*` bridge RPCs. It writes only to `01_product_schema`, with no production cron or frontend route pointing to it. Keep JWT verification enabled. **Do not schedule or replace the production ingestion writer until separately tested and an atomic rollback is ready.**

The exact original is backed up at `supabase/rollback/sync-incremental-v11/`.
