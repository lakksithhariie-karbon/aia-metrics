-- Nonbreaking point-in-time Overview snapshots for complete historical calendar months.
-- No synthetic activity: only recorded successful integrations and qualifying raw events.
-- Source as-of follows IST month-end, with published ingestion watermark frozen per build.
CREATE SEQUENCE IF NOT EXISTS metrics_private.overview_history_snapshot_id_seq
 START WITH 10000000 INCREMENT BY 1;

CREATE OR REPLACE FUNCTION public.refresh_overview_history_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
SET statement_timeout TO '100s'
AS $fn$
DECLARE
 v_wm timestamptz;v_latest timestamptz;v_month date;v_last date;
 v_cutoff timestamptz;v_snapshot_id bigint;v_members integer;v_count integer:=0;
 v_items jsonb:='[]'::jsonb;
BEGIN
 SELECT s.source_watermark_at,(s.payload#>>'{value,active_users,as_of}')::timestamptz
 INTO v_wm,v_latest
 FROM public.product_snapshot_current c JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
 LIMIT 1;
 IF v_wm IS NULL OR v_latest IS NULL THEN
  RAISE EXCEPTION 'Current verified Overview generation unavailable';
 END IF;
 FOR v_month IN
  SELECT generate_series(date '2026-03-01'::timestamp,
   (date_trunc('month',v_latest AT TIME ZONE 'Asia/Kolkata')-interval '1 month')::timestamp,
   interval '1 month')::date
 LOOP
  v_last:=(v_month+interval '1 month')::date-1;
  v_cutoff:=((v_last+1)::timestamp AT TIME ZONE 'Asia/Kolkata')-interval '1 second';

  SELECT id INTO v_snapshot_id FROM public.product_snapshot
  WHERE kind='overview' AND scope_key='asof='||to_char(v_last,'YYYY-MM-DD')
  ORDER BY created_at DESC LIMIT 1;
  IF v_snapshot_id IS NULL THEN
   INSERT INTO public.product_snapshot(
    kind,scope_key,payload,source_status,source_watermark_at,
    source_watermark_date,as_of_at,created_at,build_key
   ) VALUES(
    'overview','asof='||to_char(v_last,'YYYY-MM-DD'),
    jsonb_build_object('value',jsonb_build_object('active_users',
     jsonb_build_object('as_of',v_cutoff,'historical',true,'timezone','Asia/Kolkata'))),
    'ok',v_wm,(v_wm AT TIME ZONE 'Asia/Kolkata')::date,
    v_cutoff,now(),'verified-history-v1'
   ) RETURNING id INTO v_snapshot_id;
  ELSE
   UPDATE public.product_snapshot SET
    payload=jsonb_build_object('value',jsonb_build_object('active_users',
     jsonb_build_object('as_of',v_cutoff,'historical',true,'timezone','Asia/Kolkata'))),
    source_status='ok',source_watermark_at=v_wm,
    source_watermark_date=(v_wm AT TIME ZONE 'Asia/Kolkata')::date,
    as_of_at=v_cutoff,created_at=now(),build_key='verified-history-v1'
   WHERE id=v_snapshot_id;
  END IF;

  DELETE FROM public.product_overview_member WHERE snapshot_id=v_snapshot_id;

  WITH eligible AS MATERIALIZED(
   SELECT DISTINCT ON(e.company_id)
    e.company_id,e.event_time integrated_at,
    CASE lower(btrim(e.properties->>'type'))
      WHEN 'tally' THEN 'Tally' WHEN 'zoho' THEN 'Zoho Books'
      ELSE 'Unknown' END integration_type,
    coalesce(nullif(btrim(d.company_name),''),
      nullif(btrim(cp.company_name),''),e.company_id) company_name
   FROM public.events e
   JOIN public.client_company c ON c.company_id=e.company_id
   LEFT JOIN public.company_directory d ON d.company_uuid::text=e.company_id
   LEFT JOIN public.company_profile cp ON cp.company_id=e.company_id
   WHERE public.is_successful_integration(e.event_name,e.properties)
    AND e.event_time<v_cutoff-interval '28 days'
    AND e.ingested_at<=v_wm
    AND NOT coalesce(d.is_test,false)
   ORDER BY e.company_id,e.event_time,e.insert_id
  ),mature AS (
   SELECT * FROM eligible
   WHERE integrated_at>=v_cutoff-interval '56 days'
  ),ranked AS(
   SELECT *,row_number() OVER(ORDER BY integrated_at,company_id)-1 pos FROM mature
  )
  INSERT INTO public.product_overview_member(
    snapshot_id,kind,drill_key,tab,member_id,sort_position,card
  )
  SELECT v_snapshot_id,'overview',v.drill_key,'all',r.company_id,r.pos::integer,
   jsonb_build_object('company_name',r.company_name,
    'integration_type',r.integration_type,'integrated_at',r.integrated_at,
    'is_test',false,'historical',true)
  FROM ranked r CROSS JOIN (VALUES
    ('core_adoption_7d'),('sustained_adoption_28d'),('value_conversion_28d')
  ) v(drill_key);
  GET DIAGNOSTICS v_members=ROW_COUNT;
  v_count:=v_count+1;
  v_items:=v_items||jsonb_build_array(jsonb_build_object(
   'as_of',v_last,'snapshot_id',v_snapshot_id,
   'mature_integrations',v_members/3,'source_watermark_at',v_wm
  ));
 END LOOP;
 RETURN jsonb_build_object('built',v_count,'snapshots',v_items,'status','ok');
END;
$fn$;
REVOKE ALL ON FUNCTION public.refresh_overview_history_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_overview_history_v1() TO service_role;

CREATE OR REPLACE FUNCTION public.read_overview_history_id_v1(p_as_of date)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
AS $fn$
 SELECT s.id FROM public.product_snapshot s
 WHERE s.kind='overview'
 AND s.scope_key='asof='||to_char(p_as_of,'YYYY-MM-DD')
 AND s.source_status='ok'
 AND p_as_of=(date_trunc('month',p_as_of::timestamp)+interval '1 month'-interval '1 day')::date
 AND p_as_of >= date '2026-03-31'
 AND s.source_watermark_at IS NOT NULL
 LIMIT 1;
$fn$;
REVOKE ALL ON FUNCTION public.read_overview_history_id_v1(date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_history_id_v1(date) TO service_role;
