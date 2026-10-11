"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";
import CompactMenuSelect from "../ui/compact-menu-select";
import MetricsInfoDialog, { MetricsInfoButton } from "../ui/metrics-info";
import type { MetricsInfoDefinition } from "../ui/metrics-info";
import type { InfraPreviewData, InfraAwsService, InfraAwsAccount, InfraDocType } from "../../lib/infra/types";
import {
  AwsSpendTrend, ServiceDrivers, AccountDistribution,
  BillVolumeEconomics, CostComposition, DocumentTypes, DailyBillVolume,
} from "./infra-charts";

type DrillKind = "aws-month"|"services"|"service"|"accounts"|"account"|"bill-month"|"doc-type"|"health";
type Drill = {kind:DrillKind; key?:string};
type Metric = {id:string;label:string;value:string;unit?:string;period:string;caption:string;definition:string;source:string;drill:Drill};
type DrillRow = {label:string;amount:string;extra:string;hint?:string;drill?:Drill};

const us = (n:number)=>new Intl.NumberFormat("en-US").format(n);
const usd = (n:number)=>new Intl.NumberFormat("en-US",{
  style:"currency",currency:"USD",minimumFractionDigits:2,maximumFractionDigits:2,
}).format(n);
const dec = (n:number,d=2)=>n.toLocaleString("en-US",{
  minimumFractionDigits:d,maximumFractionDigits:d,
});
const pct = (n:number)=>dec(n,1)+"%";
const monthText = (month:string)=>new Date(month+"-01T12:00:00Z")
  .toLocaleDateString("en-GB",{month:"short",year:"numeric",timeZone:"UTC"});
const dateText = (iso:string)=>new Date(iso).toLocaleString("en-GB",{
  timeZone:"Asia/Kolkata",day:"2-digit",month:"short",year:"numeric",hour:"2-digit",minute:"2-digit",
})+" IST";
const pretty = (v:string)=>v==="Amazon Relational Database Service"?"Amazon RDS":
  v==="Savings Plans for AWS Compute usage"?"Savings Plans":
  v==="Amazon Elastic Container Service"?"Amazon ECS":
  v==="AmazonCloudWatch"?"CloudWatch":
  v==="Amazon Elastic Load Balancing"?"Load Balancing":
  v==="Amazon EC2 Container Registry (ECR)"?"Amazon ECR":
  v==="Amazon Virtual Private Cloud"?"Amazon VPC":v;
const sourcePreview = "Audited read-only preview capture; not a live Supabase reader";

function SectionHead({title,question}:{title:string;question:string}){
  return <div className="metrics-section-kicker ed-section-heading">
    <span>{title}</span><span className="metrics-section-description">{question}</span>
  </div>;
}

/** Exact shared report-card and report-header primitives from Engineering/Product. */
function Surface({title,subtitle,children,half=false,onInfo}:{
  title:string;subtitle:string;children:ReactNode;half?:boolean;onInfo?:()=>void;
}){
  return <article className={"report-card ed-report"+(half?" ed-report-half":"")}>
    <header className="report-header ed-report-heading">
      <div><h2>{title}</h2><p className="report-subtitle">{subtitle}</p></div>
      {onInfo?<MetricsInfoButton label={"How "+title+" is counted"} onClick={onInfo}/>:null}
    </header>
    {children}
  </article>;
}

/** Exact Product .metric-card and Engineering .ed-metric; separate info button. */
function MetricCard({metric,onDrill,onInfo}:{
  metric:Metric;onDrill:(drill:Drill)=>void;onInfo:(metric:Metric)=>void;
}){
  return <div className="ed-metric-wrap">
    <button className="metric-card ed-metric" type="button"
      onClick={()=>onDrill(metric.drill)} aria-haspopup="dialog"
      aria-label={metric.label+": "+metric.value+". Open supporting breakdown."}>
      <span className="po-kpi-divider" aria-hidden="true"/>
      <span className="metric-label">{metric.label}</span>
      <span className="metric-period">{metric.period}</span>
      <span className="metric-value">{metric.value}
        {metric.unit?<span className="unit">{metric.unit}</span>:null}
      </span>
      <span className="metric-note">{metric.caption}</span>
    </button>
    <MetricsInfoButton className="ed-info-button" label={"How "+metric.label+" is calculated"}
      onClick={()=>onInfo(metric)}/>
  </div>;
}

