"use client";

import { useId, useState } from "react";
import type {
  InfraAwsMonth, InfraAwsService, InfraAwsAccount, InfraBillMonth,
  InfraDocType, InfraBillDay,
} from "../../lib/infra/types";

const money = (n:number) => new Intl.NumberFormat("en-US",{
  style:"currency",currency:"USD",maximumFractionDigits:2,
}).format(n);
const integer = (n:number) => new Intl.NumberFormat("en-US").format(n);
const numeric = (n:number,d=2) => n.toLocaleString("en-US",{
  minimumFractionDigits:d,maximumFractionDigits:d,
});
const labelMonth = (s:string) => new Date(s+"-01T12:00:00Z")
  .toLocaleDateString("en-GB",{month:"short",year:"2-digit",timeZone:"UTC"});
const shortService = (s:string) => ({
  "Amazon Relational Database Service":"Amazon RDS",
  "Amazon Elastic Container Service":"Amazon ECS",
  "Savings Plans for AWS Compute usage":"Savings Plans",
  "AmazonCloudWatch":"CloudWatch",
  "Amazon Elastic Load Balancing":"Load Balancing",
  "Amazon EC2 Container Registry (ECR)":"Amazon ECR",
  "Amazon Virtual Private Cloud":"Amazon VPC",
  "Amazon Simple Storage Service":"Amazon S3",
  "Amazon ElastiCache":"ElastiCache",
} as Record<string,string>)[s] ?? s;
const smoothPath = (points: Array<{x:number;y:number}>):string => {
  if(!points.length)return "";
  let d="M "+points[0].x+" "+points[0].y;
  for(let i=1;i<points.length;i++){
    const a=points[i-1],b=points[i],mid=(a.x+b.x)/2;
    d+=" C "+mid+" "+a.y+", "+mid+" "+b.y+", "+b.x+" "+b.y;
  }
  return d;
};

/** Native SVG report body inside the existing Product/Engineering report card. */
export function AwsSpendTrend({months,selected,onSelect}:{
  months:InfraAwsMonth[]; selected:string; onSelect:(month:string)=>void;
}){
  const rawId=useId(),id="infra-spend-"+rawId.replace(/:/g,"");
  const [hover,setHover]=useState<string|null>(null);
  const width=940,height=270,left=62,right=23,top=22,bottom=44;
  const base=height-bottom, plotH=base-top;
  const maximum=Math.ceil(Math.max(1,...months.map(m=>m.usd))/1000)*1000;
  const points=months.map((m,i)=>({
    x:left+(months.length===1?0:i*(width-left-right)/(months.length-1)),
    y:base-m.usd/maximum*plotH,month:m.month,usd:m.usd,estimated:m.estimated,
  }));
  const active=months.find(x=>x.month===(hover??selected))??months[months.length-1];
  const line=smoothPath(points),area=points.length?
    line+" L "+points[points.length-1].x+" "+base+" L "+points[0].x+" "+base+" Z":"";
  return <div className="infra-chart-shell">
    <svg viewBox={"0 0 "+width+" "+height} className="infra-svg-chart"
      role="group" aria-label="AWS monthly UnblendedCost chart; select a month for details">
      <defs>
        <linearGradient id={id} x1="0" x2="0" y1="0" y2="1">
          <stop offset="0%" stopColor="#5276d9" stopOpacity=".22"/>
          <stop offset="100%" stopColor="#5276d9" stopOpacity=".012"/>
        </linearGradient>
      </defs>
      {[0,.25,.5,.75,1].map(t=>{
        const y=base-t*plotH;
        return <g key={t}><path d={"M "+left+" "+y+" H "+(width-right)}
          stroke="#e9edf5" strokeDasharray={t===0?"":"3 5"} strokeWidth="1"/>
          <text x={left-12} y={y+4} textAnchor="end" className="infra-axis-label">
            {t===0?"0":"$"+numeric(maximum*t/1000,maximum<1000?1:0)+"k"}
          </text></g>;
      })}
      <path d={area} fill={"url(#"+id+")"}/>
      <path d={line} fill="none" stroke="#365fd3" strokeWidth="3" strokeLinejoin="round"
        strokeLinecap="round"/>
      {points.map(p=>{
        const activePoint=p.month===(hover??selected),w=months.length>1?(width-left-right)/(months.length-1):70;
        return <g key={p.month} role="button" tabIndex={0}
          aria-label={labelMonth(p.month)+": "+money(p.usd)+(p.estimated?", estimated":"")+". View monthly breakdown."}
          onMouseEnter={()=>setHover(p.month)} onMouseLeave={()=>setHover(null)}
          onFocus={()=>setHover(p.month)} onBlur={()=>setHover(null)}
          onClick={()=>onSelect(p.month)}
          onKeyDown={e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();onSelect(p.month);}}}>
          <rect x={p.x-w/2} y={top} width={w} height={base-top+12} fill="transparent" className="infra-point-hit"/>
          {activePoint?<path d={"M "+p.x+" "+top+" V "+base} stroke="#8da7ea"
            strokeDasharray="4 5" strokeWidth="1"/>:null}
          {activePoint?<circle cx={p.x} cy={p.y} r="10" fill="#e6edff"/>:null}
          <circle cx={p.x} cy={p.y} r={activePoint?5:3.5} fill="#fff"
            stroke="#365fd3" strokeWidth={activePoint?3:2}/>
          <text x={p.x} y={base+24} textAnchor="middle"
            className={"infra-axis-label"+(activePoint?" is-active":"")}>
            {labelMonth(p.month).split(" ")[0]}
          </text>
          <title>{labelMonth(p.month)} · {money(p.usd)}</title>
        </g>;
      })}
    </svg>
    {active?<div className="infra-chart-summary">
      <div><span>{labelMonth(active.month)} AWS spend</span>
        <strong>{money(active.usd)}</strong>
      </div>
      <div><span>Reporting</span><strong>{active.estimated?"Estimated · partial month":"Completed month"}</strong></div>
      <span className="infra-chart-hint">Select a point to inspect services and accounts <span aria-hidden="true">↗</span></span>
    </div>:null}
  </div>;
}

