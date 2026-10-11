import ProductMetricsHeader from "../../../components/product-metrics-header";
import "../delivery.css";
import "../../retention/retention.css";
import "../../customer/customer.css";
import "../../metrics-page-grid.css";
import "./assignees.css";

export default function LoadingAssignees(){
  return <div className="companies-shell assignee-shell">
    <ProductMetricsHeader current="delivery" deliveryView="assignees"/>
    <main className="companies-page assignee-page" role="status" aria-busy="true"
      aria-label="Loading assignee workload matrix">
      <div className="page-heading companies-page-heading">
        <div className="companies-title-block"><h1>Assignee Overview</h1>
          <p>Open Jira work by assignee, module and issue type</p></div>
      </div>
      <div className="metrics-section-kicker"><span>Assignee workload</span></div>
      <section className="companies-records po-record-layout companies-monthly-records companies-grid-card">
        <div className="po-record-toolbar companies-command-bar">
          <div className="ed-skeleton-line" style={{width:190,height:14}}/>
          <div className="ed-skeleton-line" style={{width:270,height:34}}/>
        </div>
        <div className="po-record-scroll companies-monthly-scroll assignee-load">
          <div className="ed-skeleton-line" style={{height:70,width:"100%",borderRadius:0}}/>
          {Array.from({length:12},(_,i)=><div key={i} className="ed-skeleton-line"
            style={{height:24,width:(72+(i%4)*7)+"%",margin:"20px 15px"}}/>)}
        </div>
      </section>
    </main>
  </div>;
}
