import {
  moduleFor,
  UNATTRIBUTED_ID,
  UNATTRIBUTED_LABEL,
  usableCompanyName,
} from "../companies/modules";
import type {
  ActivationCompanyDetail,
  ActivationCompanyRow,
  ActivationDetailUser,
  ActivationEvidenceRow,
  ActivationListResponse,
  ActivationModuleTotals,
  ActivationStatus,
  ActivationUserRow,
  ActivationWeekRow,
} from "./drill-types";

interface RawEvent {
  insert_id: string;
  event_name: string;
  event_time: string;
  distinct_id: string | null;
  email: string | null;
  company_id: string | null;
  company: string | null;
  properties: Record<string, unknown> | null;
}

interface IntegrationSeed {
  id: string;
  integration_at: string;
  integration: string;
  event: RawEvent;
}

const INTERNAL_DOMAINS = ["aiaccountant.com", "korefi.ai", "karboncard.com"];
const RELEVANT_EVENTS = [
  "Accounting Sync", "Upload", "Entity Created", "Invoice Bulk Edited",
  "Vendor Mismatch Resolved", "Invoice Created", "Download-Inv", "Preview",
  "Transaction Ledger Updated", "Transaction Status", "Transaction Type Updated",
  "Transaction Configuration Edited", "Download", "Delete", "Export",
  "Recon Processed",
];

const text = (value: unknown): string =>
  typeof value === "string" ? value.trim() : "";

function credentials(): { url: string; key: string } {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("supabase_unavailable");
  return { url, key };
}

function isRetentionInternalEmail(email: string | null | undefined): boolean {
  let raw = text(email).toLowerCase();
  if (!raw) return false;
  const open = raw.lastIndexOf("<");
  const close = raw.lastIndexOf(">");
  if (open >= 0 && close > open) raw = raw.slice(open + 1, close).trim();
  const at = raw.lastIndexOf("@");
  if (at < 0) return false;
  const domain = raw.slice(at + 1);
  return INTERNAL_DOMAINS.some(
    item => domain === item || domain.endsWith("." + item),
  );
}

function eventProps(event: RawEvent): Record<string, unknown> {
  return event.properties ?? {};
}

function successfulIntegration(event: RawEvent): boolean {
  if (event.event_name !== "Integration status") return false;
  if (isRetentionInternalEmail(event.email)) return false;
  const status = text(eventProps(event).status).toLowerCase();
  const type = text(eventProps(event).type).toLowerCase();
  return ["success", "successful"].includes(status) &&
    ["tally", "zoho"].includes(type);
}

function integrationLabel(event: RawEvent): string {
  const type = text(eventProps(event).type).toLowerCase();
  return type === "tally" ? "Tally" : type === "zoho" ? "Zoho Books" : "Unknown";
}

function qualifyingSync(event: RawEvent): boolean {
  if (event.event_name !== "Accounting Sync") return false;
  const items = eventProps(event).items_count;
  return typeof items === "number" && Number.isFinite(items) && items > 0;
}

function coreActivity(event: RawEvent): boolean {
  const p = eventProps(event);
  const type = text(p.type).toLowerCase();
  const entity = text(p.entityType).toLowerCase();
  if (event.event_name === "Upload" &&
      ["bill", "invoice", "statement"].includes(type)) return true;
  if (event.event_name === "Entity Created" &&
      ["bill", "invoice"].includes(entity)) return true;
  return [
    "Invoice Bulk Edited", "Transaction Ledger Updated", "Transaction Status",
    "Transaction Type Updated", "Transaction Configuration Edited",
    "Vendor Mismatch Resolved", "Accounting Sync",
  ].includes(event.event_name);
}

function independentCoreJob(event: RawEvent): boolean {
  if (!coreActivity(event) || event.event_name === "Accounting Sync") return false;
  return text(eventProps(event).status).toLowerCase() !== "failed";
}

function emptyTotals(): ActivationModuleTotals {
  return { ap: 0, ar: 0, transactions: 0, gst: 0 };
}

