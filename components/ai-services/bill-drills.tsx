"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type { BillExtractionRecord } from "../../lib/ai-services/types";

function shortId(uuid: string) {
  return uuid.slice(0, 8);
}

function fmtDate(iso: string) {
  return iso.slice(0, 10);
}

function fmtCost(v: number | null) {
  return v === null ? "unknown" : v.toFixed(3) + " units";
}

function fmtLatency(v: number | null) {
  return v === null ? "unknown" : String(v) + " units";
}

/** Shared modal shell: focus close on mount, Escape, overlay click, scroll lock. */
function ModalShell({ label, onClose, children, wide = false }: {
  label: string;
  onClose: () => void;
  children: React.ReactNode;
  wide?: boolean;
}) {
  const closeRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLElement>(null);
  useEffect(() => {
    const before = document.body.style.overflow;
    const previous = document.activeElement as HTMLElement | null;
    document.body.style.overflow = "hidden";
    closeRef.current?.focus({ preventScroll: true });
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        onClose();
        return;
      }
      if (event.key !== "Tab" || !panelRef.current) return;
      const all = Array.from(
        panelRef.current.querySelectorAll<HTMLElement>('button:not([disabled]),a[href],[tabindex]:not([tabindex="-1"]),input,select'),
      ).filter(el => el.tabIndex >= 0 && el.getClientRects().length > 0);
      if (!all.length) return;
      if (event.shiftKey && document.activeElement === all[0]) {
        event.preventDefault();
        all[all.length - 1].focus();
      } else if (!event.shiftKey && document.activeElement === all[all.length - 1]) {
        event.preventDefault();
        all[0].focus();
      }
    };
    document.addEventListener("keydown", onKey, true);
    return () => {
      document.body.style.overflow = before;
      document.removeEventListener("keydown", onKey, true);
      previous?.focus?.({ preventScroll: true });
    };
  }, [onClose]);
  return (
    <div
      className="ed-overlay"
      onMouseDown={event => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <section
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-label={label}
        className={"rd-modal rd-activation-modal ed-investigation-modal" + (wide ? " ai-drill-wide" : "")}
      >
        <header className="rd-modal-head ed-investigation-head">
          <h2>{label}</h2>
          <button ref={closeRef} type="button" className="rd-close ed-investigation-close" onClick={onClose} aria-label="Close dialog">
            ✕
          </button>
        </header>
        {children}
      </section>
    </div>
  );
}

type SortKey = "createdAt" | "knownTotalCost" | "knownTotalLatency";

const PAGE_SIZE = 10;

