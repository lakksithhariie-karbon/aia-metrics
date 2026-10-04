/**
 * Server-only Companies data plane (never imported by client components).
 *
 * Reads Supabase with the deployment's SUPABASE_SERVICE_ROLE_KEY over
 * PostgREST — the key never leaves the server. The browser receives only the
 * bounded page/modal JSON. Classification lives in the service_role-only SQL
 * readers (supabase/companies-live.sql); this module shapes, filters, sorts,
 * and paginates their bounded aggregates.
 */
import {
  MODULES,
  type CompanyUsageResponse,
  type CompanyUsageRow,
  type CompanyUsageUser,
  type ModuleBreakdownResponse,
  type ModuleKey,
  type SortDirection,
  type SortKey,
  type Totals,
  type UsageFilter,
} from "./types";

const PAGE_SIZE = 10;
const UNATTRIBUTED_ID = "__unattributed__";
const UNATTRIBUTED_LABEL = "Unattributed activity";
const INTERNAL_DOMAINS = ["karboncard.com", "korefi.ai", "aiaccountant.com", "korefi.com"];

const emptyTotals = (): Totals => ({ ap: 0, ar: 0, transactions: 0, gst: 0, sync: 0 });
const text = (value: unknown): string => (typeof value === "string" ? value.trim() : "");
const companyTotal = (value: Totals): number =>
  value.ap + value.ar + value.transactions + value.gst + value.sync;
const isInternalEmail = (email: string): boolean => {
  const domain = email.toLowerCase().split("@").pop() ?? "";
  return INTERNAL_DOMAINS.some(
    internal => domain === internal || domain.endsWith(`.${internal}`),
  );
};
const istDay = (value: string): string =>
  new Date(value).toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" });

function credentials(): { url: string; key: string } {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("supabase_unavailable");
  return { url, key };
}

async function rest<T>(path: string, init?: RequestInit, signal?: AbortSignal): Promise<T> {
  const { url, key } = credentials();
  const response = await fetch(`${url}/rest/v1${path}`, {
    ...init,
    signal,
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
  });
  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    const server = response.headers.get("server") ?? "";
    const ray = response.headers.get("cf-ray") ?? response.headers.get("x-vercel-id") ?? "";
    throw new Error(`supabase_${response.status}:${path.slice(0, 60)}:srv=${server}:ray=${ray}:body=${detail.slice(0, 100)}`);
  }
  return (await response.json()) as T;
}

async function readAll<T>(collection: string, select: string, extra = "", cap = 50_000, signal?: AbortSignal): Promise<T[]> {
  const output: T[] = [];
  for (let start = 0; start < cap; start += 1000) {
    const rows = await rest<T[]>(
      `/${collection}?select=${select}${extra}&offset=${start}&limit=1000`,
      undefined,
      signal,
    );
    output.push(...rows);
    if (rows.length < 1000) break;
  }
  return output;
}

async function rpc<T>(fn: string, params: Record<string, unknown>, signal?: AbortSignal): Promise<T> {
  return rest<T>(`/rpc/${fn}`, { method: "POST", body: JSON.stringify(params) }, signal);
}

export interface ListParams {
  signal?: AbortSignal;
  page: number;
  query: string;
  integration: string;
  usage: UsageFilter;
  sort: SortKey;
  direction: SortDirection;
  from: string | null;
  to: string | null;
}