function totalsWithSync(): ActivationModuleTotals & { sync: number } {
  return { ap: 0, ar: 0, transactions: 0, gst: 0, sync: 0 };
}

function addModule(
  target: ActivationModuleTotals | (ActivationModuleTotals & { sync: number }),
  event: RawEvent,
) {
  const module = moduleFor(event.event_name, eventProps(event));
  if (!module) return;
  if (module === "sync") {
    if ("sync" in target) target.sync += 1;
    return;
  }
  target[module] += 1;
}

function istDateKey(value: string): string {
  return new Date(value).toLocaleDateString("en-CA", {
    timeZone: "Asia/Kolkata",
  });
}

function toMillis(value: string | null | undefined): number {
  const ms = value ? Date.parse(value) : Number.NaN;
  return Number.isFinite(ms) ? ms : Number.NaN;
}

function addDays(date: string, amount: number): string {
  const d = new Date(date + "T12:00:00Z");
  d.setUTCDate(d.getUTCDate() + amount);
  return d.toISOString().slice(0, 10);
}

function mondayFor(date: string): string {
  const d = new Date(date + "T12:00:00Z");
  return addDays(date, -((d.getUTCDay() + 6) % 7));
}

function lastCompleteWeeks(count = 8): Array<{ start: string; end: string }> {
  const today = new Date().toLocaleDateString("en-CA", {
    timeZone: "Asia/Kolkata",
  });
  const currentMonday = mondayFor(today);
  return Array.from({ length: count }, (_, index) => {
    const start = addDays(currentMonday, -7 * (count - index));
    return { start, end: addDays(start, 6) };
  });
}

function statusFor(
  training: RawEvent | null,
  core: RawEvent | null,
  activation: RawEvent | null,
): ActivationStatus {
  if (activation) return "activated";
  if (core) return "awaiting_sync";
  if (training) return "no_core";
  return "no_training";
}

function lifecycle(seed: IntegrationSeed, allEvents: RawEvent[]) {
  const integrationMs = toMillis(seed.integration_at);
  const relevant = allEvents
    .filter(event => event.company_id === seed.id)
    .filter(event => !isRetentionInternalEmail(event.email))
    .filter(event => toMillis(event.event_time) >= integrationMs)
    .sort((a, b) =>
      toMillis(a.event_time) - toMillis(b.event_time) ||
      a.insert_id.localeCompare(b.insert_id)
    );

  const training = relevant.find(qualifyingSync) ?? null;
  const trainingDay = training ? istDateKey(training.event_time) : null;
  const core = training && trainingDay
    ? relevant.find(event =>
        istDateKey(event.event_time) > trainingDay &&
        independentCoreJob(event)
      ) ?? null
    : null;
  const activation = core
    ? relevant.find(event =>
        toMillis(event.event_time) > toMillis(core.event_time) &&
        qualifyingSync(event)
      ) ?? null
    : null;

  return { relevant, training, trainingDay, core, activation };
}

function latestEmail(events: RawEvent[]): string {
  for (let index = events.length - 1; index >= 0; index -= 1) {
    const email = text(events[index].email);
    if (email && !isRetentionInternalEmail(email)) return email;
  }
  return "";
}

function activationWindow(
  seed: IntegrationSeed,
  allEvents: RawEvent[],
  trainingDay: string | null,
  activation: RawEvent | null,
): RawEvent[] {
  if (!trainingDay) return [];
  const end = activation ? toMillis(activation.event_time) : Number.POSITIVE_INFINITY;
  return allEvents
    .filter(event => event.company_id === seed.id)
    .filter(event => !isRetentionInternalEmail(event.email))
    .filter(event => istDateKey(event.event_time) > trainingDay)
    .filter(event => toMillis(event.event_time) <= end)
    .sort((a, b) =>
      toMillis(a.event_time) - toMillis(b.event_time) ||
      a.insert_id.localeCompare(b.insert_id)
    );
}

