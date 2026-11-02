-- Make Infra read the latest complete, reconciled AWS Cost Explorer sync.
-- Public Next.js routes are unauthenticated, so ONLY the server-side service_role
-- may execute this RPC. The function never emits linked-account identifiers.
CREATE OR REPLACE FUNCTION public.read_infra_aws_live_v1()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $infra$
WITH latest AS MATERIALIZED (
  SELECT started_at, finished_at, months_covered, accounts, rows_upserted, total_usd
  FROM aia_infra.aws_cost_sync_runs
  WHERE ok IS TRUE AND finished_at IS NOT NULL
  ORDER BY finished_at DESC
  LIMIT 1
),
-- A single successful run is the publication boundary: old upserts that no
-- longer exist in AWS must not leak into current-month or closed-month totals.
items AS MATERIALIZED (
  SELECT c.cost_month, c.linked_account, c.service, c.cost_usd, c.estimated
  FROM aia_infra.aws_costs c
  CROSS JOIN latest r
  WHERE c.fetched_at >= r.started_at AND c.fetched_at <= r.finished_at
    AND c.cost_month >= (date_trunc('month',r.started_at) - interval '13 months')::date
    AND c.cost_month <= date_trunc('month',r.started_at)::date
    AND c.currency = 'USD'
),
month_cost AS (
  SELECT cost_month, round(sum(cost_usd),2) AS usd,
         count(DISTINCT linked_account) AS accounts,
         count(DISTINCT service) AS services,
         bool_or(estimated) AS estimated
  FROM items GROUP BY cost_month
),
service_cost AS (
  SELECT cost_month, service, round(sum(cost_usd),2) AS usd
  FROM items GROUP BY cost_month,service
),
account_labels AS (
  SELECT linked_account,
         'Account ' || lpad(row_number() OVER (ORDER BY linked_account)::text,2,'0') AS label
  FROM (SELECT DISTINCT linked_account FROM items) a
),
account_cost AS (
  SELECT i.cost_month, l.label, round(sum(i.cost_usd),2) AS usd
  FROM items i JOIN account_labels l ON l.linked_account=i.linked_account
  GROUP BY i.cost_month,l.label
),
detail AS (
  SELECT count(*) AS rows, count(DISTINCT cost_month) AS months,
         count(DISTINCT linked_account) AS accounts,
         coalesce(sum(cost_usd),0)::numeric AS stored_usd
  FROM items
)
SELECT jsonb_build_object(
  'contract','infra_aws_live_v1',
  'mode','live-aws-costs',
  'awsAsOf',to_char(r.finished_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  'awsRun',jsonb_build_object(
    'finishedAt',to_char(r.finished_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'months',r.months_covered,
    'accounts',r.accounts,
    'rows',r.rows_upserted,
    'referenceUsd',r.total_usd,
    'storedDetailUsd',d.stored_usd,
    'driftUsd',round(d.stored_usd-r.total_usd,4)
  ),
  'awsMonths',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'month',to_char(m.cost_month,'YYYY-MM'),
      'usd',m.usd,
      'accounts',m.accounts,
      'services',m.services,
      'estimated',m.estimated
    ) ORDER BY m.cost_month)
    FROM month_cost m
  ),'[]'::jsonb),
  'awsServices',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'month',to_char(s.cost_month,'YYYY-MM'),
      'service',s.service,
      'usd',s.usd
    ) ORDER BY s.cost_month,s.service)
    FROM service_cost s
  ),'[]'::jsonb),
  'awsAccounts',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'month',to_char(a.cost_month,'YYYY-MM'),
      'label',a.label,
      'usd',a.usd
    ) ORDER BY a.cost_month,a.label)
    FROM account_cost a
  ),'[]'::jsonb)
)
FROM latest r CROSS JOIN detail d
WHERE d.rows=r.rows_upserted
  AND d.months=r.months_covered
  AND d.accounts=r.accounts
  AND abs(d.stored_usd-r.total_usd)<=0.05;
$infra$;

REVOKE ALL ON FUNCTION public.read_infra_aws_live_v1()
  FROM PUBLIC, anon, authenticated, product_metrics_fetcher;
GRANT EXECUTE ON FUNCTION public.read_infra_aws_live_v1() TO service_role;
COMMENT ON FUNCTION public.read_infra_aws_live_v1() IS
  'Private service-role-only, masked, UTC-monthly USD aggregates from the most recent complete AWS sync; rejects row-count and cost reconciliation errors.';

-- Cron already wakes at 04:17 UTC every day, but the old four-day guard
-- caused actual imports every five days. Keep the schedule, shorten the
-- de-duplication threshold so each daily wake starts a new sync.
DO $cron$
DECLARE target cron.job%ROWTYPE;
BEGIN
  SELECT * INTO STRICT target
  FROM cron.job WHERE jobname='aws-cost-sync' AND active IS TRUE;
  IF target.schedule <> '17 4 * * *'
     OR position('interval ''4 days''' IN target.command)=0 THEN
    RAISE EXCEPTION 'AWS cron schedule/guard changed; refusing unsafe update';
  END IF;
  PERFORM cron.alter_job(
    job_id := target.jobid,
    command := replace(target.command,'interval ''4 days''','interval ''20 hours''')
  );
END;
$cron$;
