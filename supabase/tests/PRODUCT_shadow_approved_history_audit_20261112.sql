-- Product shadow source-fidelity audit (Nov 12 2026).
-- Non-destructive. Full 58-table physical parity remains separately reported by
-- product_cutover_small_parity_part_{1,2,3}.sql and product_cutover_large_parity.sql.
-- Strict exact parity now passes after the shadow Edge canary's built-in prune.
-- Also permit ONLY the three previously documented, unreferenced Oct 26
-- historical generations if still present (for replay before pruning).
-- Any other extra MUST fail.
-- Source rows must match exactly in BOTH values and multiplicity.
-- Do not use this to override PRODUCT_cutover_go_no_go.sql (Overview still blocked).
WITH
approved(id,kind,members,drills) AS (
 VALUES (348::bigint,'overview-module-mix'::text,883::bigint,16::bigint),
        (351::bigint,'overview-friction'::text,622::bigint,30::bigint),
        (354::bigint,'overview'::text,8638::bigint,63::bigint)
),
shadow_only_snapshots AS (
 SELECT s.id,s.kind,s.source_watermark_at,s.n_events,s.build_key,
    a.kind expected_kind,a.members expected_members,a.drills expected_drills,
    (SELECT count(*) FROM "01_product_schema".product_overview_member m WHERE m.snapshot_id=s.id) member_rows,
    (SELECT count(*) FROM "01_product_schema".product_overview_drill d WHERE d.snapshot_id=s.id) drill_rows,
    (SELECT count(*) FROM "01_product_schema".product_overview_seal z WHERE z.snapshot_id=s.id) seal_rows,
    (SELECT count(*) FROM "01_product_schema".product_snapshot_current c WHERE c.snapshot_id=s.id) current_refs,
    (SELECT count(*) FROM "01_product_schema".product_publication_member pm WHERE pm.snapshot_id=s.id) publication_refs
 FROM "01_product_schema".product_snapshot s
 LEFT JOIN approved a ON a.id=s.id
 WHERE NOT EXISTS (SELECT 1 FROM public.product_snapshot p WHERE p.id=s.id)
),
source_missing AS (
 SELECT 'product_snapshot' relation,count(*) missing_count FROM
   (SELECT to_jsonb(s) doc FROM public.product_snapshot s
    EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema".product_snapshot d) x
 UNION ALL SELECT 'product_overview_member',count(*) FROM
   (SELECT to_jsonb(s) doc FROM public.product_overview_member s
    EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema".product_overview_member d) x
 UNION ALL SELECT 'product_overview_drill',count(*) FROM
   (SELECT to_jsonb(s) doc FROM public.product_overview_drill s
    EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema".product_overview_drill d) x
 UNION ALL SELECT 'product_overview_seal',count(*) FROM
   (SELECT to_jsonb(s) doc FROM public.product_overview_seal s
    EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema".product_overview_seal d) x
),
extra_members AS (
 SELECT (doc->>'snapshot_id')::bigint id,count(*) row_count FROM
   (SELECT to_jsonb(d) doc FROM "01_product_schema".product_overview_member d
    EXCEPT ALL SELECT to_jsonb(s) FROM public.product_overview_member s) x GROUP BY 1
),
extra_drills AS (
 SELECT (doc->>'snapshot_id')::bigint id,count(*) row_count FROM
   (SELECT to_jsonb(d) doc FROM "01_product_schema".product_overview_drill d
    EXCEPT ALL SELECT to_jsonb(s) FROM public.product_overview_drill s) x GROUP BY 1
),
extra_seals AS (
 SELECT (doc->>'snapshot_id')::bigint id,count(*) row_count FROM
   (SELECT to_jsonb(d) doc FROM "01_product_schema".product_overview_seal d
    EXCEPT ALL SELECT to_jsonb(s) FROM public.product_overview_seal s) x GROUP BY 1
),
checks AS (
 SELECT
 (SELECT count(*) FROM public.events) legacy_events,
 (SELECT count(*) FROM "01_product_schema".events) shadow_events,
 (SELECT sum(missing_count) FROM source_missing) source_rows_missing_or_mismatched,
 (SELECT count(*) FROM shadow_only_snapshots) shadow_only_generations,
 (SELECT coalesce(sum(row_count),0) FROM extra_members) extra_member_rows,
 (SELECT coalesce(sum(row_count),0) FROM extra_drills) extra_drill_rows,
 (SELECT coalesce(sum(row_count),0) FROM extra_seals) extra_seal_rows,
 NOT EXISTS(SELECT * FROM public.product_snapshot_current EXCEPT SELECT * FROM "01_product_schema".product_snapshot_current)
 AND NOT EXISTS(SELECT * FROM "01_product_schema".product_snapshot_current EXCEPT SELECT * FROM public.product_snapshot_current)
 AND NOT EXISTS(SELECT * FROM public.product_publication_current EXCEPT SELECT * FROM "01_product_schema".product_publication_current)
 AND NOT EXISTS(SELECT * FROM "01_product_schema".product_publication_current EXCEPT SELECT * FROM public.product_publication_current)
 AS current_pointers_match,
 (SELECT count(*)=3 AND coalesce(bool_and(
    s.kind=s.expected_kind
    AND s.source_watermark_at='2026-10-26 10:05:29.354647+00'::timestamptz
    AND s.n_events=511439 AND s.build_key IS NOT NULL
    AND s.member_rows=s.expected_members AND s.drill_rows=s.expected_drills
    AND s.seal_rows=1 AND s.current_refs=0 AND s.publication_refs=0),false)
 FROM shadow_only_snapshots s) AS all_three_archives_verified,
 NOT EXISTS(SELECT 1 FROM extra_members e LEFT JOIN approved a USING(id) WHERE a.id IS NULL OR e.row_count<>a.members)
 AND NOT EXISTS(SELECT 1 FROM extra_drills e LEFT JOIN approved a USING(id) WHERE a.id IS NULL OR e.row_count<>a.drills)
 AND NOT EXISTS(SELECT 1 FROM extra_seals e LEFT JOIN approved a USING(id) WHERE a.id IS NULL OR e.row_count<>1)
 AND (SELECT count(*) FROM extra_members)=3
 AND (SELECT count(*) FROM extra_drills)=3
 AND (SELECT count(*) FROM extra_seals)=3
 AS no_unapproved_extra_child_rows
)
SELECT now() AS checked_utc,checks.*,
 CASE
   WHEN legacy_events=shadow_events
     AND source_rows_missing_or_mismatched=0
     AND current_pointers_match
     AND shadow_only_generations=0 AND extra_member_rows=0
     AND extra_drill_rows=0 AND extra_seal_rows=0
   THEN 'pass_exact_parity'
   WHEN legacy_events=shadow_events
     AND source_rows_missing_or_mismatched=0
     AND current_pointers_match
     AND shadow_only_generations=3 AND extra_member_rows=10143
     AND extra_drill_rows=109 AND extra_seal_rows=3
     AND all_three_archives_verified AND no_unapproved_extra_child_rows
   THEN 'pass_source_fidelity_with_approved_historical_extras'
   ELSE 'FAIL_unexplained_source_or_shadow_divergence' END result
FROM checks;
