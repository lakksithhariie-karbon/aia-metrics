export const MAX_NON_EMPTY_LINES = 100_000;
export const EVENT_PROPERTIES_VERSION = "event_properties.v1.2";

export type JsonObject = Record<string, unknown>;

type PropertyKind =
  | "nullable_text"
  | "lower_text"
  | "nullable_lower_text"
  | "text"
  | "type"
  | "subtype"
  | "status"
  | "transaction_type"
  | "boolean"
  | "number"
  | "string_array"
  | "scalar_state";

// The event-property contract, declared once. Must stay identical, in key and
// order, to fetcher/parse.py and to public.normalize_event_properties.
// Contract: docs/specs/2026-09-13-event-property-contract-v1_1.md
//
// v1 keys are global: any event may carry them. `items_count` is a global v1
// key and must stay accepted on ANY event, exactly as deployed v1 does. Product
// logic (qualifying sync / activation) may consume it only on `Accounting Sync`,
// but that is a consumer rule, not an ingest rule: narrowing the gate here would
// silently drop a valid producer key on other events.
export const V1_PROPERTY_KINDS: ReadonlyArray<readonly [string, PropertyKind]> = [
  ["companyName", "text"],
  ["type", "type"],
  ["subType", "subtype"],
  ["status", "status"],
  ["fileType", "text"],
  ["source", "text"],
  ["entityType", "text"],
  ["transactionType", "transaction_type"],
  ["action", "text"],
  ["productCode", "text"],
  ["widgetName", "text"],
  ["flow", "text"],
  ["method", "text"],
  ["viewSource", "text"],
  ["isReactivation", "boolean"],
  ["items_count", "number"],
];

// v1.1 additions are EVENT-SCOPED, not global. A property is only admitted on
// its declared event. `Accounting Sync` accepts `sync_items`; the camel-case
// counts are deliberately not scoped to it, because `items_count` (the global
// v1 key above) is the sole qualifying-count field.
export const V1_1_PROPERTY_KINDS: ReadonlyArray<
  readonly [string, string, PropertyKind]
> = [
  ["Accounting Sync", "sync_items", "string_array"],
  ["Transaction Status", "itemsCount", "number"],
  ["Transaction Ledger Updated", "transactionCount", "number"],
  ["Transaction Type Updated", "transactionCount", "number"],
  ["Vendor Mismatch Resolved", "resolutionType", "text"],
  ["Transaction Configuration Edited", "configField", "text"],
  ["Transaction Configuration Edited", "previousState", "scalar_state"],
  ["Transaction Configuration Edited", "newState", "scalar_state"],
];

