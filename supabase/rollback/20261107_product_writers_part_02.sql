-- Exact original public Product writer/helper definitions. Restore part 2/5.
-- Retains existing function grants when run with CREATE OR REPLACE.
-- Review impact before applying. Captured 2026-11-07.
SET LOCAL lock_timeout='7s';

CREATE OR REPLACE FUNCTION public.normalize_event_properties(p_event_name text, p_properties jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE PARALLEL SAFE
AS $function$
DECLARE
  result jsonb := '{}'::jsonb;
  value text;
  normalized text;
  raw jsonb;
  item jsonb;
  text_items text[];
BEGIN
  IF p_properties IS NULL OR jsonb_typeof(p_properties) <> 'object' THEN
    RETURN result;
  END IF;

  -- -------------------------------------------------------------------------
  -- v1 keys are global: any event may carry them.
  -- -------------------------------------------------------------------------

  -- String-valued keys accept JSON strings only. `->>` renders a number,
  -- boolean, object or array as text, which would invent a value the producer
  -- never emitted (and would disagree with the Deno parser, which drops
  -- structures, and with Python for booleans). The jsonb_typeof guard keeps the
  -- three implementations identical. Non-string input stays absent.
  value := CASE WHEN jsonb_typeof(p_properties->'companyName') = 'string'
                THEN NULLIF(btrim(p_properties->>'companyName'), '') END;
  IF value IS NOT NULL THEN
    result := result || jsonb_build_object('companyName', value);
  END IF;

  value := CASE WHEN jsonb_typeof(p_properties->'type') = 'string'
                THEN NULLIF(btrim(p_properties->>'type'), '') END;
  IF value IS NOT NULL THEN
    normalized := lower(value);
    IF normalized = 'gst2b' THEN normalized := 'gstr2b'; END IF;
    result := result || jsonb_build_object('type', normalized);
  END IF;

  value := CASE WHEN jsonb_typeof(p_properties->'subType') = 'string'
                THEN NULLIF(btrim(p_properties->>'subType'), '') END;
  IF value IS NOT NULL THEN
    normalized := lower(value);
    IF p_event_name = 'Upload'
       AND normalized NOT IN ('bulk', 'single', 'gst_reconciliation') THEN
      normalized := 'bank';
    END IF;
    result := result || jsonb_build_object('subType', normalized);
  END IF;

  value := CASE WHEN jsonb_typeof(p_properties->'fileType') = 'string'
                THEN NULLIF(btrim(p_properties->>'fileType'), '') END;
  IF value IS NOT NULL THEN
    result := result || jsonb_build_object('fileType', value);
  END IF;

  value := CASE WHEN jsonb_typeof(p_properties->'status') = 'string'
                THEN NULLIF(btrim(p_properties->>'status'), '') END;
  IF value IS NOT NULL THEN
    normalized := lower(value);
    IF normalized = 'success' THEN
      value := 'Success';
    ELSIF normalized = 'failed' THEN
      value := 'Failed';
    END IF;
    result := result || jsonb_build_object('status', value);
  END IF;

  FOREACH value IN ARRAY ARRAY[
    'source', 'entityType', 'action', 'productCode', 'widgetName',
    'flow', 'method', 'viewSource'
  ]
  LOOP
    IF jsonb_typeof(p_properties->value) = 'string' THEN
      normalized := NULLIF(btrim(p_properties->>value), '');
      IF normalized IS NOT NULL THEN
        result := result || jsonb_build_object(value, normalized);
      END IF;
    END IF;
  END LOOP;

  value := CASE WHEN jsonb_typeof(p_properties->'transactionType') = 'string'
                THEN NULLIF(btrim(p_properties->>'transactionType'), '') END;
  IF value IS NOT NULL THEN
    IF value ~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' THEN
      normalized := value;
    ELSE
      normalized := lower(value);
    END IF;
    result := result || jsonb_build_object('transactionType', normalized);
  END IF;

  raw := p_properties->'isReactivation';
  IF jsonb_typeof(raw) = 'boolean' THEN
    result := result || jsonb_build_object('isReactivation', raw);
  END IF;

  -- items_count is a GLOBAL v1 key, exactly as deployed v1/011 has it: any
  -- event may carry it, and it survives whenever it is a valid JSON number.
  -- Product logic (qualifying sync / activation) may consume it only on
  -- 'Accounting Sync', but that is a consumer rule, not an ingest rule -- the
  -- gate must keep the key on every event or it silently drops a valid producer
  -- value and regresses deployed behaviour.
  raw := p_properties->'items_count';
  IF jsonb_typeof(raw) = 'number' THEN
    result := result || jsonb_build_object('items_count', raw);
  END IF;

  -- -------------------------------------------------------------------------
  -- v1.1 keys are event-scoped. Each block is guarded on p_event_name, so an
  -- unrelated event can never retain the key. Keep this order identical to
  -- _V1_1_PROPERTY_KINDS in fetcher/parse.py and V1_1_PROPERTY_KINDS in
  -- parse.ts.
  -- -------------------------------------------------------------------------

  -- Accounting Sync: sync_items (array<string>). items_count is the global v1
  -- key handled above, not a v1.1 addition.
  IF p_event_name = 'Accounting Sync' THEN
    IF p_properties ? 'sync_items' THEN
      raw := p_properties->'sync_items';
      IF jsonb_typeof(raw) = 'array' THEN
        text_items := ARRAY[]::text[];
        FOR item IN SELECT jsonb_array_elements(raw)
        LOOP
          -- Every element must be a non-blank string, else the whole value is
          -- malformed and is dropped rather than partially trusted.
          IF jsonb_typeof(item) <> 'string' THEN
            text_items := NULL;
            EXIT;
          END IF;
          value := NULLIF(btrim(item #>> '{}'), '');
          IF value IS NULL THEN
            text_items := NULL;
            EXIT;
          END IF;
          text_items := text_items || value;
        END LOOP;
        IF text_items IS NOT NULL THEN
          result := result || jsonb_build_object('sync_items', to_jsonb(text_items));
        END IF;
      END IF;
    END IF;
  END IF;

  -- Transaction Status: itemsCount (number).
  IF p_event_name = 'Transaction Status' THEN
    raw := p_properties->'itemsCount';
    IF jsonb_typeof(raw) = 'number' THEN
      result := result || jsonb_build_object('itemsCount', raw);
    END IF;
  END IF;

  -- Transaction Ledger Updated / Transaction Type Updated: transactionCount.
  IF p_event_name IN ('Transaction Ledger Updated', 'Transaction Type Updated') THEN
    raw := p_properties->'transactionCount';
    IF jsonb_typeof(raw) = 'number' THEN
      result := result || jsonb_build_object('transactionCount', raw);
    END IF;
  END IF;

  -- Vendor Mismatch Resolved: resolutionType (text).
  IF p_event_name = 'Vendor Mismatch Resolved' THEN
    normalized := CASE WHEN jsonb_typeof(p_properties->'resolutionType') = 'string'
                       THEN NULLIF(btrim(p_properties->>'resolutionType'), '') END;
    IF normalized IS NOT NULL THEN
      result := result || jsonb_build_object('resolutionType', normalized);
    END IF;
  END IF;

  -- Transaction Configuration Edited: configField (text) plus the two scalar
  -- state values (string | boolean | finite number, source type preserved).
  IF p_event_name = 'Transaction Configuration Edited' THEN
    normalized := CASE WHEN jsonb_typeof(p_properties->'configField') = 'string'
                       THEN NULLIF(btrim(p_properties->>'configField'), '') END;
    IF normalized IS NOT NULL THEN
      result := result || jsonb_build_object('configField', normalized);
    END IF;

    -- These two keys come from the same scalar rule, so they are handled in one
    -- loop. (jsonb does not preserve key order on storage, so the SQL layer
    -- makes no ordering claim; ordering is a Python/Deno parser property.)
    FOREACH value IN ARRAY ARRAY['previousState', 'newState']
    LOOP
      raw := p_properties->value;
      IF jsonb_typeof(raw) = 'boolean' OR jsonb_typeof(raw) = 'number' THEN
        result := result || jsonb_build_object(value, raw);
      ELSIF jsonb_typeof(raw) = 'string' THEN
        normalized := NULLIF(btrim(p_properties->>value), '');
        IF normalized IS NOT NULL THEN
          result := result || jsonb_build_object(value, normalized);
        END IF;
      END IF;
    END LOOP;
  END IF;

  IF p_event_name = 'Billing Intent Claimed' THEN
    IF jsonb_typeof(p_properties->'outcome') = 'string' AND NULLIF(btrim(p_properties->>'outcome'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('outcome', lower(NULLIF(btrim(p_properties->>'outcome'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Billing Intent Claimed' THEN
    IF jsonb_typeof(p_properties->'stage') = 'string' AND NULLIF(btrim(p_properties->>'stage'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('stage', lower(NULLIF(btrim(p_properties->>'stage'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Billing Intent Created' THEN
    IF jsonb_typeof(p_properties->'outcome') = 'string' AND NULLIF(btrim(p_properties->>'outcome'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('outcome', lower(NULLIF(btrim(p_properties->>'outcome'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Billing Intent Created' THEN
    IF jsonb_typeof(p_properties->'stage') = 'string' AND NULLIF(btrim(p_properties->>'stage'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('stage', lower(NULLIF(btrim(p_properties->>'stage'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Billing Intent Refreshed' THEN
    IF jsonb_typeof(p_properties->'outcome') = 'string' AND NULLIF(btrim(p_properties->>'outcome'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('outcome', lower(NULLIF(btrim(p_properties->>'outcome'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Billing Intent Refreshed' THEN
    IF jsonb_typeof(p_properties->'stage') = 'string' AND NULLIF(btrim(p_properties->>'stage'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('stage', lower(NULLIF(btrim(p_properties->>'stage'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Billing Intent Reserved' THEN
    IF jsonb_typeof(p_properties->'billingExpected') = 'boolean' THEN
      result := result || jsonb_build_object('billingExpected', p_properties->'billingExpected');
    END IF;
  END IF;
  IF p_event_name = 'Billing Intent Reserved' THEN
    IF jsonb_typeof(p_properties->'outcome') = 'string' AND NULLIF(btrim(p_properties->>'outcome'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('outcome', lower(NULLIF(btrim(p_properties->>'outcome'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Billing Intent Reserved' THEN
    IF jsonb_typeof(p_properties->'stage') = 'string' AND NULLIF(btrim(p_properties->>'stage'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('stage', lower(NULLIF(btrim(p_properties->>'stage'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Company Created' THEN
    IF jsonb_typeof(p_properties->'createdBy') = 'string' AND NULLIF(btrim(p_properties->>'createdBy'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('createdBy', NULLIF(btrim(p_properties->>'createdBy'), ''));
    END IF;
  END IF;
  IF p_event_name = 'Company Created' THEN
    IF jsonb_typeof(p_properties->'userUuid') = 'string' AND NULLIF(btrim(p_properties->>'userUuid'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('userUuid', NULLIF(btrim(p_properties->>'userUuid'), ''));
    END IF;
  END IF;
  IF p_event_name = 'Company Switched' THEN
    IF jsonb_typeof(p_properties->'fromCompanyId') = 'string' AND NULLIF(btrim(p_properties->>'fromCompanyId'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('fromCompanyId', NULLIF(btrim(p_properties->>'fromCompanyId'), ''));
    END IF;
  END IF;
  IF p_event_name = 'Company Switched' THEN
    IF jsonb_typeof(p_properties->'organisationId') = 'string' AND NULLIF(btrim(p_properties->>'organisationId'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('organisationId', NULLIF(btrim(p_properties->>'organisationId'), ''));
    ELSIF p_properties->'organisationId' = 'null'::jsonb THEN
      result := result || jsonb_build_object('organisationId', NULL);
    END IF;
  END IF;
  IF p_event_name = 'Company Switched' THEN
    IF jsonb_typeof(p_properties->'toCompanyId') = 'string' AND NULLIF(btrim(p_properties->>'toCompanyId'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('toCompanyId', NULLIF(btrim(p_properties->>'toCompanyId'), ''));
    END IF;
  END IF;
  IF p_event_name = 'Company Switched' THEN
    IF jsonb_typeof(p_properties->'toolConnected') = 'string' AND NULLIF(btrim(p_properties->>'toolConnected'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('toolConnected', lower(NULLIF(btrim(p_properties->>'toolConnected'), '')));
    ELSIF p_properties->'toolConnected' = 'null'::jsonb THEN
      result := result || jsonb_build_object('toolConnected', NULL);
    END IF;
  END IF;
  IF p_event_name = 'Duplicate Phone Attempt' THEN
    IF jsonb_typeof(p_properties->'outcome') = 'string' AND NULLIF(btrim(p_properties->>'outcome'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('outcome', lower(NULLIF(btrim(p_properties->>'outcome'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Duplicate Phone Attempt' THEN
    IF jsonb_typeof(p_properties->'reason') = 'string' AND NULLIF(btrim(p_properties->>'reason'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('reason', lower(NULLIF(btrim(p_properties->>'reason'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Duplicate Phone Attempt' THEN
    IF jsonb_typeof(p_properties->'stage') = 'string' AND NULLIF(btrim(p_properties->>'stage'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('stage', lower(NULLIF(btrim(p_properties->>'stage'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Login' THEN
    IF jsonb_typeof(p_properties->'billingExpected') = 'boolean' THEN
      result := result || jsonb_build_object('billingExpected', p_properties->'billingExpected');
    END IF;
  END IF;
  IF p_event_name = 'Phone OTP Failed' THEN
    IF jsonb_typeof(p_properties->'attemptsRemaining') = 'number' THEN
      result := result || jsonb_build_object('attemptsRemaining', p_properties->'attemptsRemaining');
    END IF;
  END IF;
  IF p_event_name = 'Phone OTP Failed' THEN
    IF jsonb_typeof(p_properties->'outcome') = 'string' AND NULLIF(btrim(p_properties->>'outcome'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('outcome', lower(NULLIF(btrim(p_properties->>'outcome'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Phone OTP Failed' THEN
    IF jsonb_typeof(p_properties->'reason') = 'string' AND NULLIF(btrim(p_properties->>'reason'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('reason', lower(NULLIF(btrim(p_properties->>'reason'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Phone OTP Failed' THEN
    IF jsonb_typeof(p_properties->'stage') = 'string' AND NULLIF(btrim(p_properties->>'stage'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('stage', lower(NULLIF(btrim(p_properties->>'stage'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Phone OTP Resent' THEN
    IF jsonb_typeof(p_properties->'outcome') = 'string' AND NULLIF(btrim(p_properties->>'outcome'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('outcome', lower(NULLIF(btrim(p_properties->>'outcome'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Phone OTP Resent' THEN
    IF jsonb_typeof(p_properties->'stage') = 'string' AND NULLIF(btrim(p_properties->>'stage'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('stage', lower(NULLIF(btrim(p_properties->>'stage'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Phone OTP Sent' THEN
    IF jsonb_typeof(p_properties->'outcome') = 'string' AND NULLIF(btrim(p_properties->>'outcome'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('outcome', lower(NULLIF(btrim(p_properties->>'outcome'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Phone OTP Sent' THEN
    IF jsonb_typeof(p_properties->'stage') = 'string' AND NULLIF(btrim(p_properties->>'stage'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('stage', lower(NULLIF(btrim(p_properties->>'stage'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Phone OTP Verification Attempted' THEN
    IF jsonb_typeof(p_properties->'outcome') = 'string' AND NULLIF(btrim(p_properties->>'outcome'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('outcome', lower(NULLIF(btrim(p_properties->>'outcome'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Phone OTP Verification Attempted' THEN
    IF jsonb_typeof(p_properties->'stage') = 'string' AND NULLIF(btrim(p_properties->>'stage'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('stage', lower(NULLIF(btrim(p_properties->>'stage'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Phone Verification Completed' THEN
    IF jsonb_typeof(p_properties->'outcome') = 'string' AND NULLIF(btrim(p_properties->>'outcome'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('outcome', lower(NULLIF(btrim(p_properties->>'outcome'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Phone Verification Completed' THEN
    IF jsonb_typeof(p_properties->'stage') = 'string' AND NULLIF(btrim(p_properties->>'stage'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('stage', lower(NULLIF(btrim(p_properties->>'stage'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Phone Verification Locked' THEN
    IF jsonb_typeof(p_properties->'outcome') = 'string' AND NULLIF(btrim(p_properties->>'outcome'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('outcome', lower(NULLIF(btrim(p_properties->>'outcome'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Phone Verification Locked' THEN
    IF jsonb_typeof(p_properties->'reason') = 'string' AND NULLIF(btrim(p_properties->>'reason'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('reason', lower(NULLIF(btrim(p_properties->>'reason'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Phone Verification Locked' THEN
    IF jsonb_typeof(p_properties->'stage') = 'string' AND NULLIF(btrim(p_properties->>'stage'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('stage', lower(NULLIF(btrim(p_properties->>'stage'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Phone Verification Required' THEN
    IF jsonb_typeof(p_properties->'billingExpected') = 'boolean' THEN
      result := result || jsonb_build_object('billingExpected', p_properties->'billingExpected');
    END IF;
  END IF;
  IF p_event_name = 'Phone Verification Required' THEN
    IF jsonb_typeof(p_properties->'outcome') = 'string' AND NULLIF(btrim(p_properties->>'outcome'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('outcome', lower(NULLIF(btrim(p_properties->>'outcome'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Phone Verification Required' THEN
    IF jsonb_typeof(p_properties->'stage') = 'string' AND NULLIF(btrim(p_properties->>'stage'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('stage', lower(NULLIF(btrim(p_properties->>'stage'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Product Subscription' THEN
    IF jsonb_typeof(p_properties->'productUuid') = 'string' AND NULLIF(btrim(p_properties->>'productUuid'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('productUuid', NULLIF(btrim(p_properties->>'productUuid'), ''));
    END IF;
  END IF;
  IF p_event_name = 'Sign Up' THEN
    IF jsonb_typeof(p_properties->'billingExpected') = 'boolean' THEN
      result := result || jsonb_build_object('billingExpected', p_properties->'billingExpected');
    END IF;
  END IF;
  IF p_event_name = 'Sign Up' THEN
    IF jsonb_typeof(p_properties->'signUpMethod') = 'string' AND NULLIF(btrim(p_properties->>'signUpMethod'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('signUpMethod', lower(NULLIF(btrim(p_properties->>'signUpMethod'), '')));
    END IF;
  END IF;
  IF p_event_name = 'Transaction Ledger Updated' THEN
    IF jsonb_typeof(p_properties->'from') = 'string' AND NULLIF(btrim(p_properties->>'from'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('from', NULLIF(btrim(p_properties->>'from'), ''));
    ELSIF p_properties->'from' = 'null'::jsonb THEN
      result := result || jsonb_build_object('from', NULL);
    END IF;
  END IF;
  IF p_event_name = 'Transaction Ledger Updated' THEN
    IF jsonb_typeof(p_properties->'to') = 'string' AND NULLIF(btrim(p_properties->>'to'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('to', NULLIF(btrim(p_properties->>'to'), ''));
    END IF;
  END IF;
  IF p_event_name = 'Transaction Type Updated' THEN
    IF jsonb_typeof(p_properties->'bankLineUuid') = 'string' AND NULLIF(btrim(p_properties->>'bankLineUuid'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('bankLineUuid', NULLIF(btrim(p_properties->>'bankLineUuid'), ''));
    END IF;
  END IF;
  IF p_event_name = 'Transaction Type Updated' THEN
    IF jsonb_typeof(p_properties->'from') = 'string' AND NULLIF(btrim(p_properties->>'from'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('from', NULLIF(btrim(p_properties->>'from'), ''));
    ELSIF p_properties->'from' = 'null'::jsonb THEN
      result := result || jsonb_build_object('from', NULL);
    END IF;
  END IF;
  IF p_event_name = 'Transaction Type Updated' THEN
    IF jsonb_typeof(p_properties->'to') = 'string' AND NULLIF(btrim(p_properties->>'to'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('to', NULLIF(btrim(p_properties->>'to'), ''));
    END IF;
  END IF;
  IF p_event_name = 'Upload' THEN
    IF jsonb_typeof(p_properties->'reason') = 'string' AND NULLIF(btrim(p_properties->>'reason'), '') IS NOT NULL THEN
      result := result || jsonb_build_object('reason', lower(NULLIF(btrim(p_properties->>'reason'), '')));
    END IF;
  END IF;

  RETURN result;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.prune_funnel_members(p_keep_per_scope integer DEFAULT 5)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_keep integer;
  v_deleted integer;
BEGIN
  v_keep := GREATEST(COALESCE(p_keep_per_scope, 5), 1);
  -- The seal IS the completion record: a completed set — published now,
  -- retained as an older generation, or kept alive by a page publication —
  -- is swept only when its SNAPSHOT row is gone (prune_product_snapshots
  -- cascades members, drill headers and the seal together). What can be
  -- swept is exactly the debris: membership rows whose snapshot was never
  -- sealed (an aborted stage that left partial rows behind).
  WITH doomed AS (
    SELECT r.id
    FROM public.product_snapshot AS r
    WHERE r.kind = 'overview-funnel'
      AND r.id IN (
        SELECT s.id
        FROM public.product_snapshot AS s
        WHERE s.kind = 'overview-funnel'
          AND s.id IN (
            SELECT m.snapshot_id FROM public.product_funnel_member AS m
            UNION
            SELECT d.snapshot_id FROM public.product_funnel_drill AS d
          )
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.product_funnel_seal AS x
        WHERE x.snapshot_id = r.id
      )
  )
  DELETE FROM public.product_funnel_member AS m
  USING doomed AS d
  WHERE m.snapshot_id = d.id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  WITH doomed AS (
    SELECT r.id
    FROM public.product_snapshot AS r
    WHERE r.kind = 'overview-funnel'
      AND r.id IN (
        SELECT m.snapshot_id FROM public.product_funnel_member AS m
        UNION
        SELECT d.snapshot_id FROM public.product_funnel_drill AS d
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.product_funnel_seal AS x
        WHERE x.snapshot_id = r.id
      )
  )
  DELETE FROM public.product_funnel_drill AS d
  USING doomed AS dd
  WHERE d.snapshot_id = dd.id;
  RETURN v_deleted;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.prune_overview_members(p_keep_per_scope integer DEFAULT 5)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_keep integer;
  v_deleted integer;
BEGIN
  v_keep := GREATEST(COALESCE(p_keep_per_scope, 5), 1);
  WITH doomed AS (
    SELECT r.id
    FROM public.product_snapshot AS r
    WHERE r.kind IN ('overview', 'overview-feature-usage', 'overview-module-mix', 'overview-friction')
      AND r.id IN (
        SELECT s.id FROM public.product_snapshot AS s
        WHERE s.kind IN ('overview', 'overview-feature-usage', 'overview-module-mix', 'overview-friction')
          AND s.id IN (
            SELECT m.snapshot_id FROM public.product_overview_member AS m
            UNION SELECT d.snapshot_id FROM public.product_overview_drill AS d
          )
      )
      AND NOT EXISTS (SELECT 1 FROM public.product_overview_seal AS x WHERE x.snapshot_id = r.id)
  )
  DELETE FROM public.product_overview_member AS m USING doomed AS d WHERE m.snapshot_id = d.id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  WITH doomed AS (
    SELECT r.id FROM public.product_snapshot AS r
    WHERE r.kind IN ('overview', 'overview-feature-usage', 'overview-module-mix', 'overview-friction')
      AND r.id IN (SELECT m.snapshot_id FROM public.product_overview_member AS m UNION SELECT d.snapshot_id FROM public.product_overview_drill AS d)
      AND NOT EXISTS (SELECT 1 FROM public.product_overview_seal AS x WHERE x.snapshot_id = r.id)
  )
  DELETE FROM public.product_overview_drill AS d USING doomed AS dd WHERE d.snapshot_id = dd.id;
  RETURN v_deleted;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.prune_product_refresh_runs(p_keep_days integer DEFAULT 90)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_deleted integer;
BEGIN
  DELETE FROM public.product_refresh_run AS r
  WHERE r.updated_at < now() - (GREATEST(COALESCE(p_keep_days, 90), 1)::text || ' days')::interval
    AND r.status IN ('published', 'failed', 'superseded');
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.prune_product_snapshots(p_keep_per_scope integer DEFAULT 5)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_keep integer;
  v_deleted integer;
BEGIN
  v_keep := GREATEST(COALESCE(p_keep_per_scope, 5), 1);
  WITH ranked AS (
    SELECT s.id,
           ROW_NUMBER() OVER (
             PARTITION BY s.kind, s.scope_key ORDER BY s.id DESC
           ) AS rn
    FROM public.product_snapshot AS s
  ), doomed AS (
    SELECT r.id
    FROM ranked AS r
    WHERE r.rn > v_keep
      AND NOT EXISTS (
        SELECT 1
        FROM public.product_snapshot_current AS c
        WHERE c.snapshot_id = r.id
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.product_publication_member AS m
        WHERE m.snapshot_id = r.id
      )
  )
  DELETE FROM public.product_snapshot AS s
  USING doomed AS d
  WHERE s.id = d.id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$function$
;
