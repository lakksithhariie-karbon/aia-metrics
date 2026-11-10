-- Rollback-only regression: older Jira issue copies for Sprint 1270 contain
-- future, active and closed states. Previously a single derive_issue batch
-- tried to UPSERT the same sprint PK repeatedly and failed.
-- This test never commits its temporary derivation.
BEGIN;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='10s';
DO $test$
DECLARE v_rows integer; v_state text;
BEGIN
 SELECT count(*) INTO v_rows
 FROM "02_engineering_schema".derive_issue(ARRAY[34571,36145,28330]::bigint[]);
 IF v_rows<>3 THEN RAISE EXCEPTION 'Expected 3 derived issues, got %',v_rows; END IF;
 SELECT state INTO v_state FROM "02_engineering_schema".sprints WHERE id=1270;
 IF v_state IS DISTINCT FROM 'closed' THEN
  RAISE EXCEPTION 'Expected Jira sprint 1270 closed, got %',v_state;
 END IF;
END $test$;
SELECT 'PASS: three conflicting sprint-state copies handled, closed wins' AS test_result;
ROLLBACK;
