import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createRemoteJWKSet, decodeJwt, jwtVerify } from "https://esm.sh/jose@6";

// Deployed as `companies-dashboard` with verify_jwt=false: it validates the
// Vercel OIDC JWT itself before any data read. Only the Vercel deployment of
// project prj_I0L4ZpkJU4VXKV0062RV0peBvqQy can call it. The service-role key
// below lives in the function's server environment and never reaches browsers.
const VERCEL_PROJECT_ID = "prj_I0L4ZpkJU4VXKV0062RV0peBvqQy";
const VERCEL_TEAM_SLUG = "lakksith-hariies-projects-eab39a06";
const AUDIENCE = `https://vercel.com/${VERCEL_TEAM_SLUG}`;
const PAGE_SIZE = 10;
const MODULES = ["ap", "ar", "transactions", "gst", "sync"] as const;
type ModuleKey = (typeof MODULES)[number];
type Totals = Record<ModuleKey, number>;
type SortKey = "name" | ModuleKey;

const UNATTRIBUTED_ID = "__unattributed__";
const UNATTRIBUTED_LABEL = "Unattributed activity";
// Staff domains mirror public.is_internal_email so internal addresses never
// surface in labels either.
const INTERNAL_DOMAINS = ["karboncard.com", "korefi.ai", "aiaccountant.com", "korefi.com"];
const isInternalEmail = (email: string) => {
  const domain = email.toLowerCase().split("@").pop() ?? "";
  return INTERNAL_DOMAINS.some(internal => domain === internal || domain.endsWith(`.${internal}`));
};

const totals = (): Totals => ({ ap: 0, ar: 0, transactions: 0, gst: 0, sync: 0 });
const text = (value: unknown) => typeof value === "string" ? value.trim() : "";
const companyTotal = (value: Totals) =>
  value.ap + value.ar + value.transactions + value.gst + value.sync;
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json", "cache-control": "no-store" },
});
async function verifyVercel(request: Request) {
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) throw new Error("missing token");
  const token = authorization.slice(7);
  const decoded = decodeJwt(token);
  const issuer = String(decoded.iss ?? "");
  const teamIssuer = `https://oidc.vercel.com/${VERCEL_TEAM_SLUG}`;
  if (issuer !== teamIssuer && issuer !== "https://oidc.vercel.com") throw new Error("invalid issuer");
  const jwks = createRemoteJWKSet(new URL(`${issuer}/.well-known/jwks`));
  const { payload } = await jwtVerify(token, jwks, { issuer, audience: AUDIENCE });
  if (payload.project_id !== VERCEL_PROJECT_ID) throw new Error("invalid project");
}

