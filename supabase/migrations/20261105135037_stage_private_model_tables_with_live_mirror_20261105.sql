-- Model stage A (2026-11-05): keep existing external PostgreSQL ON CONFLICT ingestion intact.
-- Physical read-model tables and reporting view in "04_model_schema" are mirrored
-- by source-table AFTER triggers. No writes to teammate-owned schemas.
DO $pre$
BEGIN
  IF to_regclass('"04_model_schema".companies') IS NOT NULL
     OR to_regclass('"04_model_schema".bill_costs') IS NOT NULL
     OR to_regclass('"04_model_schema".bill_extraction_reporting_v1') IS NOT NULL
  THEN RAISE EXCEPTION 'Model destination is not empty, refusing overwrite'; END IF;
  IF to_regclass('aia_infra.bill_costs') IS NULL
     OR to_regclass('aia_infra.companies') IS NULL
     OR to_regclass('aia_infra.bill_extraction_reporting_v1') IS NULL
  THEN RAISE EXCEPTION 'Model source missing'; END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid IN
      ('aia_infra.bill_costs'::regclass,'aia_infra.companies'::regclass)
      AND tgname IN ('model_bill_costs_mirror_to_v1','model_companies_mirror_to_v1'))
  THEN RAISE EXCEPTION 'Mirror triggers already exist'; END IF;
END;
$pre$;

-- This short lock blocks a concurrent external UPSERT only while the initial copy
-- is taken and the mirroring triggers are installed. The old writer never changes.
LOCK TABLE aia_infra.companies,aia_infra.bill_costs IN SHARE ROW EXCLUSIVE MODE;

CREATE TABLE "04_model_schema".companies (LIKE aia_infra.companies INCLUDING ALL);
CREATE TABLE "04_model_schema".bill_costs (LIKE aia_infra.bill_costs INCLUDING ALL);
ALTER TABLE "04_model_schema".bill_costs
 ADD CONSTRAINT bill_costs_company_uuid_fkey
 FOREIGN KEY (company_uuid) REFERENCES "04_model_schema".companies(company_uuid);

INSERT INTO "04_model_schema".companies (company_uuid,company_name,is_test,created_at)
 SELECT company_uuid,company_name,is_test,created_at FROM aia_infra.companies;

-- total_cost and total_latency are stored GENERATED columns, so they must not
-- be included in the insert list. PostgreSQL recomputes them in the target.
INSERT INTO "04_model_schema".bill_costs
 (prediction_uuid,company_uuid,file_uuid,created_at,review_status,
  extraction_cost,enrichment_cost,extraction_latency,enrichment_latency,
  doc_type,legibility_score,total_pages,has_raw,loaded_at)
SELECT prediction_uuid,company_uuid,file_uuid,created_at,review_status,
  extraction_cost,enrichment_cost,extraction_latency,enrichment_latency,
  doc_type,legibility_score,total_pages,has_raw,loaded_at
FROM aia_infra.bill_costs;

ALTER TABLE "04_model_schema".companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE "04_model_schema".bill_costs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE "04_model_schema".companies, "04_model_schema".bill_costs
 FROM PUBLIC,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA "04_model_schema" TO product_metrics_fetcher;
GRANT SELECT ON TABLE "04_model_schema".companies,"04_model_schema".bill_costs
 TO product_metrics_fetcher;

CREATE POLICY model_companies_reader ON "04_model_schema".companies
 FOR SELECT TO product_metrics_fetcher USING (true);
CREATE POLICY model_bill_costs_reader ON "04_model_schema".bill_costs
 FOR SELECT TO product_metrics_fetcher USING (true);

-- A SECURITY DEFINER trigger keeps this mirror independent of the external
-- writer's role. It cannot be invoked as an RPC (RETURNS trigger).
CREATE FUNCTION "04_model_schema".mirror_companies_from_legacy_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $mirror$
BEGIN
  IF TG_OP='DELETE' THEN
    DELETE FROM "04_model_schema".companies WHERE company_uuid=OLD.company_uuid;
    RETURN OLD;
  END IF;
  IF TG_OP='UPDATE' AND NEW.company_uuid IS DISTINCT FROM OLD.company_uuid THEN
    DELETE FROM "04_model_schema".companies WHERE company_uuid=OLD.company_uuid;
  END IF;
  INSERT INTO "04_model_schema".companies(company_uuid,company_name,is_test,created_at)
  VALUES (NEW.company_uuid,NEW.company_name,NEW.is_test,NEW.created_at)
  ON CONFLICT(company_uuid) DO UPDATE SET
    company_name=excluded.company_name,is_test=excluded.is_test,
    created_at=excluded.created_at;
  RETURN NEW;
END;
$mirror$;
REVOKE ALL ON FUNCTION "04_model_schema".mirror_companies_from_legacy_v1()
 FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher;