export async function listCompanies(params: ListParams): Promise<CompanyUsageResponse> {
  const signal = params.signal;
  const search = params.query.trim().toLowerCase();
  const [clientRows, directoryRows, usageRows, memberRows, nameRows, firstEvent, lastEvent, watermark] =
    await Promise.all([
      readAll<{ company_id: string }>("client_company", "company_id", "", 10_000, signal),
      readAll<{ company_uuid: string; company_name: string; is_test: boolean }>(
        "company_directory", "company_uuid,company_name,is_test", "", 10_000, signal,
      ),
      rpc<Array<{ company_id: string; user_key: string | null; module: string; events: number }>>(
        "read_companies_usage", { p_from: params.from, p_to: params.to }, signal,
      ),
      rpc<Array<{ company_id: string; user_key: string; user_email: string | null }>>(
        "read_company_users", {}, signal,
      ),
      rpc<Array<{ company_id: string; event_name: string }>>(
        "read_company_names", { p_company_id: null }, signal,
      ),
      rest<Array<{ event_time: string }>>("events?select=event_time&order=event_time.asc&limit=1", undefined, signal),
      rest<Array<{ event_time: string }>>("events?select=event_time&order=event_time.desc&limit=1", undefined, signal),
      rest<Array<{ last_success_at: string }>>(
        'export_watermarks?select=last_success_at&job_name=eq.incremental&status=eq.ok&limit=1',
        undefined,
        signal,
      ),
    ]);

  const dataStart = firstEvent[0]?.event_time ? istDay(firstEvent[0].event_time) : null;
  const dataEnd = lastEvent[0]?.event_time ? istDay(lastEvent[0].event_time) : null;
  const available =
    !params.from && !params.to
      ? true
      : !!(
          dataStart &&
          dataEnd &&
          (!params.to || params.to >= dataStart) &&
          (!params.from || params.from <= dataEnd)
        );

  const clientIds = new Set(clientRows.map(row => text(row.company_id)).filter(Boolean));
  const directory = new Map(directoryRows.map(row => [text(row.company_uuid), row]));
  const eventNames = new Map<string, string>();
  for (const row of nameRows) {
    if (text(row.company_id) && text(row.event_name)) {
      eventNames.set(text(row.company_id), text(row.event_name));
    }
  }
  const displayName = (id: string): string =>
    text(directory.get(id)?.company_name) || eventNames.get(id) || id;

  const integrationRows = await readAll<{
    company_id: string;
    event_time: string;
    insert_id: string;
    properties: Record<string, unknown> | null;
  }>(
    "events",
    "company_id,event_time,insert_id,properties",
    "&event_name=eq.Integration%20status&company_id=not.is.null&order=event_time.desc",
    10_000,
    signal,
  );
  const integrations = new Map<string, string>();
  for (const row of integrationRows) {
    const id = text(row.company_id);
    if (!clientIds.has(id) || integrations.has(id)) continue;
    const properties = row.properties ?? {};
    if (!["success", "successful"].includes(text(properties.status).toLowerCase())) continue;
    const type = text(properties.type).toLowerCase();
    integrations.set(
      id,
      type === "tally" ? "Tally" : type === "zoho" || type === "zoho books" ? "Zoho Books" : "Unknown",
    );
  }

  type Member = { id: string; email: string; totals: Totals };
  const usageByCompany = new Map<string, { totals: Totals; users: Map<string, Member> }>();
  for (const id of clientIds) usageByCompany.set(id, { totals: emptyTotals(), users: new Map() });
  for (const row of memberRows) {
    const company = usageByCompany.get(text(row.company_id));
    const key = text(row.user_key);
    if (!company || !key || company.users.has(key)) continue;
    company.users.set(key, { id: key, email: text(row.user_email) || key, totals: emptyTotals() });
  }
  for (const row of usageRows) {
    const company = usageByCompany.get(text(row.company_id));
    if (!company || typeof row.events !== "number") continue;
    const module = text(row.module) as ModuleKey;
    if (!MODULES.some(entry => entry.key === module)) continue;
    company.totals[module] += row.events;
    const key = row.user_key == null ? UNATTRIBUTED_ID : text(row.user_key) || UNATTRIBUTED_ID;
    let user = company.users.get(key);
    if (!user) {
      user = {
        id: key,
        email: key === UNATTRIBUTED_ID ? UNATTRIBUTED_LABEL : key,
        totals: emptyTotals(),
      };
      company.users.set(key, user);
    }
    user.totals[module] += row.events;
  }

  const sign = params.direction === "asc" ? 1 : -1;
  const companies = [...clientIds]
    .map(id => ({
      id,
      name: displayName(id),
      is_test: directory.get(id)?.is_test === true,
      integration: integrations.get(id) || "Unknown",
      totals: usageByCompany.get(id)!.totals,
    }))
    .filter(company => {
      if (search) {
        const users = usageByCompany.get(company.id)?.users.values() ?? [];
        const emailHit = [...users].some(user => user.email.toLowerCase().includes(search));
        if (!company.name.toLowerCase().includes(search) && !emailHit) return false;
      }
      if (params.integration !== "all" && company.integration !== params.integration) return false;
      const total = companyTotal(company.totals);
      if (params.usage === "active" && total === 0) return false;
      if (params.usage === "inactive" && total > 0) return false;
      return true;
    })
    .sort((a, b) => {
      if (params.sort === "name") {
        return (a.name.localeCompare(b.name) || a.id.localeCompare(b.id)) * sign;
      }
      const diff = a.totals[params.sort] - b.totals[params.sort];
      return (diff === 0 ? (a.id < b.id ? -1 : a.id > b.id ? 1 : 0) : diff) * sign;
    });

  const page = Math.max(1, params.page || 1);
  const visible = companies.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
  const rows: CompanyUsageRow[] = visible.map(company => ({
    ...company,
    users: [...usageByCompany.get(company.id)!.users.values()]
      .sort((a, b) => a.email.localeCompare(b.email) || a.id.localeCompare(b.id))
      .map((user): CompanyUsageUser => ({ id: user.id, email: user.email, totals: user.totals })),
  }));
  return {
    rows,
    total: companies.length,
    page,
    page_size: PAGE_SIZE,
    available,
    data_start: dataStart,
    data_end: dataEnd,
    source_watermark_at: watermark[0]?.last_success_at ?? null,
  };
}