function aggregateWindow(
  windowEvents: RawEvent[],
): { totals: ActivationModuleTotals; users: ActivationUserRow[] } {
  const totals = emptyTotals();
  const users = new Map<
    string,
    { events: RawEvent[]; totals: ActivationModuleTotals }
  >();

  for (const event of windowEvents) {
    const module = moduleFor(event.event_name, eventProps(event));
    const id = text(event.distinct_id) || (module ? UNATTRIBUTED_ID : "");
    if (id) {
      let user = users.get(id);
      if (!user) {
        user = { events: [], totals: emptyTotals() };
        users.set(id, user);
      }
      user.events.push(event);
      if (module && module !== "sync") user.totals[module] += 1;
    }
    if (module && module !== "sync") totals[module] += 1;
  }

  return {
    totals,
    users: [...users.entries()]
      .map(([id, user]) => ({
        id,
        email: id === UNATTRIBUTED_ID
          ? UNATTRIBUTED_LABEL
          : latestEmail(user.events) || id,
        totals: user.totals,
      }))
      .sort((a, b) =>
        Number(a.id === UNATTRIBUTED_ID) - Number(b.id === UNATTRIBUTED_ID) ||
        a.email.localeCompare(b.email)
      ),
  };
}

type QueryPair = [string, string];

async function restRows<T>(
  table: string,
  query: QueryPair[],
  signal?: AbortSignal,
  maxRows = 50_000,
): Promise<T[]> {
  const auth = credentials();
  const pageSize = 1000;
  const rows: T[] = [];

  for (let offset = 0; offset < maxRows; offset += pageSize) {
    const params = new URLSearchParams();
    for (const pair of query) params.append(pair[0], pair[1]);
    params.set("limit", String(pageSize));
    params.set("offset", String(offset));

    const response = await fetch(
      auth.url + "/rest/v1/" + table + "?" + params.toString(),
      {
        cache: "no-store",
        signal,
        headers: {
          apikey: auth.key,
          Authorization: "Bearer " + auth.key,
          "Cache-Control": "no-cache",
          Pragma: "no-cache",
        },
      },
    );

    if (!response.ok) {
      const detail = await response.text().catch(() => "");
      throw new Error(
        "supabase_" + response.status + ":" + table + ":" + detail.slice(0, 160),
      );
    }

    const page = (await response.json()) as T[];
    rows.push(...page);
    if (page.length < pageSize) return rows;
  }

  throw new Error("retention_drill_truncated:" + table);
}

function quoteIn(values: string[]): string {
  return "in.(" +
    values.map(value => '"' + value.replaceAll('"', '\\"') + '"').join(",") +
    ")";
}

function chunks<T>(items: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let index = 0; index < items.length; index += size)
    result.push(items.slice(index, index + size));
  return result;
}

async function integrationSeeds(signal?: AbortSignal): Promise<IntegrationSeed[]> {
  const result = await Promise.all([
    restRows<RawEvent>(
      "events",
      [
        ["select", "insert_id,event_name,event_time,distinct_id,email,company_id,company,properties"],
        ["event_name", "eq.Integration status"],
        ["order", "event_time.asc,insert_id.asc"],
      ],
      signal,
      5000,
    ),
    restRows<{ company_id: string }>(
      "client_company",
      [["select", "company_id"]],
      signal,
      5000,
    ),
  ]);
  const events = result[0];
  const clients = result[1];

  const clientIds = new Set(clients.map(row => row.company_id));
  const byCompany = new Map<string, IntegrationSeed>();
  for (const event of events) {
    const id = text(event.company_id);
    if (!id || !clientIds.has(id) || !successfulIntegration(event)) continue;
    if (byCompany.has(id)) continue;
    byCompany.set(id, {
      id,
      integration_at: event.event_time,
      integration: integrationLabel(event),
      event,
    });
  }
  return [...byCompany.values()];
}

