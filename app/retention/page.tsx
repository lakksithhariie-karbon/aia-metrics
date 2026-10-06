import RetentionDashboard from "../../components/retention/retention-dashboard";
import { readRetentionDashboardV4 } from "../../lib/retention/server";
import type { RetentionDashboardV4Response } from "../../lib/retention/types";
import "./retention.css";

export const dynamic = "force-dynamic";

function currentMonthIST(): string {
  return new Date()
    .toLocaleDateString("en-CA", {
      timeZone: "Asia/Kolkata",
      year: "numeric",
      month: "2-digit",
    })
    .slice(0, 7);
}

function shiftMonth(month: string, offset: number): string {
  const [year, value] = month.split("-").map(Number);
  return new Date(Date.UTC(year, value - 1 + offset, 1))
    .toISOString()
    .slice(0, 7);
}

function lastDayOfMonth(month: string): string {
  const next = shiftMonth(month, 1);
  return new Date(Date.parse(next + "-01T00:00:00Z") - 86_400_000)
    .toISOString()
    .slice(0, 10);
}

export default async function RetentionPage() {
  const initialMonth = shiftMonth(currentMonthIST(), -1);
  let initialData: RetentionDashboardV4Response | null = null;

  try {
    initialData = await readRetentionDashboardV4({
      from: initialMonth + "-01",
      to: lastDayOfMonth(initialMonth),
    });
  } catch (error) {
    console.error(
      "retention-initial-dashboard",
      error instanceof Error ? error.message.slice(0, 180) : String(error),
    );
  }

  return (
    <RetentionDashboard
      initialMonth={initialMonth}
      initialData={initialData}
    />
  );
}