export interface BreakdownParams {
  signal?: AbortSignal;
  company_id: string;
  user_id: string | null;
  module: ModuleKey;
  from: string | null;
  to: string | null;
}

export async function companyBreakdown(params: BreakdownParams): Promise<ModuleBreakdownResponse> {
  const userKey =
    params.user_id == null ? null : params.user_id === UNATTRIBUTED_ID ? "" : params.user_id;
  const [grouped, directoryRows, userEmails, fallbackNames] = await Promise.all([
    rpc<
      Array<{
        event: string;
        subtype: string | null;
        status: string | null;
        events: number;
        items: number | null;
        instrumented: number;
        latest_at: string | null;
      }>
    >("read_companies_breakdown", {
      p_company_id: params.company_id,
      p_module: params.module,
      p_user_key: userKey,
      p_from: params.from,
      p_to: params.to,
    }),
    rest<Array<{ company_name: string }>>(
      `/company_directory?select=company_name&company_uuid=eq.${encodeURIComponent(params.company_id)}&limit=1`,
    ),
    params.user_id == null || params.user_id === UNATTRIBUTED_ID
      ? Promise.resolve([] as Array<{ email: string }>)
      : rest<Array<{ email: string }>>(
          `/events?select=email&company_id=eq.${encodeURIComponent(params.company_id)}&distinct_id=eq.${encodeURIComponent(params.user_id)}&email=not.is.null&email=neq.&order=event_time.desc&limit=5`,
        ),
    rpc<Array<{ company_id: string; event_name: string }>>("read_company_names", {
      p_company_id: params.company_id,
    }),
  ]);
  const rows = grouped
    .map(row => ({
      event: text(row.event),
      subtype: text(row.subtype) || null,
      status: text(row.status) || null,
      count: Number(row.events) || 0,
      items: Number(row.instrumented) > 0 ? Number(row.items) || 0 : null,
      latest_at: row.latest_at ?? null,
    }))
    .sort((a, b) => b.count - a.count || a.event.localeCompare(b.event));
  const total = rows.reduce((sum, row) => sum + row.count, 0);
  const instrumented = rows.filter(row => row.items != null);
  const directoryName = text(directoryRows[0]?.company_name);
  const eventName = text(fallbackNames[0]?.event_name);
  const userEmail = text(
    userEmails.map(row => row.email).find(email => !isInternalEmail(text(email))),
  );
  return {
    company_id: params.company_id,
    company_name: directoryName || eventName || params.company_id,
    user_id: params.user_id,
    user_label:
      params.user_id == null
        ? null
        : params.user_id === UNATTRIBUTED_ID
          ? UNATTRIBUTED_LABEL
          : userEmail || params.user_id,
    module: params.module,
    total,
    item_total: instrumented.length
      ? instrumented.reduce((sum, row) => sum + (row.items ?? 0), 0)
      : null,
    rows,
  };
}
