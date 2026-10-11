"use client";

import type { ReactNode } from "react";

/**
 * Reusable Product / Engineering investigation table.
 * The approved rd-activation-table + ed-investigation-table primitives own
 * table density, header, row rhythm, hover and sticky scroll semantics.
 * Each investigation provides only its columns, values and optional drill
 * actions; no metric calculation or AWS logic lives here.
 */
export type MetricsInvestigationRow = {
  id:string; label:string; value:string; detail:string;
  muted?:boolean;
  onOpen?:()=>void;
};
export type MetricsInvestigationTotal = {label:string; value:string; detail:string};

export default function MetricsInvestigationTable({
  rows,labelHeader,valueHeader,detailHeader,fullTotal,emptyMessage,ariaLabel,
}:{
  rows:MetricsInvestigationRow[];
  labelHeader:string;valueHeader:string;detailHeader:string;
  fullTotal?:MetricsInvestigationTotal;
  emptyMessage:string;ariaLabel:string;
}){
  return <div className="rd-table-wrap ed-investigation-table-wrap infra-drill-table-wrap"
      role="region" tabIndex={0} aria-label={ariaLabel}>
    <table className="rd-activation-table ed-investigation-table infra-drill-table">
      <thead><tr>
        <th scope="col">{labelHeader}</th>
        <th scope="col" className="infra-drill-align-right">{valueHeader}</th>
        <th scope="col" className="infra-drill-align-right">{detailHeader}</th>
      </tr></thead>
      <tbody>
        {rows.length?rows.map(row=>
          <tr key={row.id} className={"ed-investigation-row"+(row.muted?" infra-drill-muted":"")}>
            <td title={row.label}>{row.onOpen?
              <button type="button" className="ed-investigation-key infra-drill-open"
                title={"View "+row.label+" cost history"}
                onClick={row.onOpen}>{row.label}</button>:
              <span className="infra-drill-label">{row.label}</span>}</td>
            <td className="infra-drill-align-right infra-drill-amount">{row.value}</td>
            <td className="infra-drill-align-right infra-drill-detail">{row.detail}</td>
          </tr>
        ):<tr className="ed-investigation-row">
          <td colSpan={3} className="infra-drill-empty">{emptyMessage}</td>
        </tr>}
      </tbody>
      {fullTotal?<tfoot><tr>
        <th scope="row">{fullTotal.label}</th>
        <td className="infra-drill-align-right">{fullTotal.value}</td>
        <td className="infra-drill-align-right">{fullTotal.detail}</td>
      </tr></tfoot>:null}
    </table>
  </div>;
}