async function directoryFor(
  ids: string[],
  signal?: AbortSignal,
): Promise<Map<string, { company_name: string; is_test: boolean }>> {
  const valid = ids.filter(id =>
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)
  );
  const result = new Map<string, { company_name: string; is_test: boolean }>();
  for (const batch of chunks(valid, 100)) {
    const rows = await restRows<{
      company_uuid: string;
      company_name: string | null;
      is_test: boolean | null;
    }>(
      "company_directory",
      [
        ["select", "company_uuid,company_name,is_test"],
        ["company_uuid", "in.(" + batch.join(",") + ")"],
      ],
      signal,
      1000,
    );
    for (const row of rows) {
      result.set(row.company_uuid, {
        company_name: text(row.company_name),
        is_test: Boolean(row.is_test),
      });
    }
  }
  return result;
}

async function eventsForSeeds(
  seeds: IntegrationSeed[],
  signal?: AbortSignal,
): Promise<RawEvent[]> {
  const all: RawEvent[] = [];
  for (const batch of chunks(seeds, 30)) {
    const ids = batch.map(seed => seed.id);
    const earliest = [...batch]
      .sort((a, b) => toMillis(a.integration_at) - toMillis(b.integration_at))[0]
      ?.integration_at;
    if (!earliest) continue;
    const rows = await restRows<RawEvent>(
      "events",
      [
        ["select", "insert_id,event_name,event_time,distinct_id,email,company_id,company,properties"],
        ["company_id", "in.(" + ids.join(",") + ")"],
        ["event_time", "gte." + earliest],
        ["event_name", quoteIn(RELEVANT_EVENTS)],
        ["order", "event_time.asc,insert_id.asc"],
      ],
      signal,
      25_000,
    );
    all.push(...rows);
  }
  return all;
}

function seedName(
  seed: IntegrationSeed,
  directory: Map<string, { company_name: string; is_test: boolean }>,
  events: RawEvent[],
): string {
  const fromDirectory = directory.get(seed.id)?.company_name;
  if (fromDirectory) return fromDirectory;

  const candidates = [...events]
    .filter(event => event.company_id === seed.id)
    .sort((a, b) => toMillis(b.event_time) - toMillis(a.event_time));
  for (const event of candidates) {
    const value =
      usableCompanyName(event.company) ??
      usableCompanyName(text(eventProps(event).companyName));
    if (value) return value;
  }

  return usableCompanyName(seed.event.company) || seed.id;
}

export async function readActivationPreviewList(params: {
  from: string | null;
  to: string | null;
  query: string;
  signal?: AbortSignal;
}): Promise<ActivationListResponse> {
  const seeds = await integrationSeeds(params.signal);
  const fromMs = params.from
    ? Date.parse(params.from + "T00:00:00+05:30")
    : Number.NEGATIVE_INFINITY;
  const toMsExclusive = params.to
    ? Date.parse(params.to + "T00:00:00+05:30") + 86_400_000
    : Number.POSITIVE_INFINITY;

  let cohort = seeds.filter(seed => {
    const at = toMillis(seed.integration_at);
    return at >= fromMs && at < toMsExclusive;
  });

  const directory = await directoryFor(cohort.map(seed => seed.id), params.signal);
  const names = new Map(
    cohort.map(seed => [
      seed.id,
      directory.get(seed.id)?.company_name ||
        usableCompanyName(seed.event.company) ||
        seed.id,
    ]),
  );

  const needle = params.query.trim().toLowerCase();
  if (needle) {
    cohort = cohort.filter(seed =>
      (names.get(seed.id) ?? seed.id).toLowerCase().includes(needle)
    );
  }

  cohort.sort((a, b) =>
    toMillis(b.integration_at) - toMillis(a.integration_at) ||
    a.id.localeCompare(b.id)
  );

  const total = cohort.length;
  const selected = cohort.slice(0, 80);
  const events = await eventsForSeeds(selected, params.signal);

  const rows: ActivationCompanyRow[] = selected.map(seed => {
    const flow = lifecycle(seed, events);
    const windowEvents = activationWindow(
      seed, events, flow.trainingDay, flow.activation,
    );
    const usage = aggregateWindow(windowEvents);
    const activatedAt = flow.activation?.event_time ?? null;

    return {
      id: seed.id,
      name: seedName(seed, directory, events),
      is_test: directory.get(seed.id)?.is_test ?? false,
      integration: seed.integration,
      integration_at: seed.integration_at,
      training_sync_at: flow.training?.event_time ?? null,
      post_training_core_at: flow.core?.event_time ?? null,
      activated_at: activatedAt,
      status: statusFor(flow.training, flow.core, flow.activation),
      ttv_hours: activatedAt == null
        ? null
        : (toMillis(activatedAt) - toMillis(seed.integration_at)) / 3_600_000,
      totals: usage.totals,
      users: usage.users,
    };
  });

  return {
    rows,
    total,
    loaded: rows.length,
    sampled: total > rows.length,
  };
}