export function BillRecordsModal({ title, subtitle, coverage, records, onClose }: {
  title: string;
  subtitle: string;
  coverage: string;
  records: BillExtractionRecord[];
  onClose: () => void;
}) {
  const [query, setQuery] = useState("");
  const [sortKey, setSortKey] = useState<SortKey>("createdAt");
  const [sortDir, setSortDir] = useState<"asc" | "desc">("desc");
  const [page, setPage] = useState(1);
  const [detail, setDetail] = useState<BillExtractionRecord | null>(null);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    const rows = q
      ? records.filter(r =>
          r.predictionUuid.toLowerCase().includes(q) ||
          r.companyName.toLowerCase().includes(q) ||
          (r.docType ?? "").includes(q),
        )
      : records;
    const dir = sortDir === "asc" ? 1 : -1;
    return [...rows].sort((a, b) => {
      const av = a[sortKey];
      const bv = b[sortKey];
      if (av === null && bv === null) return 0;
      if (av === null) return 1;
      if (bv === null) return -1;
      if (typeof av === "number" && typeof bv === "number") return (av - bv) * dir;
      return String(av).localeCompare(String(bv)) * dir;
    });
  }, [records, query, sortKey, sortDir]);

  const pages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, pages);
  const visible = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);

  const toggleSort = (key: SortKey) => {
    if (key === sortKey) setSortDir(d => (d === "asc" ? "desc" : "asc"));
    else {
      setSortKey(key);
      setSortDir(key === "createdAt" ? "desc" : "desc");
    }
    setPage(1);
  };

  return (
    <ModalShell label={title} onClose={detail ? () => setDetail(null) : onClose} wide>
      <p className="ed-investigation-caption">{subtitle}</p>
      <p className="ed-investigation-caption">{coverage} · {filtered.length} matching extractions</p>
      <div className="rd-drill-toolbar ed-investigation-toolbar">
        <input
          type="search"
          className="ai-drill-search"
          placeholder="Search prediction, company, type"
          aria-label="Search extractions"
          value={query}
          onChange={event => {
            setQuery(event.target.value);
            setPage(1);
          }}
        />
      </div>
      <div className="rd-table-wrap ed-investigation-table-wrap">
        <table className="rd-activation-table ed-investigation-table ai-records-table">
          <thead>
            <tr>
              <th scope="col">Prediction</th>
              <th scope="col" aria-sort={sortKey === "createdAt" ? (sortDir === "asc" ? "ascending" : "descending") : "none"}>
                <button type="button" className="ed-investigation-sort" onClick={() => toggleSort("createdAt")}>Created</button>
              </th>
              <th scope="col">Company</th>
              <th scope="col">Doc</th>
              <th scope="col">Pages</th>
              <th scope="col" aria-sort={sortKey === "knownTotalCost" ? (sortDir === "asc" ? "ascending" : "descending") : "none"}>
                <button type="button" className="ed-investigation-sort" onClick={() => toggleSort("knownTotalCost")}>Cost</button>
              </th>
              <th scope="col" aria-sort={sortKey === "knownTotalLatency" ? (sortDir === "asc" ? "ascending" : "descending") : "none"}>
                <button type="button" className="ed-investigation-sort" onClick={() => toggleSort("knownTotalLatency")}>Latency</button>
              </th>
              <th scope="col">Review</th>
            </tr>
          </thead>
          <tbody>
            {visible.length ? visible.map(r => (
              <tr key={r.predictionUuid} className="ed-investigation-row">
                <td>
                  <button type="button" className="ed-investigation-key" onClick={() => setDetail(r)} title={"Open " + r.predictionUuid}>
                    {shortId(r.predictionUuid)}
                  </button>
                </td>
                <td>{fmtDate(r.createdAt)}</td>
                <td title={r.companyName}>{r.companyName}</td>
                <td>{r.docType ?? "unknown"}</td>
                <td>{r.totalPages ?? "—"}</td>
                <td>{fmtCost(r.knownTotalCost)}</td>
                <td>{fmtLatency(r.knownTotalLatency)}</td>
                <td>{r.reviewStatus ?? "unknown"}</td>
              </tr>
            )) : (
              <tr className="ed-investigation-row">
                <td colSpan={8} className="ed-investigation-empty">No extractions match these filters.</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <footer className="rd-modal-foot rd-modal-foot-paginated ed-investigation-foot">
        <nav className="rd-pagination" aria-label="Extraction pages">
          <button type="button" disabled={safePage <= 1} onClick={() => setPage(p => Math.max(1, p - 1))}>Previous</button>
          <span aria-current="page">Page {safePage} of {pages}</span>
          <button type="button" disabled={safePage >= pages} onClick={() => setPage(p => Math.min(pages, p + 1))}>Next</button>
        </nav>
      </footer>
      {detail ? <BillDetailModal record={detail} onClose={() => setDetail(null)} /> : null}
    </ModalShell>
  );
}

export function BillDetailModal({ record, onClose }: {
  record: BillExtractionRecord;
  onClose: () => void;
}) {
  const rows: Array<[string, string]> = [
    ["Prediction", record.predictionUuid],
    ["Company", record.companyName + " (" + record.companyScope + ")"],
    ["Created", record.createdAt],
    ["Loaded", record.loadedAt],
    ["Review status", (record.reviewStatus ?? "unknown") + " — snapshot, not accuracy"],
    ["Document type", record.docType ?? "unknown"],
    ["Pages", record.totalPages === null ? "unknown" : String(record.totalPages)],
    ["Legibility", record.legibilityScore === null ? "unknown (not a correctness score)" : record.legibilityScore.toFixed(2)],
    ["Extraction cost", record.extractionCost === null ? "unknown" : String(record.extractionCost)],
    ["Enrichment cost", record.enrichmentCost === null ? "unknown" : String(record.enrichmentCost)],
    ["Known total cost", fmtCost(record.knownTotalCost) + (record.completeCostBreakdown ? "" : " (partial)")],
    ["Extraction latency", record.extractionLatency === null ? "unknown" : String(record.extractionLatency)],
    ["Enrichment latency", record.enrichmentLatency === null ? "unknown" : String(record.enrichmentLatency)],
    ["Known total latency", fmtLatency(record.knownTotalLatency) + (record.completeLatencyBreakdown ? "" : " (partial)")],
    ["Raw artifact", record.hasRaw ? "available" : "not stored"],
  ];
  return (
    <ModalShell label={"Extraction " + shortId(record.predictionUuid)} onClose={onClose}>
      <button type="button" className="ed-investigation-key ai-record-back" onClick={onClose}>← Back to results</button>
      <dl className="ai-record-detail">
        {rows.map(([term, value]) => (
          <div key={term}>
            <dt>{term}</dt>
            <dd>{value}</dd>
          </div>
        ))}
      </dl>
    </ModalShell>
  );
}
