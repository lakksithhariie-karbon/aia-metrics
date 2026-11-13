-- Remove isolated canary writer bridge functions, no production writer changes.
DROP FUNCTION IF EXISTS public.shadow_product_watermark();
DROP FUNCTION IF EXISTS public.shadow_product_prune_overview_members(integer);
DROP FUNCTION IF EXISTS public.shadow_product_prune_funnel_members(integer);
DROP FUNCTION IF EXISTS public.shadow_product_prune_product_snapshots(integer);
DROP FUNCTION IF EXISTS public.shadow_product_refresh_retention(text);
DROP FUNCTION IF EXISTS public.shadow_product_finish_incremental(boolean,date,text);
DROP FUNCTION IF EXISTS public.shadow_product_upsert_mixpanel_events_detail(jsonb);
DROP FUNCTION IF EXISTS public.shadow_product_try_begin_incremental(interval);