export const V1_2_PROPERTY_KINDS: ReadonlyArray<readonly [string, string, PropertyKind]> = [
  ["Billing Intent Claimed", "outcome", "lower_text"],
  ["Billing Intent Claimed", "stage", "lower_text"],
  ["Billing Intent Created", "outcome", "lower_text"],
  ["Billing Intent Created", "stage", "lower_text"],
  ["Billing Intent Refreshed", "outcome", "lower_text"],
  ["Billing Intent Refreshed", "stage", "lower_text"],
  ["Billing Intent Reserved", "billingExpected", "boolean"],
  ["Billing Intent Reserved", "outcome", "lower_text"],
  ["Billing Intent Reserved", "stage", "lower_text"],
  ["Company Created", "createdBy", "text"],
  ["Company Created", "userUuid", "text"],
  ["Company Switched", "fromCompanyId", "text"],
  ["Company Switched", "organisationId", "nullable_text"],
  ["Company Switched", "toCompanyId", "text"],
  ["Company Switched", "toolConnected", "nullable_lower_text"],
  ["Duplicate Phone Attempt", "outcome", "lower_text"],
  ["Duplicate Phone Attempt", "reason", "lower_text"],
  ["Duplicate Phone Attempt", "stage", "lower_text"],
  ["Login", "billingExpected", "boolean"],
  ["Phone OTP Failed", "attemptsRemaining", "number"],
  ["Phone OTP Failed", "outcome", "lower_text"],
  ["Phone OTP Failed", "reason", "lower_text"],
  ["Phone OTP Failed", "stage", "lower_text"],
  ["Phone OTP Resent", "outcome", "lower_text"],
  ["Phone OTP Resent", "stage", "lower_text"],
  ["Phone OTP Sent", "outcome", "lower_text"],
  ["Phone OTP Sent", "stage", "lower_text"],
  ["Phone OTP Verification Attempted", "outcome", "lower_text"],
  ["Phone OTP Verification Attempted", "stage", "lower_text"],
  ["Phone Verification Completed", "outcome", "lower_text"],
  ["Phone Verification Completed", "stage", "lower_text"],
  ["Phone Verification Locked", "outcome", "lower_text"],
  ["Phone Verification Locked", "reason", "lower_text"],
  ["Phone Verification Locked", "stage", "lower_text"],
  ["Phone Verification Required", "billingExpected", "boolean"],
  ["Phone Verification Required", "outcome", "lower_text"],
  ["Phone Verification Required", "stage", "lower_text"],
  ["Product Subscription", "productUuid", "text"],
  ["Sign Up", "billingExpected", "boolean"],
  ["Sign Up", "signUpMethod", "lower_text"],
  ["Transaction Ledger Updated", "from", "nullable_text"],
  ["Transaction Ledger Updated", "to", "text"],
  ["Transaction Type Updated", "bankLineUuid", "text"],
  ["Transaction Type Updated", "from", "nullable_text"],
  ["Transaction Type Updated", "to", "text"],
  ["Upload", "reason", "lower_text"],
];

// Union of every distinct key any event may carry, in declaration order (first
// occurrence wins). Used by merge-style callers to keep already-normalized
// values, not as an emission allowlist: emission is gated per event by
// V1_1_PROPERTY_KINDS. Deduplicated so it matches
// fetcher.parse.EVENT_PROPERTY_ALLOWLIST key-for-key.
export const EVENT_PROPERTY_KEYS: readonly string[] = Array.from(
  new Set([
    ...V1_PROPERTY_KINDS.map(([key]) => key),
    ...V1_1_PROPERTY_KINDS.map(([, key]) => key),
    ...V1_2_PROPERTY_KINDS.map(([, key]) => key),
  ]),
);

export interface EventRow {
  insert_id: string;
  event_name: string;
  event_time: string;
  distinct_id: string;
  user_id: string | null;
  uc_uuid: string | null;
  email: string | null;
  company_id: string | null;
  company: string | null;
  properties: JsonObject;
  properties_contract: string;
}

export interface ParseResult {
  rows: EventRow[];
  nonEmptyLines: number;
  synthesized: number;
}

function asText(value: unknown): string | null {
  if (value === null || value === undefined || value === "") return null;
  if (typeof value === "boolean") return value ? "True" : "False";
  return String(value);
}

function trimmedText(value: unknown): string | null {
  // String-valued property keys accept JSON strings only. A number, boolean,
  // object or array is malformed for these keys and is dropped rather than
  // coerced: coercing a structure produces noise (e.g. '{"a": 1}'), and
  // coercing a boolean differs by implementation ('True' here, 'true' in SQL).
  // This must stay identical to _normalized_text in fetcher/parse.py and to the
  // jsonb_typeof(raw) = 'string' guard in normalize_event_properties.
  if (typeof value !== "string") return null;
  const text = value.trim();
  return text || null;
}

function normalizedType(value: unknown): string | null {
  const text = trimmedText(value)?.toLowerCase() ?? null;
  if (text === "gst2b") return "gstr2b";
  return text;
}

const UPLOAD_SUBTYPES = new Set(["bulk", "single", "gst_reconciliation"]);

function normalizedSubtype(value: unknown, eventName: string): string | null {
  const text = trimmedText(value)?.toLowerCase() ?? null;
  if (text === null) return null;
  if (eventName === "Upload") {
    return UPLOAD_SUBTYPES.has(text) ? text : "bank";
  }
  return text;
}

