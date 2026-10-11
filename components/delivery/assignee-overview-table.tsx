"use client";

import { useEffect,useMemo,useRef,useState } from "react";
import type { MouseEvent } from "react";
import { useRouter } from "next/navigation";
import type { AssigneeMatrix,AssigneeRow,MatrixCounts } from "../../lib/delivery/assignee-matrix";
import { UNTAGGED_MODULE } from "../../lib/delivery/assignee-matrix";
import type { AssigneeMatrixScope,DeliveryFilters } from "../../lib/delivery/types";
import DeliveryEvidenceModal from "./delivery-evidence-modal";
import { prefetchEvidencePage } from "./evidence-prefetch";
import CompactMenuSelect from "../ui/compact-menu-select";
import { resetAssigneeToolbarFilters } from "../../lib/delivery/assignee-filter-url";
import MetricsInfoDialog, {
  metricsInfoDefinitions,
  MetricsInfoButton,
} from "../ui/metrics-info";

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
export default function AssigneeOverviewTable({data}: {data:AssigneeMatrix}){
  const router=useRouter();
  const [query,setQuery]=useState("");
  const [sort,setSort]=useState<SortCol>("open");
  const [direction,setDirection]=useState<"asc"|"desc">("desc");
  const [expanded,setExpanded]=useState<Set<string>>(()=>new Set());
  const [allModules,setAllModules]=useState(false);
  const [filtersOpen,setFiltersOpen]=useState(false);
  const [columnsOpen,setColumnsOpen]=useState(false);
  const [sprintOpen,setSprintOpen]=useState(false);
  const [drill,setDrill]=useState<Target|null>(null);
  const [infoOpen,setInfoOpen]=useState(false);
  const infoTrigger=useRef<HTMLButtonElement|null>(null);
  const openInfo=(event:MouseEvent<HTMLButtonElement>)=>{
    event.preventDefault();
    event.stopPropagation();
    infoTrigger.current=event.currentTarget;
    setInfoOpen(true);
  };
  const sourceButton=useRef<HTMLButtonElement|null>(null);
  const sprintTrigger=useRef<HTMLButtonElement|null>(null);
  const scrollRef=useRef<HTMLDivElement|null>(null);
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
  const moduleOptions=[{value:"",label:"All modules"},
    {value:"__untagged__",label:"Untagged"},
    ...data.options.modules.map(m=>({value:m,label:m}))];
  const submoduleOptions=[{value:"",label:"All sub-modules"},
    {value:"__untagged__",label:"Untagged"},
    ...data.options.sub_modules.map(m=>({value:m,label:m}))];
  const severityOptions=[{value:"",label:"All severities"},
    ...data.options.severities.map(s=>({value:s,label:s}))];
  const tableMinWidth=462+numericColumns.length*94;
  // Sparse filtered views keep few numeric columns; cap the fixed-layout
  // stretch at ~190px per column so cells never balloon across wide cards.
  const tableMaxWidth=462+numericColumns.length*190;
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
  // Sparse filtered views hug their content: when the toolbar + table fit in
  // the space the viewport offers, the card gets a definite height and never
  // leaves a dead strip below the sticky footer. Tall tables fall back to the
  // original viewport-fill card and scroll internally exactly as before.
  const [cardStyle,setCardStyle]=useState<Record<string,string|number>|null>(null);
  useEffect(()=>{
    const measure=()=>{
      const section=scrollRef.current?.closest("section");
      const toolbar=section?.querySelector<HTMLElement>(".po-record-toolbar");
      const table=scrollRef.current?.querySelector<HTMLElement>("table");
      if(!section||!toolbar||!table)return;
      const available=window.innerHeight
        -section.getBoundingClientRect().top-14;
      const content=toolbar.offsetHeight+table.offsetHeight+2;
      setCardStyle(content<=available
        ?{flex:"0 0 auto",height:content}:null);
    };
    measure();
    window.addEventListener("resize",measure);
    return()=>window.removeEventListener("resize",measure);
  },[data,sorted.length,expanded,query,allModules]);
  const changeSort=(next:SortCol)=>{
    if(sort===next)setDirection(previous=>previous==="asc"?"desc":"asc");
    else{setSort(next);setDirection(next==="name"?"asc":"desc");}
  };
  const selectedSort=(key:string):"ascending"|"descending"|undefined=>
    sort===key?(direction==="asc"?"ascending":"descending"):undefined;
  const updateFilter=(key:"module"|"sub_module"|"severity",value:string)=>{
    const url=new URLSearchParams(window.location.search);
    if(value)url.set(key,value);else url.delete(key);
    const q=url.toString();
    router.replace("/delivery/assignees"+(q?"?"+q:""),{scroll:false});
    setFiltersOpen(false);
  };
  const resetFilters=()=>{
    router.replace(
      resetAssigneeToolbarFilters(new URLSearchParams(window.location.search)),
      {scroll:false},
    );
    setFiltersOpen(false);
  };
  // The heading scope chip selects the reporting sprint only; module and
  // sub-module scoping stay in the toolbar Filters menu.
  const sprintLabel=data.filters.sprint==null?"All sprints":
    (data.options.sprints.find(s=>s.sprint_id===data.filters.sprint)
      ?.sprint_name??"Sprint "+data.filters.sprint).replace(/^SPEND /,"");
  const applySprint=(id:number|null)=>{
    const url=new URLSearchParams(window.location.search);
    if(id)url.set("sprint",String(id));else url.delete("sprint");
    const q=url.toString();
    router.replace("/delivery/assignees"+(q?"?"+q:""),{scroll:false});
    setSprintOpen(false);
    requestAnimationFrame(()=>sprintTrigger.current?.focus({preventScroll:true}));
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
        <span className="global-control-label">Reporting scope</span>
        <div className="assignee-scope-wrap">
          <button type="button" ref={sprintTrigger} className="ui-control date-trigger"
            aria-label={"Reporting scope: "+sprintLabel}
            aria-expanded={sprintOpen}
            onClick={()=>{setFiltersOpen(false);setColumnsOpen(false);setSprintOpen(v=>!v);}}>
            <svg className="icon" viewBox="0 0 24 24" aria-hidden="true">
              <rect x="4" y="5" width="16" height="16" rx="2"/>
              <path d="M8 3v4m8-4v4M4 10h16m-12 4h2m4 0h2"/>
            </svg>
            <span>{sprintLabel}</span>
            <span className="chevron"><Icon name="down"/></span>
          </button>
          {sprintOpen?<div className="companies-filter-popover po-filters assignee-sprint-menu">
            <div className="po-filter-head"><strong>Reporting sprint</strong>
              <button type="button" onClick={()=>setSprintOpen(false)}>Close</button>
            </div>
            <button type="button" className="assignee-option"
              aria-pressed={data.filters.sprint==null} onClick={()=>applySprint(null)}>
              All sprints
            </button>
            {data.options.sprints.map(s=><button type="button" key={s.sprint_id}
              className="assignee-option" aria-pressed={data.filters.sprint===s.sprint_id}
              onClick={()=>applySprint(s.sprint_id)}>
              {s.sprint_name.replace(/^SPEND /,"")} · {s.state}
            </button>)}
          </div>:null}
        </div>
      </div>
    </div>
    <div className="metrics-section-kicker">
      <span>Assignee workload</span>
      <span className="metrics-section-description">Open work · Current issue state</span>
    </div>
    <section className="companies-records po-record-layout companies-monthly-records companies-grid-card"
      aria-label="Assignee workload matrix"
      style={{maxWidth:tableMaxWidth+2,...(cardStyle??{})}}>
      {/* +2 covers the card's 1px borders, so the table fills the capped card
        edge-to-edge and filtered views never show empty space inside it. */}
      <div className="po-record-toolbar companies-command-bar">
        <div className="companies-toolbar-meta">
          <strong>{fmt(data.totals.assignees)} assignees · {fmt(data.totals.open)} open issues</strong>
          <span>{fmt(data.totals.stale)} stale · {fmt(data.totals.blocked)} blocked · {fmt(data.totals.untagged)} untagged · updated {pretty(data.synced_at)}</span>
        </div>
        <div className="po-record-tools">
          <MetricsInfoButton
            label="How assignee workload is counted"
            onClick={openInfo}
          />
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
              (data.filters.module||data.filters.sub_module||data.filters.severity?" has-filters":"")}
              aria-expanded={filtersOpen} onClick={()=>{setColumnsOpen(false);setSprintOpen(false);setFiltersOpen(v=>!v);}}>
              <Icon name="filter"/><span>Filters</span>
              {(data.filters.module||data.filters.sub_module||data.filters.severity)?<span className="companies-filter-badge">
                {Number(!!data.filters.module)+Number(!!data.filters.sub_module)+Number(!!data.filters.severity)}</span>:null}
            </button>
            {filtersOpen?<div className="companies-filter-popover po-filters">
              <div className="po-filter-head">
                <strong>Filter assignees</strong>
                <button type="button" disabled={!data.filters.module&&!data.filters.sub_module&&!data.filters.severity}
                  onClick={resetFilters}>Reset</button>
              </div>
              <div className="assignee-filter-field"><span>Module</span>
                <CompactMenuSelect value={data.filters.module??""}
                  options={moduleOptions} onChange={value=>updateFilter("module",value)}
                  ariaLabel="Filter by module" className="assignee-filter-select"/>
              </div>
              <div className="assignee-filter-field"><span>Sub-module</span>
                <CompactMenuSelect value={data.filters.sub_module??""}
                  options={submoduleOptions} onChange={value=>updateFilter("sub_module",value)}
                  ariaLabel="Filter by sub-module" className="assignee-filter-select"/>
              </div>
              <div className="assignee-filter-field"><span>Severity</span>
                <CompactMenuSelect value={data.filters.severity??""}
                  options={severityOptions} onChange={value=>updateFilter("severity",value)}
                  ariaLabel="Filter by severity" className="assignee-filter-select"/>
              </div>
              <div className="po-filter-note">Filters apply to every cell and its Jira issue drill.</div>
            </div>:null}
          </div>
          <div className="companies-filter-wrap assignee-columns-wrap">
            <button type="button" className="ui-control companies-filter-trigger"
              aria-expanded={columnsOpen}
              onClick={()=>{setFiltersOpen(false);setSprintOpen(false);setColumnsOpen(v=>!v);}}>
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
        </div>
      </div>
      <div ref={scrollRef} className="po-record-scroll companies-monthly-scroll" role="region"
        tabIndex={0} aria-label="Assignee by module matrix, scroll horizontally to inspect modules">
        <table className="po-user-table companies-table companies-monthly-table assignee-monthly-table"
          aria-label="Jira open issues by assignee and module" style={{minWidth:tableMinWidth,maxWidth:tableMaxWidth}}>
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
    {drill?<DeliveryEvidenceModal target={drill} data={data} filters={data.filters}
      onClose={()=>{
        setDrill(null);
        requestAnimationFrame(()=>sourceButton.current?.focus({preventScroll:true}));
      }}/>:null}
    {infoOpen?<MetricsInfoDialog definition={metricsInfoDefinitions.assignee_workload}
      onClose={()=>{
        setInfoOpen(false);
        requestAnimationFrame(()=>infoTrigger.current?.focus({preventScroll:true}));
      }}/>:null}
  </main>;
}