export function ServiceDrivers({rows,total,month,onSelect}:{
  rows:InfraAwsService[];total:number;month:string;
  onSelect:(service:string)=>void;
}){
  if(!rows.length)return <div className="infra-chart-empty">Service breakdowns in this preview begin in May 2026.</div>;
  const sorted=[...rows].sort((a,b)=>b.usd-a.usd);
  const max=Math.max(1,...sorted.map(x=>x.usd));
  const display=sorted.slice(0,7);
  return <div className="infra-drivers">
    <div className="infra-list-head"><span>Service / category</span><span>Contribution</span><span>Spend</span></div>
    {display.map((row,i)=><button type="button" key={row.service}
      className="infra-driver-row"
      onClick={()=>onSelect(row.service)}
      aria-label={shortService(row.service)+", "+money(row.usd)+", "+
        numeric(total>0?row.usd/total*100:0,1)+" percent. View service breakdown."}>
      <span className="infra-driver-name"><i className="infra-swatch" style={{backgroundColor:i===0?"#365fcd":"#7894df"}}/>
        <span>{shortService(row.service)}</span>
      </span>
      <span className="infra-driver-track"><i style={{width:(row.usd/max*100)+"%",
        backgroundColor:i===0?"#365fcd":"#89a4e9"}}/></span>
      <strong>{money(row.usd)}</strong>
    </button>)}
    <div className="infra-list-footer">
      <span>Top {display.length} categories · {labelMonth(month)}</span>
      <span>{numeric(total?display.reduce((s,r)=>s+r.usd,0)/total*100:0,1)}% of spend shown</span>
    </div>
  </div>;
}

export function AccountDistribution({rows,total,onSelect}:{
  rows:InfraAwsAccount[];total:number;onSelect:(name:string)=>void;
}){
  if(!rows.length)return <div className="infra-chart-empty">Account breakdowns in this preview begin in May 2026.</div>;
  const sorted=[...rows].sort((a,b)=>b.usd-a.usd);
  const max=Math.max(1,...sorted.map(x=>x.usd));
  return <div className="ed-table-shell infra-accounts-scroll" role="region"
    tabIndex={0} aria-label="Linked account spend distribution, anonymized for preview">
    <table className="ed-report-table infra-accounts-table">
      <thead><tr><th scope="col">AWS account</th><th scope="col">Share of spend</th>
        <th scope="col">Amount</th><th scope="col">Share</th></tr></thead>
      <tbody>
        {sorted.map(row=><tr key={row.label}>
          <th scope="row"><button type="button" className="ed-cell-drill"
              onClick={()=>onSelect(row.label)}>{row.label}<span aria-hidden="true">↗</span></button></th>
          <td><div className="ed-flow-track"><span style={{width:(row.usd/max*100)+"%"}}/></div></td>
          <td className="infra-table-num">{money(row.usd)}</td>
          <td className="infra-table-num">{numeric(total?row.usd/total*100:0,1)}%</td>
        </tr>)}
      </tbody>
    </table>
  </div>;
}