function BreakdownDialog({target,month,data,onClose,onNext}:{
  target:Drill;month:string;data:InfraPreviewData;
  onClose:()=>void;onNext:(target:Drill)=>void;
}){
  const closeRef=useRef<HTMLButtonElement>(null);
  const panelRef=useRef<HTMLElement>(null);
  useEffect(()=>{
    const before=document.body.style.overflow;
    document.body.style.overflow="hidden";
    closeRef.current?.focus({preventScroll:true});
    const onKey=(event:KeyboardEvent)=>{
      if(event.key==="Escape"){event.preventDefault();onClose();return;}
      if(event.key!=="Tab")return;
      const all=Array.from(panelRef.current?.querySelectorAll<HTMLElement>(
        'button:not([disabled]),a[href],[tabindex]:not([tabindex="-1"])'
      )||[]).filter(el=>el.tabIndex>=0);
      if(!all.length)return;
      if(event.shiftKey&&document.activeElement===all[0]){event.preventDefault();all[all.length-1].focus();}
      if(!event.shiftKey&&document.activeElement===all[all.length-1]){event.preventDefault();all[0].focus();}
    };
    document.addEventListener("keydown",onKey,true);
    return ()=>{document.body.style.overflow=before;document.removeEventListener("keydown",onKey,true);};
  },[onClose]);

  const aws=data.awsMonths.find(x=>x.month===month);
  const bill=data.billMonths.find(x=>x.month===month);
  const serviceRows=data.awsServices.filter(x=>x.month===month);
  const accountRows=data.awsAccounts.filter(x=>x.month===month);
  const typeRows=data.docTypes.filter(x=>x.month===month);
  let title="",subtitle="",note="",rows:DrillRow[]=[];
  const costLabel="Recorded cost units";

  if(target.kind==="aws-month"||target.kind==="services"){
    title=target.kind==="aws-month"?"AWS spend · "+monthText(month):"Cloud services · "+monthText(month);
    subtitle="UnblendedCost · USD · "+(aws?.estimated?"Estimated period":"Completed month");
    rows=serviceRows.map(r=>({
      label:pretty(r.service),amount:usd(r.usd),
      extra:pct((aws?.usd??0)>0?r.usd/(aws?.usd??1)*100:0),
      drill:{kind:"service",key:r.service},
    }));
    const remaining=Math.max(0,(aws?.usd??0)-serviceRows.reduce((s,r)=>s+r.usd,0));
    if(remaining>.005)rows.push({label:"Other services",amount:usd(remaining),extra:"Combined",
      hint:"Outside the preview's top 11 service categories"});
    note="All services contribute to the monthly total. The preview only itemizes the 11 largest categories.";
  }else if(target.kind==="service"){
    const name=target.key??"";
    title=pretty(name);
    subtitle="Monthly AWS service/category costs · USD";
    rows=data.awsMonths.filter(r=>r.month>="2026-05").map(m=>{
      const selected=data.awsServices.find(s=>s.month===m.month&&s.service===name);
      return {label:monthText(m.month),amount:selected?usd(selected.usd):"—",
        extra:m.estimated?"Estimated":"Completed",
        hint:selected?"":"Only the top 11 categories per month are captured in this preview"};
    });
    note="A dash means this service was not within the captured top 11 for that month, not that its spend was zero.";
  }else if(target.kind==="accounts"){
    title="Linked AWS accounts";
    subtitle=monthText(month)+" · Anonymized account labels · USD";
    rows=accountRows.map(r=>({
      label:r.label,amount:usd(r.usd),
      extra:pct((aws?.usd??0)>0?r.usd/(aws?.usd??1)*100:0),
      drill:{kind:"account",key:r.label},
    }));
    const remaining=Math.max(0,(aws?.usd??0)-accountRows.reduce((s,r)=>s+r.usd,0));
    if(remaining>.005)rows.push({label:"Other accounts",amount:usd(remaining),extra:"Combined"});
    note="The preview masks AWS account IDs. Only the nine largest account totals are itemized.";
  }else if(target.kind==="account"){
    title=target.key??"AWS account";
    subtitle="Captured monthly account spend · USD";
    rows=data.awsMonths.filter(r=>r.month>="2026-05").map(m=>{
      const observation=data.awsAccounts.find(a=>a.month===m.month&&a.label===target.key);
      return {label:monthText(m.month),amount:observation?usd(observation.usd):"—",
        extra:m.estimated?"Estimated":"Completed"};
    });
    note="Only the nine largest linked accounts per month are stored in the preview. Missing rows do not imply zero spend.";
  }else if(target.kind==="bill-month"){
    title="Bill-processing economics · "+monthText(month);
    subtitle="Processing records grouped by source document type";
    rows=typeRows.map(r=>({
      label:r.doc_type,amount:us(r.docs)+" bills",
      extra:r.avg_measured==null?"Average unavailable":dec(r.avg_measured,5)+" avg cost units",
      drill:{kind:"doc-type",key:r.doc_type},
    }));
    note=(bill?us(bill.docs)+" bill records · "+us(bill.measured)+" with both cost components measured. ":"")+
      "No currency conversion is assumed; missing cost components are excluded from measured averages.";
  }else if(target.kind==="doc-type"){
    const name=target.key??"Unclassified";
    title="Document type · "+name;
    subtitle="Monthly volume and source-native processing cost";
    rows=data.billMonths.map(m=>{
      const item=data.docTypes.find(r=>r.month===m.month&&r.doc_type===name);
      return {label:monthText(m.month),amount:item?us(item.docs)+" bills":"—",
        extra:item&&item.avg_measured!=null?dec(item.avg_measured,5)+" measured average":"—"};
    });
    note="Grouping comes from bill_costs.doc_type. A measured average requires both extraction and enrichment costs.";
  }else{
    title="Data freshness and completeness";
    subtitle="Read-only preview source checks";
    rows=[
      {label:"Last successful AWS import",amount:"8 Oct 2026",extra:"14 months covered"},
      {label:"AWS linked accounts",amount:us(data.awsRun.accounts),extra:"Cost Explorer"},
      {label:"AWS source rows upserted",amount:us(data.awsRun.rows),extra:"Latest import"},
      {label:"Stored vs reference AWS amount",amount:usd(data.awsRun.storedDetailUsd),extra:usd(data.awsRun.referenceUsd)+" reference"},
      {label:"Bill processing capture",amount:"11 Oct 2026",extra:"Last table observation"},
      {label:"Unmeasured cost components",amount:"2,380",extra:"Across all three captured bill months"},
    ];
    note="AWS per-account failures are currently tolerated by the ingestion function. This screenshot-ready preview does not certify that every account has a complete detail trail.";
  }

  return <div className="ed-overlay" role="presentation" onMouseDown={e=>{
    if(e.target===e.currentTarget)onClose();
  }}>
    <section ref={panelRef} className="ed-evidence-dialog infra-drill-dialog"
      role="dialog" aria-modal="true" aria-labelledby="infra-drill-title">
      <header><div><span>INFRASTRUCTURE · SOURCE BREAKDOWN</span>
        <h2 id="infra-drill-title">{title}</h2>
      </div><button ref={closeRef} type="button" onClick={onClose}
        aria-label="Close breakdown">×</button></header>
      <div className="ed-evidence-summary">{subtitle}</div>
      <div className="ed-evidence-table-shell">
        <table className="ed-report-table ed-evidence-table">
          <thead><tr><th scope="col">Dimension</th><th scope="col">Value</th><th scope="col">Detail</th></tr></thead>
          <tbody>
            {rows.map((r,i)=><tr key={r.label+"-"+i}>
              <th scope="row">{r.drill?<button className="ed-cell-drill" type="button"
                onClick={()=>onNext(r.drill!)} title={"Open "+r.label+" breakdown"}>
                {r.label}<span aria-hidden="true">↗</span>
              </button>:r.label}</th>
              <td>{r.amount}</td><td>{r.hint?<span title={r.hint}>{r.extra} · unavailable elsewhere</span>:r.extra}</td>
            </tr>)}
            {!rows.length?<tr><td colSpan={3}>No audited rows for this reporting selection.</td></tr>:null}
          </tbody>
        </table>
      </div>
      <footer className="ed-evidence-footer infra-drill-foot">
        <span>{note}</span>
        <button type="button" onClick={onClose}>Close</button>
      </footer>
    </section>
  </div>;
}

