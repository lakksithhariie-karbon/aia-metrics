import type { Metadata } from "next";
import ProductMetricsHeader from "../../../components/product-metrics-header";
import AssigneeOverviewTable from "../../../components/delivery/assignee-overview-table";
import { readAssigneeMatrix } from "../../../lib/delivery/assignee-matrix";
import { parseDeliveryFilters } from "../../../lib/delivery/server";
import type { AssigneeMatrix } from "../../../lib/delivery/assignee-matrix";
import "../delivery.css";
import "../delivery-investigation.css";
import "../../retention/retention.css";
import "../../customer/customer.css";
import "../../metrics-page-grid.css";
import "./assignees.css";

export const metadata:Metadata={
  title:"AI Accountant | Assignee Overview",
  description:"Jira-backed ownership matrix by assignee, module and issue type.",
};
export const dynamic="force-dynamic";
export const maxDuration=45;
// Keep the matrix renderer close to the shared Supabase ap-south-1 database.
export const preferredRegion="bom1";

export default async function AssigneePage({searchParams}:{
  searchParams:Promise<Record<string,string|string[]|undefined>>;
}){
  let data:AssigneeMatrix|null=null;
  let message:string|null=null;
  try{
    const filters=parseDeliveryFilters(await searchParams);
    data=await readAssigneeMatrix(filters);
  }catch(error){
    console.error("jira_assignee_matrix_unavailable",
      error instanceof Error?error.message.slice(0,130):"unknown");
    message="Verified Jira workload is temporarily unavailable. No sample data is shown.";
  }
  return <div className="companies-shell assignee-shell">
    <ProductMetricsHeader current="delivery" deliveryView="assignees"/>
    {data?<AssigneeOverviewTable data={data}/>:
      <main className="companies-page assignee-page" role="alert">
        <div className="page-heading companies-page-heading">
          <div className="companies-title-block"><h1>Assignee Overview</h1>
            <p>Open Jira work by assignee, module and issue type</p></div>
        </div>
        <section className="companies-grid-card companies-error">
          <div><strong>Verified data unavailable</strong>
            <span>{message}</span>
            <p><a href="/delivery/assignees">Retry</a></p>
          </div>
        </section>
      </main>}
  </div>;
}