async function allCompanyEvents(
  companyId: string,
  signal?: AbortSignal,
): Promise<RawEvent[]> {
  return restRows<RawEvent>(
    "events",
    [
      ["select", "insert_id,event_name,event_time,distinct_id,email,company_id,company,properties"],
      ["company_id", "eq." + companyId],
      ["order", "event_time.asc,insert_id.asc"],
    ],
    signal,
    30_000,
  );
}

function evidenceModule(event: RawEvent): ActivationEvidenceRow["module"] | null {
  const module = moduleFor(event.event_name, eventProps(event));
  if (module === "ap") return "AP";
  if (module === "ar") return "AR";
  if (module === "transactions") return "Transaction";
  if (module === "gst") return "GST";
  if (module === "sync") return "Sync";
  return null;
}

function recentUsers(
  events: RawEvent[],
  integrationAt: string,
  weekDefs: Array<{ start: string; end: string }>,
  core: RawEvent | null,
  activation: RawEvent | null,
): ActivationDetailUser[] {
  const start = weekDefs[0]?.start;
  const end = weekDefs.at(-1)?.end;
  const users = new Map<
    string,
    {
      events: RawEvent[];
      recent: ActivationModuleTotals & { sync: number };
      first: string;
      last: string;
    }
  >();

  for (const event of events) {
    if (isRetentionInternalEmail(event.email)) continue;
    if (toMillis(event.event_time) < toMillis(integrationAt)) continue;
    const module = moduleFor(event.event_name, eventProps(event));
    const id = text(event.distinct_id) || (module ? UNATTRIBUTED_ID : "");
    if (!id) continue;

    let user = users.get(id);
    if (!user) {
      user = {
        events: [],
        recent: totalsWithSync(),
        first: event.event_time,
        last: event.event_time,
      };
      users.set(id, user);
    }

    user.events.push(event);
    if (toMillis(event.event_time) < toMillis(user.first)) user.first = event.event_time;
    if (toMillis(event.event_time) > toMillis(user.last)) user.last = event.event_time;

    const date = istDateKey(event.event_time);
    if (start && end && date >= start && date <= end) addModule(user.recent, event);
  }

  return [...users.entries()]
    .map(([id, user]) => {
      const didCore = Boolean(core && text(core.distinct_id) === id);
      const didSync = Boolean(activation && text(activation.distinct_id) === id);
      const role =
        didCore && didSync ? "both" :
        didCore ? "core_job" :
        didSync ? "closing_sync" : null;
      return {
        id,
        email: id === UNATTRIBUTED_ID
          ? UNATTRIBUTED_LABEL
          : latestEmail(user.events) || id,
        first_seen_at: user.first,
        last_seen_at: user.last,
        activation_role: role,
        recent_totals: user.recent,
      } satisfies ActivationDetailUser;
    })
    .sort((a, b) =>
      Number(a.id === UNATTRIBUTED_ID) - Number(b.id === UNATTRIBUTED_ID) ||
      a.email.localeCompare(b.email)
    );
}