export default function InfraOverview({data}:{data:InfraPreviewData}){
  const [month,setMonth]=useState("2026-09");
  const [drill,setDrill]=useState<Drill|null>(null);
  const [info,setInfo]=useState<MetricsInfoDefinition|null>(null);
  const opener=useRef<HTMLElement|null>(null);
  const closeDrill=useCallback(()=>{
    setDrill(null);
    requestAnimationFrame(()=>opener.current?.focus({preventScroll:true}));
  },[]);
  const openDrill=(target:Drill)=>{
    opener.current=document.activeElement instanceof HTMLElement?document.activeElement:null;
    setDrill(target);
  };
  const options=useMemo(()=>data.awsMonths.filter(m=>m.month>="2026-05")
    .slice().reverse().map(m=>({value:m.month,label:monthText(m.month)+(m.estimated?" · Estimated":"")})),[data.awsMonths]);
  const current=data.awsMonths.find(x=>x.month===month);
  const currentIndex=data.awsMonths.findIndex(x=>x.month===month);
  const previous=currentIndex>0?data.awsMonths[currentIndex-1]:null;
  const bill=data.billMonths.find(x=>x.month===month)??null;
  const services=data.awsServices.filter(x=>x.month===month);
  const accounts=data.awsAccounts.filter(x=>x.month===month);
  const types=data.docTypes.filter(x=>x.month===month);
  const diff=current&&!current.estimated&&previous&&!previous.estimated&&previous.usd>0
    ?(current.usd-previous.usd)/previous.usd*100:null;
  const period=monthText(month),covered=Boolean(bill);
  const awsMetrics:Metric[]=[
    {id:"aws-cost",label:"AWS cloud spend",value:current?usd(current.usd):"—",period:period+(current?.estimated?" · Estimated":""),
      caption:"Monthly UnblendedCost · USD",definition:"Sum of all AWS Cost Explorer UnblendedCost amounts across the selected month and linked accounts. Tax and Savings Plans are included.",
      source:"aia_infra.aws_costs; captured on 8 Oct 2026",drill:{kind:"aws-month"}},
    {id:"mom",label:"Month-on-month",value:diff===null?"—":(diff>0?"+":"")+pct(diff),
      period:period,caption:current?.estimated?"Incomplete months are not compared":"Compared with the previous completed month",
      definition:"Selected completed-month AWS spend minus previous completed-month AWS spend, divided by the prior month. Estimated current months have no comparable percentage.",
      source:"aia_infra.aws_costs / completed months only",drill:{kind:"aws-month"}},
    {id:"accounts",label:"Billed AWS accounts",value:current?us(current.accounts):"—",
      period:period,caption:"Distinct linked accounts with cost rows",
      definition:"Count of distinct LINKED_ACCOUNT values represented in recorded Cost Explorer rows for this month. It does not imply that each account is active or healthy.",
      source:"aia_infra.aws_costs · linked_account",drill:{kind:"accounts"}},
    {id:"services",label:"Cost categories",value:current?us(current.services):"—",
      period:period,caption:"Services, taxes and commitments",
      definition:"Distinct Cost Explorer SERVICE dimensions observed during the selected month. Financial lines such as Tax and Savings Plans are included as categories.",
      source:"aia_infra.aws_costs · service",drill:{kind:"services"}},
  ];
  const billMetrics:Metric[]=[
    {id:"bills",label:"Bills processed",value:bill?us(bill.docs):"—",
      unit:bill?"bills":undefined,period:period,caption:bill?us(bill.companies)+" companies in the captured records":"Capture starts Aug 2026",
      definition:"Count of distinct prediction records in the bill_costs source grouped by the UTC month of creation. Includes reviewed, needs-review, and deleted statuses.",
      source:"aia_infra.bill_costs · prediction_uuid; captured 11 Oct 2026",drill:{kind:"bill-month"}},
    {id:"unit-cost",label:"Avg measured cost / bill",value:bill?.avg_measured!=null?dec(bill.avg_measured,5):"—",
      period:period,caption:"Only records with both components measured",
      definition:"Average total_cost over bills with non-null extraction_cost and enrichment_cost in the selected UTC month. Records with missing cost components are excluded, not treated as free.",
      source:"aia_infra.bill_costs; currency not recorded",drill:{kind:"bill-month"}},
    {id:"bill-total",label:"Recorded processing cost",value:bill?dec(bill.total,2):"—",
      unit:bill?"units":undefined,period:period,caption:"Source-native units · Currency unconfirmed",
      definition:"Sum of total_cost stored in the bill-cost table. Some missing components default to zero; it must not be presented as final invoiced spend or combined with AWS USD.",
      source:"aia_infra.bill_costs · total_cost; currency not recorded",drill:{kind:"bill-month"}},
    {id:"missing",label:"Incomplete cost records",value:bill?us(bill.incomplete):"—",
      unit:bill?"bills":undefined,period:period,
      caption:bill?pct(bill.docs?bill.incomplete/bill.docs*100:0)+" missing one or both components":"Capture starts Aug 2026",
      definition:"Bill records where either extraction_cost or enrichment_cost is null in the selected month. These records are excluded from measured unit-cost averages even when total_cost defaults to zero.",
      source:"aia_infra.bill_costs · extraction_cost / enrichment_cost",drill:{kind:"bill-month"}},
  ];
  const openInfo=(metric:Metric)=>setInfo({
    title:metric.label,logic:metric.definition,
    example:metric.caption,
    note:metric.source+". "+sourcePreview+".",
  });
  const reportInfo=(title:string,logic:string)=>setInfo({
    title,logic,example:"Select a chart value to inspect the captured source breakdown.",
    note:sourcePreview+". AWS values are USD; bill costs use unverified source-native units.",
  });
  return <>
    <main className="rd-page ed-page infra-page">
      <div className="rd-page-head ed-page-head">
        <div className="ed-page-copy">
          <div className="ed-titleline"><h1>Infrastructure Overview</h1></div>
          <p>Cloud spend, processing economics and source integrity</p>
          <p className="infra-preview-caption">Audited preview data · AWS as of 8 Oct · Bill processing as of 11 Oct</p>
        </div>
        <div className="ed-filters" role="group" aria-label="Infra reporting scope">
          <div className="ed-filter-label">
            <span>Reporting month</span>
            <CompactMenuSelect value={month} options={options} onChange={value=>setMonth(value)}
              ariaLabel="Select Infrastructure reporting month" className="ed-delivery-filter-select"/>
          </div>
        </div>
      </div>

      <section className="metrics-grid-section ed-section" aria-label="AWS cloud spending">
        <SectionHead title="AWS cloud spending" question="Where is AWS spend concentrated, and how is it changing?"/>
        <div className="ed-sprint-kpis ed-kpi-grid po-kpis">{awsMetrics.map(m=>
          <MetricCard key={m.id} metric={m} onDrill={openDrill} onInfo={openInfo}/>)}</div>
        <div className="ed-collection">
          <Surface title="Cloud cost trajectory"
            subtitle="Monthly AWS UnblendedCost · USD · Oct is incomplete"
            onInfo={()=>reportInfo("Cloud cost trajectory",
              "Each point is the sum of recorded monthly UnblendedCost across all accounts and services. The October estimate is not comparable with completed September.")}>
            <AwsSpendTrend months={data.awsMonths} selected={month} onSelect={setMonth}/>
          </Surface>
          <Surface half title="Top cost drivers"
            subtitle={"Ranked AWS service and financial categories · "+period}
            onInfo={()=>reportInfo("AWS cost drivers","Ranking uses the 11 highest monthly service-category totals captured from Cost Explorer. Financial lines are not technical services.")}>
            <ServiceDrivers rows={services} total={current?.usd??0} month={month}
              onSelect={key=>openDrill({kind:"service",key})}/>
          </Surface>
          <Surface half title="Linked account distribution"
            subtitle={"Top nine accounts · masked labels in preview · "+period}
            onInfo={()=>reportInfo("AWS account distribution",
              "Linked account spend is grouped from the same monthly AWS cost rows. Account identifiers are masked; remaining accounts are included in overall totals.")}>
            <AccountDistribution rows={accounts} total={current?.usd??0}
              onSelect={key=>openDrill({kind:"account",key})}/>
          </Surface>
        </div>
      </section>

      <section className="metrics-grid-section ed-section" aria-label="Bill processing economics">
        <SectionHead title="Bill processing economics" question="How many bills do we process, and what does each one cost?"/>
        <div className="ed-sprint-kpis ed-kpi-grid po-kpis">{billMetrics.map(m=>
          <MetricCard key={m.id} metric={m} onDrill={openDrill} onInfo={openInfo}/>)}</div>
        <div className="ed-collection">
          <Surface title="Volume versus unit economics"
            subtitle="Processed bills (left) · Mean measured processing cost (right) · Source units"
            onInfo={()=>reportInfo("Volume versus unit economics",
              "Monthly bill volume is the source count. The measured average uses only bills with non-null extraction and enrichment costs; the currency is not confirmed.")}>
            <BillVolumeEconomics months={data.billMonths} selected={month}
              onSelect={setMonth}/>
          </Surface>
          <Surface half title="Processing cost split"
            subtitle={"Extraction and enrichment · "+period+" · Recorded units"}
            onInfo={()=>reportInfo("Processing cost split",
              "The donut partitions the recorded processing-cost sum into extraction and enrichment components. Currency is not recorded.")}>
            <CostComposition bill={bill}/>
          </Surface>
          <Surface half title="Document type breakdown"
            subtitle={"Recorded bill volume and measured average · "+period}
            onInfo={()=>reportInfo("Document type breakdown",
              "The source doc_type dimension groups scanned, digital, handwritten, and unclassified bills. Measured averages exclude missing cost components.")}>
            <DocumentTypes rows={types} month={month}
              onSelect={key=>openDrill({kind:"doc-type",key})}/>
          </Surface>
          <Surface title="Daily processing workload"
            subtitle="Daily volume for the selected reporting period · Asia/Kolkata"
            onInfo={()=>reportInfo("Daily processing workload",
              "Distinct processing records grouped by IST calendar day. UTC month selection may differ at day boundaries, so daily sums may not exactly equal UTC-month KPI counts.")}>
            <DailyBillVolume rows={data.billDays} month={month}/>
          </Surface>
        </div>
      </section>

      <section className="metrics-grid-section ed-section" aria-label="Data confidence">
        <SectionHead title="Data confidence" question="How recent and complete is the information?"/>
        <div className="ed-collection">
          <Surface title="Source integrity"
            subtitle="Latest captured observations · Explicit availability and reconciliation checks"
            onInfo={()=>reportInfo("Source integrity",
              "AWS import metadata is recorded by aws_cost_sync_runs. Detail-to-reference parity has a small rounding difference. Bill-processing refresh is established by loaded_at, but the originating producer has not been identified.")}>
            <div className="ed-table-shell infra-health-shell">
              <table className="ed-report-table infra-health-table">
                <thead><tr><th>Data source</th><th>Last observed</th><th>Coverage</th><th>Verification</th></tr></thead>
                <tbody>
                  <tr><th>AWS Cost Explorer</th><td>{dateText(data.awsRun.finishedAt)}</td>
                    <td>{us(data.awsRun.months)} months · {us(data.awsRun.accounts)} accounts</td>
                    <td>{usd(Math.abs(data.awsRun.referenceUsd-data.awsRun.storedDetailUsd))} stored difference</td></tr>
                  <tr><th>Bill processing costs</th><td>{dateText(data.billAsOf)}</td>
                    <td>{us(data.billMonths.reduce((s,r)=>s+r.docs,0))} bills · Aug–Oct</td>
                    <td>{us(data.billMonths.reduce((s,r)=>s+r.incomplete,0))} incomplete cost records</td></tr>
                  <tr><th>October AWS period</th><td>{dateText(data.awsAsOf)}</td>
                    <td>Month to date</td><td>Estimated · not final</td></tr>
                </tbody>
              </table>
            </div>
            <div className="ed-surface-foot infra-confidence-foot">
              <span>Preview only. AWS account failures may be tolerated by the current ingestion function.</span>
              <button className="ed-cell-drill" type="button" onClick={()=>openDrill({kind:"health"})}>
                Inspect data confidence <span aria-hidden="true">↗</span>
              </button>
            </div>
          </Surface>
        </div>
      </section>
    </main>
    {info?<MetricsInfoDialog definition={info} onClose={()=>setInfo(null)} sectionLabel="Infrastructure Metrics"/>:null}
    {drill?<BreakdownDialog key={drill.kind+":"+(drill.key??"")} target={drill} data={data}
      month={month} onClose={closeDrill} onNext={setDrill}/>:null}
  </>;
}