CREATE FUNCTION "04_model_schema".mirror_bill_costs_from_legacy_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $mirror$
BEGIN
  IF TG_OP='DELETE' THEN
    DELETE FROM "04_model_schema".bill_costs WHERE prediction_uuid=OLD.prediction_uuid;
    RETURN OLD;
  END IF;
  IF TG_OP='UPDATE' AND NEW.prediction_uuid IS DISTINCT FROM OLD.prediction_uuid THEN
    DELETE FROM "04_model_schema".bill_costs WHERE prediction_uuid=OLD.prediction_uuid;
  END IF;
  INSERT INTO "04_model_schema".bill_costs
    (prediction_uuid,company_uuid,file_uuid,created_at,review_status,
     extraction_cost,enrichment_cost,extraction_latency,enrichment_latency,
     doc_type,legibility_score,total_pages,has_raw,loaded_at)
  VALUES
    (NEW.prediction_uuid,NEW.company_uuid,NEW.file_uuid,NEW.created_at,NEW.review_status,
     NEW.extraction_cost,NEW.enrichment_cost,NEW.extraction_latency,NEW.enrichment_latency,
     NEW.doc_type,NEW.legibility_score,NEW.total_pages,NEW.has_raw,NEW.loaded_at)
  ON CONFLICT(prediction_uuid) DO UPDATE SET
    company_uuid=excluded.company_uuid,
    file_uuid=excluded.file_uuid,
    created_at=excluded.created_at,
    review_status=excluded.review_status,
    extraction_cost=excluded.extraction_cost,
    enrichment_cost=excluded.enrichment_cost,
    extraction_latency=excluded.extraction_latency,
    enrichment_latency=excluded.enrichment_latency,
    doc_type=excluded.doc_type,
    legibility_score=excluded.legibility_score,
    total_pages=excluded.total_pages,
    has_raw=excluded.has_raw,
    loaded_at=excluded.loaded_at;
  RETURN NEW;
END;
$mirror$;
REVOKE ALL ON FUNCTION "04_model_schema".mirror_bill_costs_from_legacy_v1()
 FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher;

CREATE TRIGGER model_companies_mirror_to_v1
 AFTER INSERT OR UPDATE OR DELETE ON aia_infra.companies
 FOR EACH ROW EXECUTE FUNCTION "04_model_schema".mirror_companies_from_legacy_v1();
CREATE TRIGGER model_bill_costs_mirror_to_v1
 AFTER INSERT OR UPDATE OR DELETE ON aia_infra.bill_costs
 FOR EACH ROW EXECUTE FUNCTION "04_model_schema".mirror_bill_costs_from_legacy_v1();

-- Preserve the exact production view SQL, projection, company-scope semantics
-- and security_barrier; only the two physical source paths change.
DO $createview$
DECLARE v_def text;
BEGIN
  SELECT pg_get_viewdef('aia_infra.bill_extraction_reporting_v1'::regclass,true)
    INTO STRICT v_def;
  IF position('aia_infra.bill_costs' IN v_def)=0
     OR position('aia_infra.companies' IN v_def)=0
  THEN RAISE EXCEPTION 'Reporting view structure unexpected'; END IF;
  v_def:=replace(replace(replace(v_def,
    'aia_infra.bill_costs','"04_model_schema".bill_costs'),
    'aia_infra.companies','"04_model_schema".companies'),
    'JOIN company_directory','JOIN public.company_directory');
  EXECUTE 'CREATE VIEW "04_model_schema".bill_extraction_reporting_v1 WITH (security_barrier=true) AS '||v_def;
END;
$createview$;
REVOKE ALL ON TABLE "04_model_schema".bill_extraction_reporting_v1
 FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON TABLE "04_model_schema".bill_extraction_reporting_v1 TO product_metrics_fetcher;
COMMENT ON VIEW "04_model_schema".bill_extraction_reporting_v1 IS
 'Private mirrored AI bill extraction reporting v1. Known cost/latency NULLs are preserved; no verified cost currency or latency units. Source writes remain at aia_infra pending ETL cutover.';
COMMENT ON COLUMN "04_model_schema".bill_extraction_reporting_v1.company_scope IS
 'verified_customer, test_company, or unverified_company. Production customer dashboards default to verified_customer.';
COMMENT ON COLUMN "04_model_schema".bill_extraction_reporting_v1.known_total_cost IS
 'Source total_cost unless both components missing; NULL means unknown, not free. Currency is not verified.';
COMMENT ON COLUMN "04_model_schema".bill_extraction_reporting_v1.known_total_latency IS
 'Source total_latency unless both components missing; NULL means unknown. Units unverified.';

COMMENT ON SCHEMA "04_model_schema" IS
 'Private AI bill extraction reporting domain. Mirrored physical tables and reporting view; source ingestion remains in aia_infra pending producer change.';

-- No published RPCs switch during this transaction. Check every row and
-- every reporting projection before permitting a reader switch.
DO $verify$
DECLARE bad bigint;
BEGIN
  IF (SELECT count(*) FROM aia_infra.companies) <>
     (SELECT count(*) FROM "04_model_schema".companies)
  OR (SELECT count(*) FROM aia_infra.bill_costs) <>
     (SELECT count(*) FROM "04_model_schema".bill_costs)
  OR (SELECT count(*) FROM aia_infra.bill_extraction_reporting_v1) <>
     (SELECT count(*) FROM "04_model_schema".bill_extraction_reporting_v1)
  THEN RAISE EXCEPTION 'Model row counts mismatch; rolling back'; END IF;

  SELECT count(*) INTO bad FROM aia_infra.companies s
    FULL JOIN "04_model_schema".companies t USING(company_uuid)
    WHERE to_jsonb(s) IS DISTINCT FROM to_jsonb(t);
  IF bad<>0 THEN RAISE EXCEPTION 'Model companies mismatch %',bad; END IF;

  SELECT count(*) INTO bad FROM aia_infra.bill_costs s
    FULL JOIN "04_model_schema".bill_costs t USING(prediction_uuid)
    WHERE to_jsonb(s) IS DISTINCT FROM to_jsonb(t);
  IF bad<>0 THEN RAISE EXCEPTION 'Model bill_costs mismatch %',bad; END IF;

  SELECT count(*) INTO bad FROM aia_infra.bill_extraction_reporting_v1 s
    FULL JOIN "04_model_schema".bill_extraction_reporting_v1 t USING(prediction_uuid)
    WHERE to_jsonb(s) IS DISTINCT FROM to_jsonb(t);
  IF bad<>0 THEN RAISE EXCEPTION 'Model reporting view mismatch %',bad; END IF;
END;
$verify$;