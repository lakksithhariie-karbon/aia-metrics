import type { RetentionKpiResponse } from "./types";

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
      `supabase_${response.status}:${fn}:${detail.slice(0, 160)}`,
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

export async function readRetentionKpis(params: {
  from: string | null;
  to: string | null;
  signal?: AbortSignal;
}): Promise<RetentionKpiResponse> {
  const payload = await rpc<RetentionKpiResponse | RetentionKpiResponse[]>(
    "read_retention_kpis_v2",
    {
      p_from: params.from,
      p_to: params.to,
    },
    params.signal,
  );
  return scalar(payload);
}
