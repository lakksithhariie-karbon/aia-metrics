"use client";

import { useMemo,useRef,useState } from "react";
import { useRouter } from "next/navigation";
import type { AssigneeMatrix,AssigneeRow,MatrixCounts } from "../../lib/delivery/assignee-matrix";
import { UNTAGGED_MODULE } from "../../lib/delivery/assignee-matrix";
import type { AssigneeMatrixScope,DeliveryFilters } from "../../lib/delivery/types";
import DeliveryEvidenceModal from "./delivery-evidence-modal";
import { prefetchEvidencePage } from "./evidence-prefetch";

type Target={
  key:string;label:string;sprintId:number|null;
  expectedCount:number;detailNote:string;matrixScope:AssigneeMatrixScope;
};
type DisplayModule={key:string;name:string};
type SortCol="open"|"name"|"stale"|"blocked"|string;
const nf=new Intl.NumberFormat("en-IN");
const fmt=(value:number)=>nf.format(value);
const pretty=(date:string)=>{
  const value=new Date(date);
  return Number.isNaN(value.getTime())?"Unavailable":
    new Intl.DateTimeFormat("en-GB",{
      day:"2-digit",month:"short",hour:"2-digit",minute:"2-digit",
      hourCycle:"h23",timeZone:"Asia/Kolkata",
    }).format(value)+" IST";
};
function Icon({name}:{name:"search"|"filter"|"right"|"down"|"sort"|"up"|"close"|"grid"}){
  return <svg className="icon" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
    {name==="search"?<><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4.5 4.5"/></>:
    name==="filter"?<path d="M3 4h18l-7 8v7l-4 2v-9z"/>:
    name==="right"?<path d="m10 6 6 6-6 6"/>:
    name==="down"?<path d="m7 10 5 5 5-5"/>:
    name==="up"?<path d="m7 14 5-5 5 5"/>:
    name==="sort"?<path d="M8 4v16m-3-3 3 3 3-3M16 20V4m-3 3 3-3 3 3"/>:
    name==="close"?<path d="m6 6 12 12M18 6 6 18"/>:
    <><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></>}
  </svg>;
}
const valueIn=(row:MatrixCounts,column:string,featured:ReadonlySet<string>):number=>{
  if(column==="__other__")return Object.entries(row.modules)
    .reduce((sum,[key,n])=>sum+(key!==UNTAGGED_MODULE&&!featured.has(key)?n:0),0);
  if(column==="__stale__")return row.stale;
  if(column==="__blocked__")return row.blocked;
  return row.modules[column]??0;
};
const escapeCSV=(raw:string|number):string=>{
  const val=String(raw);
  const guarded=/^[\s]*[=+@-]/.test(val)?"'"+val:val;
  return '"'+guarded.replace(/"/g,'""')+'"';
};
export default function AssigneeOverviewTable({data}: {data:AssigneeMatrix}){
  const router=useRouter();
  const [query,setQuery]=useState("");
  const [sort,setSort]=useState<SortCol>("open");
  const [direction,setDirection]=useState<"asc"|"desc">("desc");
  const [expanded,setExpanded]=useState<Set<string>>(()=>new Set());
  const [allModules,setAllModules]=useState(false);
  const [filtersOpen,setFiltersOpen]=useState(false);
  const [columnsOpen,setColumnsOpen]=useState(false);
  const [drill,setDrill]=useState<Target|null>(null);
  const sourceButton=useRef<HTMLButtonElement|null>(null);
  const hoverTimer=useRef<ReturnType<typeof setTimeout>|null>(null);
  const available=data.modules.filter(m=>m.key!==UNTAGGED_MODULE);
  const featured=available.slice(0,5);
  const included=allModules?available:featured;
  const featuredKeys=useMemo(()=>new Set(included.map(m=>m.key)),[allModules,data.modules]);
  const modules:Array<DisplayModule>=[
    ...included.map(m=>({key:m.key,name:m.name})),
    ...(!allModules&&available.length>featured.length?[{key:"__other__",name:"Other"}]:[]),
    {key:UNTAGGED_MODULE,name:"Untagged"},
  ];
  const numericColumns=[...modules,{key:"__stale__",name:"Stale"},
    {key:"__blocked__",name:"Blocked"}];
  const tableMinWidth=462+numericColumns.length*94;
  const sorted=useMemo(()=>{
    const needle=query.trim().toLocaleLowerCase();
    const matched=data.assignees.filter(row=>!needle||
      row.name.toLocaleLowerCase().includes(needle));
    return [...matched].sort((a,b)=>{
      const av=sort==="name"?a.name.toLocaleLowerCase():
        sort==="open"?a.open:valueIn(a,sort,featuredKeys);
      const bv=sort==="name"?b.name.toLocaleLowerCase():
        sort==="open"?b.open:valueIn(b,sort,featuredKeys);
      const compared=av<bv?-1:av>bv?1:0;
      return compared?(direction==="asc"?compared:-compared):
        a.name.localeCompare(b.name);
    });
  },[data.assignees,query,sort,direction,featuredKeys]);
  const totals=useMemo(()=>{
    const result:MatrixCounts={open:0,stale:0,blocked:0,modules:{}};
    for(const row of sorted){
      result.open+=row.open;result.stale+=row.stale;result.blocked+=row.blocked;
      for(const [name,n] of Object.entries(row.modules))
        result.modules[name]=(result.modules[name]??0)+n;
    }
    return result;
  },[sorted]);
  const changeSort=(next:SortCol)=>{
    if(sort===next)setDirection(previous=>previous==="asc"?"desc":"asc");
    else{setSort(next);setDirection(next==="name"?"asc":"desc");}
  };
  const selectedSort=(key:string):"ascending"|"descending"|undefined=>
    sort===key?(direction==="asc"?"ascending":"descending"):undefined;
  const updateFilter=(key:"sprint"|"severity",value:string)=>{
    const url=new URLSearchParams(window.location.search);
    if(value)url.set(key,value);else url.delete(key);
    const q=url.toString();
    router.replace("/delivery/assignees"+(q?"?"+q:""),{scroll:false});
    setFiltersOpen(false);
  };
  const targetFor=(row:AssigneeRow|null,issueType:string|undefined,
    column:string,n:number):Target=>{
    const assignee=row?.key==="__unassigned__"?null:row?.key;
    const isStale=column==="__stale__",isBlocked=column==="__blocked__";
    const area=isStale?"Stale":isBlocked?"Blocked":
      column==="__all__"?"Open work":
      column==="__other__"?"Other modules":
      column===UNTAGGED_MODULE?"Untagged":column;
    const mode=column==="__all__"||isStale||isBlocked?"all":
      column==="__other__"?"other":"single";
    const matrixScope:AssigneeMatrixScope={
      ...(row?{assignee}:{}),moduleMode:mode,
      ...(mode==="single"?{module:column}:{}),
      ...(mode==="other"?{excludedModules:included.map(x=>x.key)}:{}),
      ...(issueType?{issueType}:{}),
    };
    return {
      key:isStale?"matrix:stale":isBlocked?"matrix:blocked":"matrix:open",
      label:[row?.name??"All assignees",issueType,area].filter(Boolean).join(" · "),
      sprintId:data.filters.sprint,
      expectedCount:n,detailNote:area,
      matrixScope,
    };
  };
  const prefetch=(target:Target)=>{
    if(target.expectedCount===0)return;
    prefetchEvidencePage({
      key:target.key,snapshot_id:data.snapshot_id,filters:data.filters,
      matrix_scope:target.matrixScope,expected_count:target.expectedCount,
      offset:0,search:"",sort:"created_at",direction:"desc",
    });
  };
  const beginHover=(target:Target)=>{
    if(hoverTimer.current!==null)clearTimeout(hoverTimer.current);
    hoverTimer.current=setTimeout(()=>prefetch(target),140);
  };
  const cancelHover=()=>{
    if(hoverTimer.current!==null)clearTimeout(hoverTimer.current);
    hoverTimer.current=null;
  };
  const cell=(row:AssigneeRow|null,counts:MatrixCounts,
    column:string,issueType?:string)=>{
    const value=column==="__all__"?counts.open:valueIn(counts,column,featuredKeys);
    const target=targetFor(row,issueType,column,value);
    return <td className="numeric" key={column}>
      <button type="button" className={"companies-module-button"+(value===0?" is-zero":"")}
        title={target.label+": "+fmt(value)+" issues"}
        aria-label={target.label+": "+fmt(value)+" issues. View Jira issues"}
        onMouseEnter={()=>beginHover(target)} onMouseLeave={cancelHover}
        onFocus={()=>prefetch(target)}
        onClick={event=>{
          cancelHover();sourceButton.current=event.currentTarget;prefetch(target);setDrill(target);
        }}>{fmt(value)}</button>
    </td>;
  };
  const exportCSV=()=>{
    const columns=["Assignee","Issue type","Open",...numericColumns.map(x=>x.name)];
    const lines=[columns.map(escapeCSV).join(",")];
    for(const row of sorted){
      const values=(counts:MatrixCounts,type:string)=>[
        row.name,type,counts.open,
        ...numericColumns.map(column=>valueIn(counts,column.key,featuredKeys)),
      ];
      lines.push(values(row,"").map(escapeCSV).join(","));
      if(expanded.has(row.key))for(const type of row.types){
        lines.push(values(type,type.type).map(escapeCSV).join(","));
      }
    }
    const blob=new Blob(["\uFEFF"+lines.join("\r\n")],{type:"text/csv;charset=utf-8"});
    const url=URL.createObjectURL(blob);
    const anchor=document.createElement("a");
    anchor.href=url;anchor.download="jira-assignee-overview.csv";
    document.body.appendChild(anchor);anchor.click();anchor.remove();
    setTimeout(()=>URL.revokeObjectURL(url),1000);
  };
  const renderNumbers=(row:AssigneeRow,counts:MatrixCounts,issueType?:string)=>[
    ...modules.map(m=>cell(row,counts,m.key,issueType)),
    cell(row,counts,"__stale__",issueType),
    cell(row,counts,"__blocked__",issueType),
  ];
  const showTotal=()=>{
    return <tr className="companies-total-row">
      <td/><td className="companies-total-label">{fmt(totals.open)} open</td>
      <td className="companies-total-count">{fmt(sorted.length)} assignees</td>
      {numericColumns.map(m=><td key={m.key} className="numeric">
        {fmt(valueIn(totals,m.key,featuredKeys))}
      </td>)}
    </tr>;
  };
  const thSort=(key:string,label:string)=><th scope="col"
    aria-sort={selectedSort(key)}>
    <button type="button" onClick={()=>changeSort(key)}>
      {label}<Icon name={sort===key?(direction==="asc"?"up":"down"):"sort"}/>
    </button>
  </th>;
  return <main className="companies-page assignee-page" id="assignee-main">
    <div className="page-heading companies-page-heading">
      <div className="companies-title-block">
        <h1>Assignee Overview</h1>
        <p>Open Jira work by assignee, module and issue type</p>
      </div>
      <div className="global-controls assignee-current-scope">
        <span>Reporting scope</span>
        <span className="assignee-scope-value">Open work · Current issue state</span>
      </div>
    </div>
    <div className="metrics-section-kicker">
      <span>Assignee workload</span>
      <span className="metrics-section-description">Module ownership and attention</span>
    </div>
    <section className="companies-records po-record-layout companies-monthly-records companies-grid-card"
      aria-label="Assignee workload matrix">
      <div className="po-record-toolbar companies-command-bar">
        <div className="companies-toolbar-meta">
          <strong>{fmt(data.totals.assignees)} assignees · {fmt(data.totals.open)} open issues</strong>
          <span>{fmt(data.totals.stale)} stale · {fmt(data.totals.blocked)} blocked · {fmt(data.totals.untagged)} untagged</span>
        </div>
        <div className="po-record-tools">
          <div className="po-search">
            <Icon name="search"/>
            <input type="search" autoComplete="off" value={query}
              onChange={e=>setQuery(e.currentTarget.value)}
              placeholder="Search assignees..." aria-label="Search Jira assignees"/>
            {query?<button type="button" onClick={()=>setQuery("")} aria-label="Clear assignee search">
              <Icon name="close"/>
            </button>:null}
          </div>
          <div className="po-filter-wrap companies-filter-wrap">
            <button type="button" className={"ui-control companies-filter-trigger"+
              (data.filters.sprint||data.filters.severity?" has-filters":"")}
              aria-expanded={filtersOpen} onClick={()=>{setColumnsOpen(false);setFiltersOpen(v=>!v);}}>
              <Icon name="filter"/><span>Filters</span>
              {(data.filters.sprint||data.filters.severity)?<span className="companies-filter-badge">
                {Number(!!data.filters.sprint)+Number(!!data.filters.severity)}</span>:null}
            </button>
            {filtersOpen?<div className="companies-filter-popover po-filters">
              <div className="po-filter-head">
                <strong>Filter assignees</strong>
                <button type="button" disabled={!data.filters.sprint&&!data.filters.severity}
                  onClick={()=>router.replace("/delivery/assignees",{scroll:false})}>Reset</button>
              </div>
              <label htmlFor="assignee-sprint-filter">Sprint</label>
              <span className="ui-select-host"><select id="assignee-sprint-filter"
                className="ui-control ui-select-trigger"
                value={data.filters.sprint??""}
                onChange={e=>updateFilter("sprint",e.currentTarget.value)}>
                <option value="">All sprints</option>
                {data.options.sprints.map(s=><option key={s.sprint_id} value={s.sprint_id}>
                  {s.sprint_name.replace(/^SPEND /,"")} · {s.state}
                </option>)}
              </select></span>
              <label htmlFor="assignee-severity-filter">Severity</label>
              <span className="ui-select-host"><select id="assignee-severity-filter"
                className="ui-control ui-select-trigger"
                value={data.filters.severity??""}
                onChange={e=>updateFilter("severity",e.currentTarget.value)}>
                <option value="">All severities</option>
                {data.options.severities.map(s=><option key={s} value={s}>{s}</option>)}
              </select></span>
              <div className="po-filter-note">Filters apply to every cell and its Jira issue drill.</div>
            </div>:null}
          </div>
          <div className="companies-filter-wrap assignee-columns-wrap">
            <button type="button" className="ui-control companies-filter-trigger"
              aria-expanded={columnsOpen}
              onClick={()=>{setFiltersOpen(false);setColumnsOpen(v=>!v);}}>
              <Icon name="grid"/><span>Columns</span>
            </button>
            {columnsOpen?<div className="companies-filter-popover po-filters assignee-columns-menu">
              <div className="po-filter-head"><strong>Module columns</strong>
                <button type="button" onClick={()=>setColumnsOpen(false)}>Close</button>
              </div>
              <button type="button" className="assignee-option"
                aria-pressed={!allModules} onClick={()=>{setAllModules(false);setSort("open");setColumnsOpen(false);}}>
                Key modules + Other
              </button>
              <button type="button" className="assignee-option"
                aria-pressed={allModules} onClick={()=>{setAllModules(true);setSort("open");setColumnsOpen(false);}}>
                All modules ({fmt(available.length)})
              </button>
            </div>:null}
          </div>
          <button type="button" className="ui-control assignee-export" onClick={exportCSV}>
            Export CSV
          </button>
        </div>
      </div>
      <div className="po-record-scroll companies-monthly-scroll" role="region"
        tabIndex={0} aria-label="Assignee by module matrix, scroll horizontally to inspect modules">
        <table className="po-user-table companies-table companies-monthly-table assignee-monthly-table"
          aria-label="Jira open issues by assignee and module" style={{minWidth:tableMinWidth}}>
          <thead>
            <tr className="companies-month-header">
              <th scope="col"><span className="sr-only">Expand issue types</span></th>
              {thSort("open","Open issues")}
              {thSort("name","Assignee")}
              <th scope="colgroup" colSpan={modules.length} className="companies-month-group">
                Module distribution
              </th>
              <th scope="colgroup" colSpan={2} className="companies-month-group">
                Attention
              </th>
            </tr>
            <tr className="companies-module-header">
              <th aria-hidden="true" className="companies-frozen-header-spacer"/>
              <th aria-hidden="true" className="companies-frozen-header-spacer"/>
              <th aria-hidden="true" className="companies-frozen-header-spacer"/>
              {numericColumns.map(m=><th key={m.key} scope="col"
                aria-sort={selectedSort(m.key)}
                className={"numeric companies-module-head "+
                  (m.key==="AP"?"companies-module-ap":
                  m.key==="AR"?"companies-module-ar":
                  m.key==="__blocked__"?"assignee-attention-blocked":
                  m.key==="__stale__"?"assignee-attention-stale":"")}>
                <button type="button" title={m.name}
                  onClick={()=>changeSort(m.key)}>{m.name}
                  <Icon name={sort===m.key?(direction==="asc"?"up":"down"):"sort"}/></button>
              </th>)}
            </tr>
          </thead>
          <tbody>
            {sorted.length?sorted.flatMap(row=>{
              const open=expanded.has(row.key);
              const parent=<tr key={"owner:"+row.key} className={"companies-company-row"+(open?" po-expanded":"")}>
                <td className="companies-expander-cell">
                  <button type="button" className="po-expander"
                    aria-label={(open?"Collapse":"Expand")+" issue types for "+row.name}
                    aria-expanded={open} onClick={()=>setExpanded(previous=>{
                      const next=new Set(previous);if(next.has(row.key))next.delete(row.key);else next.add(row.key);return next;
                    })}><Icon name={open?"down":"right"}/></button>
                </td>
                {cell(row,row,"__all__")}
                <td className="companies-company-cell"><span className="companies-company-name">{row.name}</span></td>
                {renderNumbers(row,row)}
              </tr>;
              if(!open)return [parent];
              const children=row.types.map(type=><tr key={row.key+"|"+type.type} className="companies-nested-user-row">
                <td className="companies-expander-cell"/>
                {cell(row,type,"__all__",type.type)}
                <td className="companies-user-email">{type.type}</td>
                {renderNumbers(row,type,type.type)}
              </tr>);
              return [parent,...children];
            }):<tr><td colSpan={3+numericColumns.length}>
              <div className="po-empty"><strong>No assignees match</strong>
                <span>Try a different search or filter.</span></div>
            </td></tr>}
          </tbody>
          <tfoot>{showTotal()}</tfoot>
        </table>
      </div>
    </section>
    <footer className="assignee-page-footer">Last refresh: {pretty(data.synced_at)}</footer>
    {drill?<DeliveryEvidenceModal target={drill} data={data} filters={data.filters}
      onClose={()=>{
        setDrill(null);
        requestAnimationFrame(()=>sourceButton.current?.focus({preventScroll:true}));
      }}/>:null}
  </main>;
}
