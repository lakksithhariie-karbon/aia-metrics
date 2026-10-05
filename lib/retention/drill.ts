import type {
  ActivationCompanyDetail,
  ActivationListResponse,
  ActivationStatus,
} from "./drill-types";

function credentials(): { url: string; key: string } {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("supabase_unavailable");
  return { url, key };
}

async function rpc<T>(
  fn: string,
  params: Record<string, unknown>,
  signal?: AbortSignal,
): Promise<T> {
  const { url, key } = credentials();
  const response = await fetch(`${url}/rest/v1/rpc/${fn}`, {
    method: "POST",
    cache: "no-store",
    signal,
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      "Cache-Control": "no-cache",
      Pragma: "no-cache",
    },
    body: JSON.stringify(params),
  });

  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    throw new Error(
      `supabase_${response.status}:${fn}:${detail.slice(0, 180)}`,
    );
  }

  return (await response.json()) as T;
}

function scalar<T>(value: T | T[]): T {
  if (Array.isArray(value)) {
    if (!value.length) throw new Error("supabase_empty_scalar");
    return value[0] as T;
  }
  return value;
}

export async function readActivationList(params: {
  from: string | null;
  to: string | null;
  query: string;
  status: ActivationStatus | "all";
  page: number;
  pageSize: number;
  signal?: AbortSignal;
}): Promise<ActivationListResponse> {
  const payload = await rpc<ActivationListResponse | ActivationListResponse[]>(
    "read_retention_activation_drill_page_v1",
    {
      p_from: params.from,
      p_to: params.to,
      p_query: params.query,
      p_status: params.status,
      p_page: params.page,
      p_page_size: params.pageSize,
    },
    params.signal,
  );
  return scalar(payload);
}

export async function readActivationCompanyDetail(params: {
  companyId: string;
  signal?: AbortSignal;
}): Promise<ActivationCompanyDetail> {
  const payload = await rpc<
    ActivationCompanyDetail | ActivationCompanyDetail[]
  >(
    "read_retention_activation_company_detail_v1",
    { p_company_id: params.companyId },
    params.signal,
  );
  return scalar(payload);
}