const STATUS_CANONICAL: Record<string, string> = {
  success: "Success",
  failed: "Failed",
};

function normalizedStatus(value: unknown): string | null {
  const text = trimmedText(value);
  if (text === null) return null;
  // Exact-casing map only. "Accounting Ready" must survive verbatim.
  return STATUS_CANONICAL[text] ?? text;
}

const UUID_VALUE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function normalizedTransactionType(value: unknown): string | null {
  const text = trimmedText(value);
  if (!text || UUID_VALUE.test(text)) return text;
  return text.toLowerCase();
}

function normalizedNumber(value: unknown): number | null {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  return null;
}

function escapedJsonString(value: string): string {
  // Python json.dumps defaults to ensure_ascii=True. JSON.stringify already
  // handles quotes and control characters, so only non-ASCII code points need
  // the Python-compatible escaping pass.
  return JSON.stringify(value).replace(/[\u007f-\uffff]/g, (character) => {
    return `\\u${character.charCodeAt(0).toString(16).padStart(4, "0")}`;
  });
}

function pythonJson(value: unknown): string {
  if (value === null || value === undefined) return "null";
  if (typeof value === "string") return escapedJsonString(value);
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") {
    if (!Number.isFinite(value)) return "null";
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => pythonJson(item)).join(", ")}]`;
  }
  if (typeof value === "object") {
    const record = value as Record<string, unknown>;
    return `{${
      Object.keys(record).sort().map((key) =>
        `${escapedJsonString(key)}: ${pythonJson(record[key])}`
      ).join(", ")
    }}`;
  }
  return escapedJsonString(String(value));
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

function eventTime(properties: JsonObject): string {
  const rawTime = properties.time;
  if (rawTime === null || rawTime === undefined || rawTime === "") {
    throw new Error("event properties.time is required");
  }
  const timestamp = typeof rawTime === "number" ? rawTime : Number(rawTime);
  if (!Number.isFinite(timestamp)) {
    throw new Error("event properties.time must be numeric");
  }
  const seconds = timestamp > 1e12 ? timestamp / 1000 : timestamp;
  const result = new Date(seconds * 1000);
  if (Number.isNaN(result.getTime())) {
    throw new Error(
      "event properties.time is outside the supported date range",
    );
  }
  return result.toISOString();
}

async function synthesizedInsertId(
  eventName: string,
  properties: JsonObject,
): Promise<string> {
  const distinctId = asText(properties.distinct_id) ?? "";
  const userId = properties.userId || properties.$user_id;
  const canonical = pythonJson({
    event: eventName,
    distinct_id: distinctId,
    time: properties.time,
    companyId: properties.companyId,
    userId,
  });
  return `syn_${(await sha256Hex(canonical)).slice(0, 24)}`;
}

export async function parseJsonlLine(line: string): Promise<EventRow> {
  const payload = JSON.parse(line) as JsonObject;
  const eventName = asText(payload.event) ?? "";
  const rawProperties = payload.properties;
  const properties = (
      rawProperties && typeof rawProperties === "object" &&
      !Array.isArray(rawProperties)
    )
    ? rawProperties as JsonObject
    : {};
  const rawInsertId = properties.$insert_id;
  const hasInsertId = Boolean(rawInsertId);
  const insertId = hasInsertId
    ? asText(rawInsertId) as string
    : await synthesizedInsertId(eventName, properties);

  return {
    insert_id: insertId,
    event_name: eventName,
    event_time: eventTime(properties),
    distinct_id: asText(properties.distinct_id) ?? "",
    user_id: asText(properties.$user_id) ?? asText(properties.userId),
    uc_uuid: asText(properties.ucUuid),
    email: asText(properties.email),
    company_id: asText(properties.companyId),
    company: asText(properties.company),
    properties: warehouseProperties(properties, eventName),
    properties_contract: EVENT_PROPERTIES_VERSION,
  };
}

function normalizedStringArray(value: unknown): string[] | null {
  // Canonical sync_items: a JSON array of non-blank strings. Scalar strings are
  // NOT wrapped, and objects are rejected. A malformed value has no correct
  // reading, so it stays absent rather than being guessed at.
  if (!Array.isArray(value)) return null;
  const items: string[] = [];
  for (const entry of value) {
    if (typeof entry !== "string") return null;
    const text = entry.trim();
    if (!text) return null;
    items.push(text);
  }
  return items;
}

function normalizedScalarState(
  value: unknown,
): string | boolean | number | null {
  // Preserve the source scalar type. "false" stays the string "false" and is
  // never coerced to false: both boolean and string transitions (e.g.
  // "header" -> "ledger") are real observations. Arrays/objects are rejected.
  if (typeof value === "boolean") return value;
  if (typeof value === "string") return value.trim() || null;
  return normalizedNumber(value);
}

function normalizeKind(value: unknown, kind: PropertyKind): unknown | null {
  switch (kind) {
    case "boolean":
      return typeof value === "boolean" ? value : null;
    case "number":
      return normalizedNumber(value);
    case "string_array":
      return normalizedStringArray(value);
    case "scalar_state":
      return normalizedScalarState(value);
    case "lower_text":
    case "nullable_lower_text":
      return trimmedText(value)?.toLowerCase() ?? null;
    case "nullable_text":
    case "text":
      return trimmedText(value);
    case "type":
      return normalizedType(value);
    case "status":
      return normalizedStatus(value);
    case "transaction_type":
      return normalizedTransactionType(value);
    case "subtype":
      // Handled by the caller so the event name is available.
      return null;
  }
}

export function warehouseProperties(
  properties: JsonObject,
  eventName = "",
): JsonObject {
  const output: JsonObject = {};

  // Phase 1: global v1 keys, in contract order.
  for (const [key, kind] of V1_PROPERTY_KINDS) {
    if (!(key in properties)) continue;
    const value = kind === "subtype"
      ? normalizedSubtype(properties[key], eventName)
      : normalizeKind(properties[key], kind);
    if (value !== null) output[key] = value;
  }

  // Phase 2: only THIS event's scoped v1.1 keys. A key declared for another
  // event is never emitted, so an unrelated event cannot retain it.
  for (const [scopedEvent, key, kind] of V1_1_PROPERTY_KINDS) {
    if (eventName !== scopedEvent || !(key in properties)) continue;
    const value = normalizeKind(properties[key], kind);
    if (value !== null) output[key] = value;
  }

  for (const [scopedEvent, key, kind] of V1_2_PROPERTY_KINDS) {
    if (eventName !== scopedEvent || !(key in properties)) continue;
    if (properties[key] === null && kind.startsWith("nullable_")) {
      output[key] = null;
      continue;
    }
    const raw = properties[key];
    let value: unknown;
    if (kind === "number" || kind === "boolean") value = normalizeKind(raw, kind);
    else {
      // Match SQL btrim exactly for the new contract; don't alter legacy keys.
      const text = typeof raw === "string" ? raw.replace(/^ +| +$/g, "") : "";
      value = text ? (kind.includes("lower") ? text.toLowerCase() : text) : null;
    }
    if (value !== null) output[key] = value;
  }
  return output;
}

export async function parseJsonl(text: string): Promise<ParseResult> {
  const rows: EventRow[] = [];
  let nonEmptyLines = 0;
  let synthesized = 0;

  for (const line of text.split(/\r?\n/)) {
    if (!line.trim()) continue;
    nonEmptyLines += 1;
    if (nonEmptyLines >= MAX_NON_EMPTY_LINES) {
      throw new Error(
        `Mixpanel export has ${nonEmptyLines} non-empty lines; maximum is ${
          MAX_NON_EMPTY_LINES - 1
        }`,
      );
    }
    const row = await parseJsonlLine(line);
    if (!row.insert_id.startsWith("syn_")) {
      rows.push(row);
    } else {
      synthesized += 1;
      rows.push(row);
    }
  }

  return { rows, nonEmptyLines, synthesized };
}
