-- Company OS trust audit, read-only.
-- Internal source/schema parity is NOT proof of Jira API, Mixpanel or AWS
-- upstream completeness. Do not promote Overview snapshots based on this.
-- Full Product 58-table EXCEPT ALL parity lives in product_cutover_{small,large}_parity*.sql.
WITH
product AS (
 SELECT
  (SELECT count(*) FROM public.events) original_events,
  (SELECT count(*) FROM "01_product_schema".events) new_events,
  (SELECT last_success_at FROM public.export_watermarks WHERE job_name='incremental') source_watermark,
  (SELECT last_success_at FROM "01_product_schema".export_watermarks WHERE job_name='incremental') new_watermark
),
eng AS (
 SELECT (SELECT count(*) FROM jira.issues) old_issues,
        (SELECT count(*) FROM "02_engineering_schema".issues) new_issues,
        (SELECT errors_count FROM "02_engineering_schema".sync_log ORDER BY id DESC LIMIT 1) last_errors,
        (SELECT finished_at FROM "02_engineering_schema".sync_log ORDER BY id DESC LIMIT 1) last_finished
),
infra AS (
 SELECT (SELECT max(finished_at) FROM "03_infra_schema".aws_cost_sync_runs WHERE ok) last_good,
        (SELECT max(finished_at) FROM aia_infra.aws_cost_sync_runs WHERE ok) legacy_good
),
checks AS (
 SELECT 'Product'::text domain, 'source_and_shadow_event_counts'::text test,
        (p.original_events=p.new_events AND p.source_watermark=p.new_watermark) ok,
        format('source %s, shadow %s; source watermark %s',p.original_events,p.new_events,p.source_watermark) detail
 FROM product p
 UNION ALL
 SELECT 'Engineering','latest_authenticated_jira_sync_no_errors',
        (eng.last_errors=0 AND eng.last_finished IS NOT NULL),
        format('new %s versus old %s issues; last finished %s; errors %s',eng.new_issues,eng.old_issues,eng.last_finished,eng.last_errors)
 FROM eng
 UNION ALL
 SELECT 'Engineering','legacy_issue_ids_all_present',
        NOT EXISTS(SELECT issue_id FROM jira.issues EXCEPT SELECT issue_id FROM "02_engineering_schema".issues),
        'Compares source-key coverage, not Jira API completeness'
 UNION ALL
 SELECT 'Engineering','derived_issue_referential_integrity',
        NOT EXISTS(SELECT 1 FROM "02_engineering_schema".raw_issues r LEFT JOIN "02_engineering_schema".issues i USING(issue_id) WHERE r.deleted_at IS NULL AND i.issue_id IS NULL)
        AND NOT EXISTS(SELECT 1 FROM "02_engineering_schema".sprint_issues si LEFT JOIN "02_engineering_schema".issues i USING(issue_id) WHERE i.issue_id IS NULL)
        AND NOT EXISTS(SELECT 1 FROM "02_engineering_schema".sprint_issues si LEFT JOIN "02_engineering_schema".sprints s ON s.id=si.sprint_id WHERE s.id IS NULL),
        'Raw issues, sprint issue and sprint FK orphans must be zero'
 UNION ALL
 SELECT 'Engineering','jira_link_semantic_parity',
        NOT EXISTS(SELECT issue_id,link_type_id,link_type_name,direction,description,related_issue_id,related_issue_key
          FROM jira.issue_links EXCEPT ALL
          SELECT issue_id,link_type_id,link_type_name,direction,description,related_issue_id,related_issue_key
          FROM "02_engineering_schema".issue_links)
        AND NOT EXISTS(SELECT issue_id,link_type_id,link_type_name,direction,description,related_issue_id,related_issue_key
          FROM "02_engineering_schema".issue_links EXCEPT ALL
          SELECT issue_id,link_type_id,link_type_name,direction,description,related_issue_id,related_issue_key
          FROM jira.issue_links),
        'Ignores sequence-generated link_id and ingestion synced_at'
 UNION ALL
 SELECT 'Infra','aws_current_daily_sync',
        infra.last_good>now()-interval '36 hours' AND infra.last_good>infra.legacy_good,
        format('new sync %s; legacy sync %s',infra.last_good,infra.legacy_good)
 FROM infra
 UNION ALL
 SELECT 'Infra','aws_legacy_cost_keys_all_present',
        NOT EXISTS(SELECT cost_month,linked_account,service,usage_type FROM aia_infra.aws_costs EXCEPT SELECT cost_month,linked_account,service,usage_type FROM "03_infra_schema".aws_costs),
        'Amounts may legitimately change when AWS revises estimates'
 UNION ALL
 SELECT 'Model','bill_costs_exact_row_parity',
        NOT EXISTS(SELECT to_jsonb(t) FROM aia_infra.bill_costs t EXCEPT ALL SELECT to_jsonb(t) FROM "04_model_schema".bill_costs t)
        AND NOT EXISTS(SELECT to_jsonb(t) FROM "04_model_schema".bill_costs t EXCEPT ALL SELECT to_jsonb(t) FROM aia_infra.bill_costs t),
        'Full columns, values and multiplicities, both directions'
 UNION ALL
 SELECT 'Model','company_dimension_exact_parity',
        NOT EXISTS(SELECT to_jsonb(t) FROM aia_infra.companies t EXCEPT ALL SELECT to_jsonb(t) FROM "04_model_schema".companies t)
        AND NOT EXISTS(SELECT to_jsonb(t) FROM "04_model_schema".companies t EXCEPT ALL SELECT to_jsonb(t) FROM aia_infra.companies t),
        'Full columns and values, both directions'
 UNION ALL
 SELECT 'Model','bill_reporting_view_exact_parity',
        NOT EXISTS(SELECT to_jsonb(t) FROM aia_infra.bill_extraction_reporting_v1 t EXCEPT ALL SELECT to_jsonb(t) FROM "04_model_schema".bill_extraction_reporting_v1 t)
        AND NOT EXISTS(SELECT to_jsonb(t) FROM "04_model_schema".bill_extraction_reporting_v1 t EXCEPT ALL SELECT to_jsonb(t) FROM aia_infra.bill_extraction_reporting_v1 t),
        'All reporting view fields and values, both directions'
 UNION ALL
 SELECT 'Overview','five_kind_freshness_and_manifest',
        EXISTS(
         SELECT 1 FROM "01_product_schema".product_publication_current pc
         JOIN "01_product_schema".product_publication pp ON pp.publication_id=pc.publication_id AND pp.page='overview'
         JOIN "01_product_schema".product_publication_member pm ON pm.publication_id=pp.publication_id
         JOIN "01_product_schema".product_snapshot_current sc ON sc.kind=pm.kind AND sc.scope_key=pm.scope_key AND sc.snapshot_id=pm.snapshot_id
         JOIN "01_product_schema".product_snapshot sn ON sn.id=pm.snapshot_id
         JOIN "01_product_schema".export_watermarks w ON w.job_name='incremental' AND w.status='ok'
         WHERE pc.page='overview'
         AND pp.source_watermark_at=w.last_success_at
         AND pp.n_events=(SELECT count(*) FROM "01_product_schema".events)
         AND w.last_success_at>=now()-interval '24 hours'
         GROUP BY pc.publication_id HAVING count(*)=5 AND count(DISTINCT pm.kind)=5
            AND bool_and(sn.source_status='ok' AND sn.source_watermark_at=pp.source_watermark_at)
        ),
        'Cutover remains blocked until all five current sealed kinds are rebuilt and atomically published'
)
SELECT now() checked_at,domain,test,coalesce(ok,false) pass,detail FROM checks ORDER BY domain,test;