function validSort(value: unknown): SortKey {
  return value === "name" || (MODULES as readonly string[]).includes(String(value))
    ? (value as SortKey)
    : "name";
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try { await verifyVercel(request); } catch { return json({ error: "unauthorized" }, 401); }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  let body: any;
  try { body = await request.json(); } catch { return json({ error: "invalid_json" }, 400); }

  try {
    if (body.action === "list") {
      const page = Math.max(1, Number(body.page) || 1);
      const search = text(body.query).toLowerCase();
      const integrationFilter = text(body.integration) || "all";
      const usageFilter = text(body.usage) || "all";
      const sort = validSort(body.sort);
      const direction = text(body.direction) === "desc" ? "desc" : "asc";
      const from = text(body.from) || null;
      const to = text(body.to) || null;

      // Single public reader contract. At cutover, this RPC will point to the
      // private Product schema without exposing raw tables to the Data API.
      const [contextResult, usageRows, memberRows, nameRows] = await Promise.all([
        supabase.rpc("read_companies_context").single(),
        supabase.rpc("read_companies_usage", { p_from: from, p_to: to }),
        supabase.rpc("read_company_users"),
        supabase.rpc("read_company_names", { p_company_id: null }),
      ]);
      if (contextResult.error) throw contextResult.error;
      if (usageRows.error) throw usageRows.error;
      if (memberRows.error) throw memberRows.error;
      if (nameRows.error) throw nameRows.error;

      const context = contextResult.data ?? {};
      const dataStart = text(context.data_start) || null;
      const dataEnd = text(context.data_end) || null;
      const available = !from && !to
        ? true
        : !!(dataStart && dataEnd && (!to || to >= dataStart) && (!from || from <= dataEnd));

      const clientIds = new Set<string>(
        (Array.isArray(context.clients) ? context.clients : []).map((id: unknown) => text(id)).filter(Boolean),
      );
      const directory = new Map<string, any>(
        (Array.isArray(context.directory) ? context.directory : [])
          .map((row: any) => [text(row.company_uuid), row] as const),
      );
      const integrations = new Map<string, string>();
      for (const row of Array.isArray(context.integrations) ? context.integrations : []) {
        const id = text(row.company_id);
        if (!clientIds.has(id)) continue;
        integrations.set(id, text(row.integration) || "Unknown");
      }

      // Email search is derived from the filtered aggregate population above,
      // so internal staff activity excluded by read_companies_usage can never
      // surface through search.

      // Company totals come from the SAME classified aggregate as user totals.
      // Membership comes from read_company_users (ALL observed non-internal
      // users, not just mapped ones), so zero-activity users still appear.
      // Display names: directory → latest usable event name → raw company id.
      const eventNames = new Map<string, string>();
      for (const row of nameRows.data ?? []) {
        if (text(row.company_id) && text(row.event_name)) eventNames.set(text(row.company_id), text(row.event_name));
      }
      const displayName = (id: string) =>
        text(directory.get(id)?.company_name) || eventNames.get(id) || id;
      const usageByCompany = new Map<string, { totals: Totals; users: Map<string, { id: string; email: string; totals: Totals }> }>();
      for (const id of clientIds) usageByCompany.set(id, { totals: totals(), users: new Map() });
      for (const row of memberRows.data ?? []) {
        const company = usageByCompany.get(text(row.company_id));
        const key = text(row.user_key);
        if (!company || !key) continue;
        if (!company.users.has(key)) {
          company.users.set(key, { id: key, email: text(row.user_email) || key, totals: totals() });
        }
      }
      for (const row of usageRows.data ?? []) {
        const company = usageByCompany.get(text(row.company_id));
        if (!company || typeof row.events !== "number") continue;
        const module = text(row.module) as ModuleKey;
        if (!(MODULES as readonly string[]).includes(module)) continue;
        company.totals[module] += row.events;
        const key = row.user_key == null ? UNATTRIBUTED_ID : text(row.user_key) || UNATTRIBUTED_ID;
        // Display emails come solely from the membership aggregate above;
        // the usage aggregate carries counts only.
        let user = company.users.get(key);
        if (!user) {
          // The unattributed bucket exists only to preserve mapped activity
          // with no usable identity; membership already came from above.
          user = { id: key, email: key === UNATTRIBUTED_ID ? UNATTRIBUTED_LABEL : key, totals: totals() };
          company.users.set(key, user);
        }
        user.totals[module] += row.events;
      }

      const sign = direction === "asc" ? 1 : -1;
      const companies = [...clientIds].map(id => ({
        id,
        name: displayName(id),
        is_test: directory.get(id)?.is_test === true,
        integration: integrations.get(id) || "Unknown",
        totals: usageByCompany.get(id)!.totals,
      })).filter(company => {
        if (search) {
          const users = usageByCompany.get(company.id)?.users.values() ?? [];
          const emailHit = [...users].some(user => user.email.toLowerCase().includes(search));
          if (!company.name.toLowerCase().includes(search) && !emailHit) return false;
        }
        if (integrationFilter !== "all" && company.integration !== integrationFilter) return false;
        const total = companyTotal(company.totals);
        if (usageFilter === "active" && total === 0) return false;
        if (usageFilter === "inactive" && total > 0) return false;
        return true;
      }).sort((a, b) => {
        if (sort === "name") return (a.name.localeCompare(b.name) || a.id.localeCompare(b.id)) * sign;
        const diff = a.totals[sort] - b.totals[sort];
        // Stable tie-break by company ID, never by display name.
        return (diff === 0 ? (a.id < b.id ? -1 : a.id > b.id ? 1 : 0) : diff) * sign;
      });

      const total = companies.length;
      const visible = companies.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
      const rows = visible.map(company => ({
        ...company,
        users: [...usageByCompany.get(company.id)!.users.values()]
          .sort((a, b) => a.email.localeCompare(b.email) || a.id.localeCompare(b.id)),
      }));
      return json({
        rows, total, page, page_size: PAGE_SIZE, available,
        data_start: dataStart, data_end: dataEnd,
        source_watermark_at: context.watermark ?? null,
      });
    }

    if (body.action === "breakdown") {
      const companyId = text(body.company_id);
      const rawUser = body.user_id == null ? null : text(body.user_id);
      const module = text(body.module) as ModuleKey;
      const from = text(body.from) || null;
      const to = text(body.to) || null;
      if (!companyId || !MODULES.includes(module)) return json({ error: "invalid_parameters" }, 400);
      // The unattributed sentinel maps to an empty key, which the SQL matches
      // to events with no usable distinct_id (NULL IS NOT DISTINCT FROM NULL).
      const userKey = rawUser == null ? null : rawUser === UNATTRIBUTED_ID ? "" : rawUser;

      const { data, error } = await supabase.rpc("read_companies_breakdown", {
        p_company_id: companyId, p_module: module, p_user_key: userKey, p_from: from, p_to: to,
      });
      if (error) throw error;
      const grouped = (data ?? []).map((row: any) => ({
        event: text(row.event),
        subtype: text(row.subtype) || null,
        status: text(row.status) || null,
        count: Number(row.events) || 0,
        // Unavailable item volume stays unavailable; never invented as zero.
        items: Number(row.instrumented) > 0 ? Number(row.items) || 0 : null,
        latest_at: row.latest_at ?? null,
      })).sort((a: any, b: any) => b.count - a.count || a.event.localeCompare(b.event));

      const [contextResult, memberResult, fallbackName] = await Promise.all([
        supabase.rpc("read_companies_context").single(),
        rawUser == null || rawUser === UNATTRIBUTED_ID
          ? Promise.resolve({ data: [], error: null })
          : supabase.rpc("read_company_users"),
        supabase.rpc("read_company_names", { p_company_id: companyId }),
      ]);
      if (contextResult.error) throw contextResult.error;
      if (memberResult.error) throw memberResult.error;
      if (fallbackName.error) throw fallbackName.error;
      const context = contextResult.data ?? {};
      const directory = Array.isArray(context.directory)
        ? context.directory.find((row: any) => text(row.company_uuid) === companyId)
        : null;
      const directoryName = text(directory?.company_name);
      const eventName = Array.isArray(fallbackName.data)
        ? text(fallbackName.data[0]?.event_name)
        : "";
      // Membership is already staff-filtered and is schema-independent.
      const members = Array.isArray(memberResult.data) ? memberResult.data : [];
      const userEmail = text(members.find((row: any) =>
        text(row.company_id) === companyId && text(row.user_key) === rawUser &&
        !isInternalEmail(text(row.user_email)),
      )?.user_email);
      const total = grouped.reduce((sum: number, row: any) => sum + row.count, 0);
      const instrumented = grouped.filter((row: any) => row.items != null);
      return json({
        company_id: companyId,
        company_name: directoryName || eventName || companyId,
        user_id: rawUser,
        user_label: rawUser == null ? null : rawUser === UNATTRIBUTED_ID ? UNATTRIBUTED_LABEL :
          userEmail || rawUser,
        module,
        total,
        item_total: instrumented.length ? instrumented.reduce((sum: number, row: any) => sum + row.items, 0) : null,
        rows: grouped,
      });
    }
    return json({ error: "unknown_action" }, 400);
  } catch (error) {
    console.error("companies-dashboard", error instanceof Error ? error.message : String(error));
    return json({ error: "data_unavailable" }, 503);
  }
});
