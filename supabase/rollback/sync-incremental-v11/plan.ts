/** Two export days per invocation fit the existing hourly job's work budget. */
export function assertCurrentSyncDay(requested: string, currentIstDay: string): string {
  if (requested !== currentIstDay) {
    throw new Error("today must equal the current IST date; use the separate backfill for history");
  }
  return requested;
}

export function planIncrementalDays(today: string, lastSuccessfulDay: string | null): string[] {
  const shift = (day: string, offset: number) => {
    const value = new Date(`${day}T00:00:00Z`);
    if (Number.isNaN(value.getTime()) || value.toISOString().slice(0, 10) !== day) {
      throw new Error("invalid incremental watermark date");
    }
    value.setUTCDate(value.getUTCDate() + offset);
    return value.toISOString().slice(0, 10);
  };
  if (lastSuccessfulDay && lastSuccessfulDay > today) {
    throw new Error("incremental watermark is ahead of today");
  }
  const yesterday = shift(today, -1);
  if (!lastSuccessfulDay || lastSuccessfulDay >= yesterday) return [yesterday, today];
  // Revisit the last published day for late events, then advance one day.
  // Finishing with the second day lets each hourly run consume one missing day.
  return [lastSuccessfulDay, shift(lastSuccessfulDay, 1)];
}

/** This project's raw export API uses UTC dates; reporting cohorts still use IST. */
export function exportToday(now: Date = new Date()): string {
  return now.toISOString().slice(0, 10);
}
