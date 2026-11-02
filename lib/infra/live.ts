/** Read-only server facade for the latest successful, reconciled AWS sync. */
import "server-only";
import type { InfraPreviewData } from "./types";

type LivePayload = InfraPreviewData & { contract: string };
const validMonth = (v: unknown): v is string =>
  typeof v === "string" && /^20\d{2}-(0[1-9]|1[0-2])$/.test(v);
const numeric = (v: unknown): v is number =>
  typeof v === "number" && Number.isFinite(v);
const nonnegative = (v: unknown): v is number => numeric(v) && v >= 0;

export async function readInfraAwsLive(): Promise<InfraPreviewData> {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("infra_aws_credentials_missing");
  const response = await fetch(
    url.replace(/\/+$/, "") + "/rest/v1/rpc/read_infra_aws_live_v1",
    {
      method: "POST",
      body: "{}",
      cache: "no-store",
      signal: AbortSignal.timeout(20000),
      headers: {
        apikey: key,
        Authorization: "Bearer " + key,
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      },
    },
  );
  if (!response.ok) throw new Error("infra_aws_rpc_http_" + response.status);

  const raw: unknown = await response.json();
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("infra_aws_report_unavailable");
  }
  const data = raw as LivePayload;
  const run = data.awsRun;
  const months = data.awsMonths;
  if (data.contract !== "infra_aws_live_v1" ||
      data.mode !== "live-aws-costs" ||
      !run || !Array.isArray(months) || months.length < 1 || months.length > 14 ||
      !Array.isArray(data.awsServices) || !Array.isArray(data.awsAccounts) ||
      !numeric(run.referenceUsd) || !nonnegative(run.storedDetailUsd) ||
      Math.abs(run.referenceUsd - run.storedDetailUsd) > 0.05 ||
      run.months !== months.length ||
      !Number.isSafeInteger(run.rows) || run.rows < 1 ||
      !Number.isSafeInteger(run.accounts) || run.accounts < 1 ||
      !Number.isFinite(Date.parse(data.awsAsOf)) ||
      data.awsAsOf !== run.finishedAt ||
      months.some((m,i) => !validMonth(m.month) || !nonnegative(m.usd) ||
        !Number.isSafeInteger(m.accounts) || !Number.isSafeInteger(m.services) ||
        typeof m.estimated !== "boolean" ||
        (i > 0 && months[i-1].month >= m.month)) ||
      data.awsServices.some(s => !validMonth(s.month) || !numeric(s.usd) ||
        typeof s.service !== "string" || !months.some(m => m.month === s.month)) ||
      data.awsAccounts.some(a => !validMonth(a.month) || !numeric(a.usd) ||
        typeof a.label !== "string" || !/^Account \d{2,}$/.test(a.label) ||
        !months.some(m => m.month === a.month))) {
    throw new Error("infra_aws_report_contract_invalid");
  }
  // Stopped ingestion must not silently resemble a fresh feed.
  const age = Date.now() - Date.parse(data.awsAsOf);
  if (age < -120000 || age > 7 * 86400000) {
    throw new Error("infra_aws_sync_stale");
  }
  return data;
}
