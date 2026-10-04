import { SNAPSHOT_DATE, type Activity, type Customer, type Flow } from "./usage";

/**
 * Exact activity fixture schedule used in public/prototype/runtime-v2-2.js.
 * No real customers, no new metrics, and no inferred multi-user memberships.
 * The adapter supports multiple users, but the supplied fixture attributes each
 * company ID to one user. Equal display names are deliberately NOT merged.
 */
export function customerFixtures(): Customer[] {
  const addDays = (iso: string, days: number) => new Date(Date.parse(iso + "T12:00:00Z") + days * 86400000).toISOString().slice(0, 10);
  const hashText = (value: string) => { let h = 2166136261; for (const char of value) { h ^= char.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; };
  const names = ["Northstar", "Willow", "Harbor", "Cedar", "Maple", "Stonebridge", "Bluebird", "Summit", "Oakfield", "Silverline", "Greenfield", "Horizon", "Riverbend", "Parkside", "Evergreen", "Westhaven", "Aster", "Lakeside", "Pinecrest", "Meadow", "Elmwood", "Seabrook", "Amber", "Redwood"];
  const suffixes = ["Traders", "Textiles", "Supplies", "Distributors", "Industries", "Foods", "Engineering", "Furnishings", "Components", "Packaging", "Retail", "Services"];
  const people = ["arjun", "meera", "rohan", "kavya", "dev", "aisha", "neel", "tara", "vikram", "priya", "ananya", "kabir", "isha", "sahil", "nisha", "amit"];
  const users = Array.from({ length: 480 }, (_, i) => ({
    id: "po-u-" + i, email: `${people[i % people.length]}.${String(i + 1).padStart(3, "0")}@ledgerdesk.example`,
    companies: Array.from({ length: i % 23 === 0 ? 3 : i % 5 === 0 ? 2 : 1 }, (_, j) => ({
      id: `po-c-${i}-${j}`, name: names[(i + j * 5) % names.length] + " " + suffixes[(i * 3 + j) % suffixes.length] + (i >= 96 ? " " + String(Math.floor(i / 96) + 1) : ""),
      integration: (i + j) % 11 === 0 ? "Zoho Books" : "Tally", events: [] as Activity[],
    })),
  }));
  const scheduled = users.map(() => new Set<string>());
  const schedule = (i: number, day: string) => { if (i < users.length && day <= SNAPSHOT_DATE) scheduled[i].add(day); };
  const last4starts = ["2026-08-31", "2026-09-07", "2026-09-14", "2026-09-21"];
  let index = 0;
  [44, 60, 102, 93].forEach((n, w) => { for (let k = 0; k < n; k++, index++) schedule(index, addDays(last4starts[w], w === 0 ? 5 + index % 2 : 1 + index % 5)); });
  const pairs = [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]];
  [9, 9, 8, 8, 8, 8].forEach((n, j) => { for (let k = 0; k < n; k++, index++) pairs[j].forEach(w => schedule(index, addDays(last4starts[w], w === 0 ? 5 + index % 2 : 1 + index % 5))); });
  [8, 7, 7, 7].forEach((n, omit) => { for (let k = 0; k < n; k++, index++) last4starts.forEach((w, j) => { if (j !== omit) schedule(index, addDays(w, j === 0 ? 5 + index % 2 : 1 + index % 5)); }); });
  for (; index < 420; index++) last4starts.forEach((w, j) => schedule(index, addDays(w, j === 0 ? 5 + index % 2 : 1 + index % 5)));
  [...Array(144).keys(), ...Array.from({ length: 9 }, (_, i) => 420 + i)].forEach(i => {
    schedule(i, addDays("2026-09-28", i % 7));
    if (i % 3 === 0) schedule(i, addDays("2026-09-28", (i + 2) % 7));
    if (i % 7 === 0) schedule(i, "2026-10-04");
  });
  for (let i = 0; i < 292; i++) {
    schedule(i, addDays("2026-08-10", (i % 3) * 7 + 1 + i % 4));
    ["2026-08-10", "2026-08-17", "2026-08-24"].forEach((w, j) => { if (hashText(i + "old" + j) % 100 < (j === 1 ? 54 : 22)) schedule(i, addDays(w, 1 + i % 5)); });
    if (i % 4 === 0) schedule(i, "2026-08-07");
  }
  ["2026-07-06", "2026-07-13", "2026-07-20", "2026-07-27", "2026-08-03"].forEach((w, wi) => {
    for (let i = 0; i < users.length; i++) if ((i < 220 || i >= 429) && hashText("history" + i + ":" + wi) % 100 < 43) schedule(i, addDays(w, wi === 4 ? i % 3 : 1 + i % 5));
  });
  users.forEach((user, i) => {
    [...scheduled[i]].sort().forEach((day, di) => {
      const company = user.companies[di % user.companies.length], profile = (i * 37) % 100, seed = hashText(user.id + day), v = 4 + seed % 78;
      const add = (flow: Flow, count: number) => { if (count > 0) company.events.push({ date: day, flow, count }); };
      const hasAP = profile >= 33 && profile < 98, hasAR = profile >= 89 && profile < 99;
      const hasTxn = profile < 33 || profile >= 66 && profile < 89 || profile >= 94 && profile < 98;
      if (hasAP) { add("bills", Math.ceil(v * .53)); add("bills", Math.floor(v * .4)); if (seed % 3 === 0) add("bills", 1 + seed % 9); }
      if (hasAR) { add("invoices", 2 + seed % 13); add("invoices", 1 + seed % 8); }
      if (hasTxn) { if (seed % 3 === 0) add("statements", 1 + seed % 5); add("transactions", 12 + seed % 161); }
      if ((i + di) % 7 === 0 || di === 1 || profile === 99) add("sync", 1 + seed % 6);
      if (!company.events.some(e => e.date === day)) add("bills", v);
    });
  });
  return users.flatMap(user => user.companies.map(company => ({
    id: company.id, name: company.name, integration: company.integration,
    users: [{ id: user.id, email: user.email, events: company.events }],
  })));
}
