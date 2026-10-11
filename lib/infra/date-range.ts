export type MonthPreset = "lifetime" | "3" | "6" | "12" | "custom";
export type MonthRange = { preset: MonthPreset; start: string | null; end: string | null };

export function shiftMonth(month: string, count: number): string {
  const [year, number] = month.split("-").map(Number);
  return new Date(Date.UTC(year, number - 1 + count, 1)).toISOString().slice(0, 7);
}

export function monthLabel(month: string): string {
  return new Date(month + "-01T12:00:00Z").toLocaleDateString("en-GB", {
    month: "short", year: "numeric", timeZone: "UTC",
  }).replace("Sept", "Sep");
}

export function rangeLabel(range: MonthRange): string {
  if (range.preset === "lifetime") return "Lifetime";
  if (!range.start || !range.end) return "Custom range";
  if (range.start === range.end) return monthLabel(range.end);
  return monthLabel(range.start) + " – " + monthLabel(range.end);
}

/** Presets end at the completed month before the captured reporting month. */
export function completedPreset(preset: Exclude<MonthPreset, "custom">, asOf: string): MonthRange {
  if (preset === "lifetime") return { preset, start: null, end: null };
  const end = shiftMonth(asOf.slice(0, 7), -1);
  return { preset, start: shiftMonth(end, 1 - Number(preset)), end };
}

export function validMonthRange(range: MonthRange, latest: string): boolean {
  if (range.preset === "lifetime") return true;
  const valid = (s: string | null): s is string => !!s && /^\d{4}-(0[1-9]|1[0-2])$/.test(s);
  return valid(range.start) && valid(range.end) && range.start <= range.end && range.end <= latest;
}

/** End month drives KPI/detail scope. Start month limits the monthly trend. */
export function resolveRange(range: MonthRange, months: readonly string[]): { start: string; end: string } {
  if (!months.length) throw new Error("infra_missing_month_coverage");
  const sorted = [...months].sort();
  const first = sorted[0], last = sorted[sorted.length - 1];
  if (!validMonthRange(range, last)) throw new Error("infra_invalid_date_range");
  return range.preset === "lifetime"
    ? { start: first, end: last }
    : { start: range.start!, end: range.end! };
}
