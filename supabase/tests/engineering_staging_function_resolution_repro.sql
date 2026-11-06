-- STAGING DATABASE ONLY. Never run this on production.
-- Small, fully rolled-back reproduction for the SQL helper-resolution failure.
-- It creates synthetic helper functions under an isolated schema, renames that
-- schema to a quoted numeric-leading name, then compiles and calls a dependent
-- SQL function using the same function-local search_path representation.
-- No customer or Jira production data is read, copied, updated or deleted.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

CREATE SCHEMA engineering_resolution_repro_legacy;

CREATE FUNCTION engineering_resolution_repro_legacy._filter_sprint_matches(
  payload jsonb,p_sprint_ids integer[]
) RETURNS boolean LANGUAGE sql IMMUTABLE
SET search_path TO 'engineering_resolution_repro_legacy','public','pg_catalog'
AS $helper$
  SELECT (payload->>'sprint_id')::integer = ANY(p_sprint_ids);
$helper$;

CREATE FUNCTION engineering_resolution_repro_legacy._filter_cohort_row_matches(
  p_payload jsonb,p_sprint_ids integer[]
) RETURNS boolean LANGUAGE sql IMMUTABLE
SET search_path TO 'engineering_resolution_repro_legacy','public','pg_catalog'
AS $caller$
  SELECT _filter_sprint_matches(p_payload,p_sprint_ids);
$caller$;

DO $pre$
BEGIN
 IF engineering_resolution_repro_legacy._filter_cohort_row_matches(
   '{"sprint_id":123}'::jsonb,ARRAY[123]::integer[]) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Synthetic pre-rename function failed'; END IF;
END;
$pre$;

ALTER SCHEMA engineering_resolution_repro_legacy RENAME TO "02_engineering_resolution_repro";

DO $recompile$
DECLARE
 f text;
 original_check text;
 original_path text;
BEGIN
 original_path:=current_setting('search_path');
 original_check:=current_setting('check_function_bodies');
 PERFORM set_config('search_path','"02_engineering_resolution_repro",public,pg_catalog',true);
 PERFORM set_config('check_function_bodies','off',true);
 SELECT pg_get_functiondef('"02_engineering_resolution_repro"._filter_cohort_row_matches(jsonb,integer[])'::regprocedure)
 INTO f;
 f:=replace(f,
   'SET search_path TO ''engineering_resolution_repro_legacy'',',
   'SET search_path TO ''"02_engineering_resolution_repro"'',');
 EXECUTE f;
 PERFORM set_config('check_function_bodies',original_check,true);
 PERFORM set_config('search_path',original_path,true);
END;
$recompile$;

DO $post$
DECLARE
 path_value text;
 caller_config text[];
 helper_config text[];
 result boolean;
BEGIN
 SELECT proconfig INTO caller_config FROM pg_proc
 WHERE oid='"02_engineering_resolution_repro"._filter_cohort_row_matches(jsonb,integer[])'::regprocedure;
 SELECT proconfig INTO helper_config FROM pg_proc
 WHERE oid='"02_engineering_resolution_repro"._filter_sprint_matches(jsonb,integer[])'::regprocedure;
 path_value:=array_to_string(caller_config,',');
 -- The helper's local search_path is still the pre-rename name, but the caller
 -- explicitly names the new schema. This isolates function-local lookup.
 EXECUTE 'SELECT "02_engineering_resolution_repro"._filter_cohort_row_matches(''{"sprint_id":123}''::jsonb,ARRAY[123]::integer[])' INTO result;
 IF result IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Reproduced dependent SQL function lookup failure: %, %',
   path_value,helper_config; END IF;
END;
$post$;

-- Expected: all validation blocks succeed. No objects survive this test.
ROLLBACK;