-- Stage 1 of domain-oriented schema organization.
-- Intentionally create empty, non-exposed namespaces only.
-- DO NOT MOVE any tables, views, routines, jobs or privileges in this step.
-- Teammate-owned feature_olap is completely out of scope.
CREATE SCHEMA IF NOT EXISTS "01_product_schema" AUTHORIZATION postgres;
CREATE SCHEMA IF NOT EXISTS "02_engineering_schema" AUTHORIZATION postgres;
CREATE SCHEMA IF NOT EXISTS "03_infra_schema" AUTHORIZATION postgres;
CREATE SCHEMA IF NOT EXISTS "04_model_schema" AUTHORIZATION postgres;

REVOKE ALL ON SCHEMA "01_product_schema" FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SCHEMA "02_engineering_schema" FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SCHEMA "03_infra_schema" FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SCHEMA "04_model_schema" FROM PUBLIC, anon, authenticated;

COMMENT ON SCHEMA "01_product_schema" IS 'Reserved for product/customer activity, retention, and metrics tables. Empty pending dependency-safe migration.';
COMMENT ON SCHEMA "02_engineering_schema" IS 'Reserved for engineering and Jira data and reporting. Empty pending dependency-safe migration.';
COMMENT ON SCHEMA "03_infra_schema" IS 'Reserved for AWS/cloud costs and sync operations. Empty pending dependency-safe migration.';
COMMENT ON SCHEMA "04_model_schema" IS 'Reserved for AI extraction/model cost and inference analytics. Empty pending dependency-safe migration.';