export async function readActivationCompanyDetail(params: {
  companyId: string;
  signal?: AbortSignal;
}): Promise<ActivationCompanyDetail> {
  const events = (await allCompanyEvents(params.companyId, params.signal))
    .filter(event => !isRetentionInternalEmail(event.email));

  const firstIntegration = events.find(successfulIntegration);
  if (!firstIntegration) throw new Error("activation_company_not_integrated");

  const seed: IntegrationSeed = {
    id: params.companyId,
    integration_at: firstIntegration.event_time,
    integration: integrationLabel(firstIntegration),
    event: firstIntegration,
  };
  const flow = lifecycle(seed, events);
  const directory = await directoryFor([params.companyId], params.signal);
  const name = seedName(seed, directory, events);
  const signup = events.find(event => event.event_name === "Company Created") ?? events[0];
  if (!signup) throw new Error("activation_company_empty");

  const weekDefs = lastCompleteWeeks(8);
  const weeks: ActivationWeekRow[] = weekDefs.map(period => {
    const totals = totalsWithSync();
    for (const event of events) {
      const date = istDateKey(event.event_time);
      if (date >= period.start && date <= period.end) addModule(totals, event);
    }
    return { week_start: period.start, week_end: period.end, totals };
  });

  const recentStart = weekDefs[0]?.start;
  const recentEnd = weekDefs.at(-1)?.end;
  const activeWeekKeys = new Set<string>();
  let moduleEvents8 = 0;
  let lastCore: RawEvent | null = null;

  for (const event of events) {
    if (
      coreActivity(event) &&
      (!flow.activation ||
        toMillis(event.event_time) >= toMillis(flow.activation.event_time))
    ) {
      lastCore = event;
      const date = istDateKey(event.event_time);
      if (recentStart && recentEnd && date >= recentStart && date <= recentEnd)
        activeWeekKeys.add(mondayFor(date));
    }

    const date = istDateKey(event.event_time);
    if (
      recentStart && recentEnd &&
      date >= recentStart && date <= recentEnd &&
      moduleFor(event.event_name, eventProps(event))
    ) moduleEvents8 += 1;
  }

  let evidenceEvents: RawEvent[] = [];
  if (flow.trainingDay) {
    evidenceEvents = events.filter(event => {
      if (istDateKey(event.event_time) <= flow.trainingDay!) return false;
      if (
        flow.activation &&
        toMillis(event.event_time) > toMillis(flow.activation.event_time)
      ) return false;
      return moduleFor(event.event_name, eventProps(event)) != null;
    }).slice(0, 10);

    if (
      flow.activation &&
      !evidenceEvents.some(event => event.insert_id === flow.activation?.insert_id)
    ) evidenceEvents = evidenceEvents.slice(0, 9).concat(flow.activation);
  }

  const evidence: ActivationEvidenceRow[] = [];
  for (const event of evidenceEvents) {
    const module = evidenceModule(event);
    if (!module) continue;
    evidence.push({
      at: event.event_time,
      event: event.event_name,
      module,
      user: latestEmail([event]) || text(event.distinct_id) || null,
    });
  }

  const users = recentUsers(
    events, seed.integration_at, weekDefs, flow.core, flow.activation,
  );

  return {
    id: params.companyId,
    name,
    is_test: directory.get(params.companyId)?.is_test ?? false,
    integration: seed.integration,
    signup_at: signup.event_time,
    signup_kind: signup.event_name === "Company Created" ? "Company Created" : "First seen",
    integration_at: seed.integration_at,
    training_sync_at: flow.training?.event_time ?? null,
    post_training_core_at: flow.core?.event_time ?? null,
    activated_at: flow.activation?.event_time ?? null,
    ttv_hours: flow.activation == null
      ? null
      : (toMillis(flow.activation.event_time) - toMillis(seed.integration_at)) / 3_600_000,
    last_core_activity_at: lastCore?.event_time ?? null,
    observed_users: users.length,
    active_weeks_8: activeWeekKeys.size,
    module_events_8: moduleEvents8,
    evidence,
    users,
    weeks,
  };
}
