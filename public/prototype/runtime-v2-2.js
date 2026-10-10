
/* Product Overview compatibility runtime: remaining charts and drills are demo fixtures.
 * The three live Overview KPI cards are owned by native React, never by this script.
 * Generated activity fixtures power usage charts and user/company tables.
 * Adoption / journey cohorts are independent. Reference-only mix and friction
 * are never fabricated for historical ranges that the screenshots do not supply.
 */
(() => {
 'use strict';
 const root=$('#overview-main');
 const overviewLatestAsOf=$('#prototype-surface')?.dataset.overviewAsOf||SNAPSHOT_DATE;
 const P={page:'overview',asof:overviewLatestAsOf,chartTables:{weekly:false,feature:false,mix:false},series:new Set(['ap','ar','txn']),mode:'wau',tab:'active',query:'',companyFilter:'all',integrationFilter:'all',sort:'last',dir:'desc',pageNo:1,pageSize:10,expanded:new Set(),company:null,companyUser:null,companyTrigger:null,companyTab:'overview',flowExpanded:new Set(['bills']),scope:'selected',moved:null,placeholder:null,drill:null,journeyModule:'ap',journeyExpanded:true,recordTrigger:null};
 const keys=['bills','invoices','statements','transactions','sync'];
 const flowDefs=COMPANY_FLOWS;
 const nf=v=>fmt.format(v);
 const pct=(n,d)=>d?(100*n/d).toFixed(1):null;
 const dateSpan=(a,b)=>a&&b?`${dateLabel(a)} ${a.slice(0,4)!==b.slice(0,4)?a.slice(0,4)+' ':''}– ${dateLabel(b)} ${b.slice(0,4)}`:'No reporting window';
 const total=ev=>ev.reduce((s,e)=>s+e.count,0);
 const inWindow=(e,start,end)=>e.date>=start&&e.date<=end;
 const wEvents=(ev,start,end)=>ev.filter(e=>inWindow(e,start,end));
 const unique=arr=>[...new Set(arr)];
 const countDays=ev=>new Set(ev.map(e=>e.date)).size;
 const nrate=v=>v===null?'Not available':v+'%';
 const groupSums=ev=>Object.fromEntries(keys.map(k=>[k,total(ev.filter(e=>e.flow===k))]));
 const previousMonthEnd=iso=>monthLast(shiftMonth(iso.slice(0,7),-1));
 const monthKeyToDate=k=>k+'-01';
 const sourceStart='2026-07-06';
 function latestCompletedWeek(end=P.asof){const monday=mondayFor(end);return addDays(monday,-7);}
 function fourWeeks(end=P.asof){const last=latestCompletedWeek(end);return {start:addDays(last,-21),end:addDays(last,6),starts:[-21,-14,-7,0].map(x=>addDays(last,x))};}
 function chartWeeks(){const last=latestCompletedWeek();return Array.from({length:12},(_,i)=>addDays(last,(i-11)*7)).filter(w=>w>=sourceStart&&(appliedRange.preset==='lifetime'||w>=monthFirst(appliedRange.start))&&w<=P.asof);}
 function rolling(days,end=P.asof){return {start:addDays(end,1-days),end};}
 function referenceAvailable(){return P.asof===overviewLatestAsOf&&(appliedRange.preset==='lifetime'||monthFirst(appliedRange.start)<='2026-09-07');}
 function emptyHTML(title,copy,reset=false){return `<div class="po-empty">${icon('calendar')}<strong>${esc(title)}</strong><span>${esc(copy)}</span>${reset?'<button data-po-reset-range>Reset date range</button>':''}</div>`;}
 function htmlTable(headers,rows,cls=''){return `<table class="po-data-table ${cls}"><thead><tr>${headers.map(h=>`<th scope="col">${h}</th>`).join('')}</tr></thead><tbody>${rows.map(row=>`<tr>${row.map(c=>`<td>${c}</td>`).join('')}</tr>`).join('')}</tbody></table>`;}
 // A single deterministic user-event dataset. These are not real customer names.
 const names=['Northstar','Willow','Harbor','Cedar','Maple','Stonebridge','Bluebird','Summit','Oakfield','Silverline','Greenfield','Horizon','Riverbend','Parkside','Evergreen','Westhaven','Aster','Lakeside','Pinecrest','Meadow','Elmwood','Seabrook','Amber','Redwood'];
 const suffixes=['Traders','Textiles','Supplies','Distributors','Industries','Foods','Engineering','Furnishings','Components','Packaging','Retail','Services'];
 const people=['arjun','meera','rohan','kavya','dev','aisha','neel','tara','vikram','priya','ananya','kabir','isha','sahil','nisha','amit'];
 const users=Array.from({length:480},(_,i)=>{
  const companyN=i%23===0?3:i%5===0?2:1;
  const email=`${people[i%people.length]}.${String(i+1).padStart(3,'0')}@ledgerdesk.example`;
  return {id:'po-u-'+i,index:i,email,companies:Array.from({length:companyN},(_,j)=>({id:`po-c-${i}-${j}`,name:names[(i+j*5)%names.length]+' '+suffixes[(i*3+j)%suffixes.length]+(i>=96?' '+String(Math.floor(i/96)+1):''),integration:(i+j)%11===0?'Zoho Books':'Tally',events:[],email})),events:[]};
 });
 const scheduled=users.map(()=>new Set());
 function schedule(i,day){if(i<users.length&&day<=SNAPSHOT_DATE)scheduled[i].add(day);}
 // Four exact, non-overlapping frequency buckets: 299 / 50 / 29 / 42.
 const last4starts=['2026-08-31','2026-09-07','2026-09-14','2026-09-21'];
 let index=0;
 [44,60,102,93].forEach((n,w)=>{for(let k=0;k<n;k++,index++)schedule(index,addDays(last4starts[w],w===0?5+index%2:1+index%5));});
 const pairs=[[0,1],[0,2],[0,3],[1,2],[1,3],[2,3]],pairCounts=[9,9,8,8,8,8];
 pairCounts.forEach((n,j)=>{for(let k=0;k<n;k++,index++)pairs[j].forEach(w=>schedule(index,addDays(last4starts[w],w===0?5+index%2:1+index%5)));});
 [8,7,7,7].forEach((n,omit)=>{for(let k=0;k<n;k++,index++)last4starts.forEach((w,j)=>{if(j!==omit)schedule(index,addDays(w,j===0?5+index%2:1+index%5));});});
 for(;index<420;index++)last4starts.forEach((w,j)=>schedule(index,addDays(w,j===0?5+index%2:1+index%5)));
 // Exactly 153 active in the last 7 days. Nine are new in this week.
 [...Array(144).keys(),...Array.from({length:9},(_,i)=>420+i)].forEach(i=>{
  schedule(i,addDays('2026-09-28',i%7));
  if(i%3===0)schedule(i,addDays('2026-09-28',(i+2)%7));
  if(i%7===0)schedule(i,'2026-10-04');
 });
 // Exactly 292 distinct users in the previous rolling 30-day window.
 for(let i=0;i<292;i++){
  schedule(i,addDays('2026-08-10',(i%3)*7+1+i%4));
  ['2026-08-10','2026-08-17','2026-08-24'].forEach((w,j)=>{if(hashText(i+'old'+j)%100<(j===1?54:22))schedule(i,addDays(w,1+i%5));});
  if(i%4===0)schedule(i,'2026-08-07');
 }
 // Older history provides new/returning classification without changing MAU.
 ['2026-07-06','2026-07-13','2026-07-20','2026-07-27','2026-08-03'].forEach((w,wi)=>{
  for(let i=0;i<users.length;i++){
   if((i<220||i>=429)&&hashText('history'+i+':'+wi)%100<43)schedule(i,addDays(w,wi===4?i%3:1+i%5));
  }
 });
 function addEvent(company,date,flow,type,count){if(count>0)company.events.push({date,flow,type,count,timestamp:date+'T11:30:00Z'});}
 users.forEach((u,i)=>{
  const days=[...scheduled[i]].sort();
  days.forEach((day,di)=>{
   const company=u.companies[di%u.companies.length],profile=(i*37)%100,seed=hashText(u.id+day),v=4+seed%78;
   const hasAP=profile>=33&&profile<98,hasAR=profile>=89&&profile<99,hasTxn=profile<33||profile>=66&&profile<89||profile>=94&&profile<98;
   if(hasAP){addEvent(company,day,'bills','bill_upload',Math.ceil(v*.53));addEvent(company,day,'bills','bill_create',Math.floor(v*.4));if(seed%3===0)addEvent(company,day,'bills','bill_edit',1+seed%9);}
   if(hasAR){addEvent(company,day,'invoices','invoice_upload',2+seed%13);addEvent(company,day,'invoices','invoice_create',1+seed%8);}
   if(hasTxn){if(seed%3===0)addEvent(company,day,'statements','statement_upload',1+seed%5);addEvent(company,day,'transactions','transaction_update',12+seed%161);}
   if((i+di)%7===0||di===1||profile===99)addEvent(company,day,'sync','accounting_sync',1+seed%6);
   // A user with an otherwise empty mix still contributes a real fixture event.
   if(!company.events.some(e=>e.date===day))addEvent(company,day,'bills','bill_upload',v);
  });
  // The demo may contain a company that has no activity in the selected window.
  u.companies.forEach(c=>{
   c.events.sort((a,b)=>a.date.localeCompare(b.date)||a.type.localeCompare(b.type));
   c.first=c.events[0]?.date||null;c.integrated=c.first?addDays(c.first,-3-i%13):null;
   c.activated=c.events.find(e=>e.flow==='sync')?.date||null;
  });
  u.events=u.companies.flatMap(c=>c.events).sort((a,b)=>a.date.localeCompare(b.date));u.first=u.events[0]?.date||null;
 });
 const activityCache=new Map();
 function periodUsers(start,end){
  const key=start+'|'+end;if(activityCache.has(key))return activityCache.get(key);
  const result=users.map(u=>{const ev=wEvents(u.events,start,end);if(!ev.length)return null;return {...u,selectedEvents:ev,actions:total(ev),days:countDays(ev),last:ev.at(-1).date,activeCompanies:u.companies.filter(c=>c.events.some(e=>inWindow(e,start,end)))};}).filter(Boolean);
  activityCache.set(key,result);return result;
 }
 const adoption=Array.from({length:360},(_,i)=>({integrated:addDays('2026-06-08',Math.floor(i*91/360)),core:i<232,converted:i<82,sustained:i>=40&&i<101}));
 const journey=Array.from({length:386},(_,i)=>({integrated:addDays('2026-06-08',Math.floor(i*91/386)),work:i<251,sync:i<203}));
 function cohortData(source){return source.filter(c=>addDays(c.integrated,28)<=P.asof&&(appliedRange.preset==='lifetime'||monthInRange(c.integrated.slice(0,7))));}
 const mix=[['Transactions only',32.6,37.4,-4.9,false],['AP only',32.6,28.9,3.7,false],['AP + Transactions',23.3,20.6,2.7,true],['AP + AR',5.5,5.3,.3,true],['AP + AR + Transactions',4.8,4.3,.6,true],['AR only',.7,2.3,-1.6,false],['AR + Transactions',.2,1,-.8,true],['Other core only',.2,.3,0,false]];
 const issues=[
  {issue:'Reverted to review',module:'Transactions',rate:33,affected:69,eligible:209,previous:35,change:-2,recovered:60,recovery:87,unresolved:9},
  {issue:'Bill upload failed',module:'Uploads',rate:15,affected:32,eligible:213,previous:9.1,change:5.9,recovered:29,recovery:90.6,unresolved:3},
  {issue:'Type update failed',module:'Transactions',rate:18.9,affected:31,eligible:164,previous:25.8,change:-6.9,recovered:30,recovery:96.8,unresolved:1},
  {issue:'Invoice upload failed',module:'Uploads',rate:8.9,affected:4,eligible:45,previous:10.4,change:-1.5,recovered:3,recovery:75,unresolved:1},
  {issue:'Ledger update failed',module:'Transactions',rate:21.3,affected:44,eligible:207,previous:31.5,change:-10.2,recovered:44,recovery:100,unresolved:0}
 ];
 // Illustrative company identities. Aggregate memberships match the supplied snapshot.
 // These fixtures are not a production query or evidence about real customers.
 const moduleDefs=[
  {key:'ap',label:'Bills / AP',steps:[
   {key:'ap_upload',label:'Bill uploaded'},
   {key:'ap_create',label:'Bill record created'},
   {key:'ap_review',label:'Review / correction'},
   {key:'ap_failed',label:'Upload failed',issue:true}
  ]},
  {key:'ar',label:'Invoices / AR',steps:[
   {key:'ar_upload',label:'Invoice uploaded'},
   {key:'ar_create',label:'Invoice record created'},
   {key:'ar_failed',label:'Upload failed',issue:true}
  ]},
  {key:'txn',label:'Transactions',steps:[
   {key:'txn_upload',label:'Statement uploaded'},
   {key:'txn_work',label:'Transaction work'},
   {key:'txn_ready',label:'Accounting ready',denominator:'txn_work',denominatorLabel:'worked'},
   {key:'txn_reverted',label:'Reverted after ready',issue:true}
  ]}
 ];
 const fixtureCompanies=new Map();
 function fixtureCompany(family,i,integrated){
  const uid=`${family}-u-${Math.floor(i/2)}`;
  const c={id:`${family}-c-${i}`,ownerId:uid,email:`${family}.${String(Math.floor(i/2)+1).padStart(3,'0')}@ledgerdesk.example`,name:names[i%names.length]+' '+suffixes[Math.floor(i/names.length)%suffixes.length]+(i>=288?' '+(2+Math.floor(i/288)):''),integration:i%11===0?'Zoho Books':'Tally',integrated,events:[],observedStart:integrated,observedEnd:addDays(integrated,27),flags:{},modules:[],steps:[]};
  fixtureCompanies.set(c.id,c);return c;
 }
 function finishFixture(c){
  c.events.sort((a,b)=>a.date.localeCompare(b.date)||a.timestamp.localeCompare(b.timestamp)||a.type.localeCompare(b.type));
  c.first=c.events[0]?.date||null;c.activated=c.events.find(e=>e.flow==='sync')?.date||null;
 }
 adoption.forEach((r,i)=>{
  const c=fixtureCompany('adoption',i,r.integrated);c.flags={core:r.core,converted:r.converted,sustained:r.sustained};
  const offsets=r.sustained?[2,10,18]:r.core?[1,3]:[10,12];
  offsets.forEach((d,j)=>{addEvent(c,addDays(r.integrated,d),'bills','bill_upload',2+(i+j)%14);if(j===0)addEvent(c,addDays(r.integrated,d),'bills','bill_create',1+i%7);});
  if(r.converted)addEvent(c,addDays(r.integrated,r.sustained?11:4),'sync','accounting_sync',1);
  r.company=c;finishFixture(c);
 });
 journey.forEach((r,i)=>{
  const c=fixtureCompany('journey',i,r.integrated);c.flags={integrated:true,work:r.work,sync:r.sync};
  const ap=i<165,ar=i>=50&&i<87,tx=i>=99&&i<251,j=i-99;
  r.modules=[...(ap?['ap']:[]),...(ar?['ar']:[]),...(tx?['txn']:[])];
  r.steps=[];const step=(key,condition)=>{if(condition)r.steps.push(key);};
  step('ap_upload',ap&&i<145);step('ap_create',ap&&i>=33);step('ap_review',ap&&i>=60&&i<132);step('ap_failed',ap&&i<12);
  step('ar_upload',ar&&i<84);step('ar_create',ar&&i>=82);step('ar_failed',ar&&i>=83);
  step('txn_upload',tx);step('txn_work',tx&&j<139);step('txn_ready',tx&&j<132);step('txn_reverted',tx&&j<51);
  c.modules=r.modules;c.steps=r.steps;
  const eventMap={ap_upload:['bills','bill_upload',2],ap_create:['bills','bill_create',4],ap_review:['bills','bill_edit',7],ar_upload:['invoices','invoice_upload',3],ar_create:['invoices','invoice_create',5],txn_upload:['statements','statement_upload',2],txn_work:['transactions','transaction_update',5]};
  r.steps.forEach(key=>{if(eventMap[key]){const [flow,type,offset]=eventMap[key];addEvent(c,addDays(r.integrated,offset),flow,type,1+i%12);}});
  if(r.sync)addEvent(c,addDays(r.integrated,18),'sync','accounting_sync',1+i%3);
  r.company=c;finishFixture(c);
 });
 const issueCases=issues.map((issue,index)=>Array.from({length:issue.affected},(_,i)=>{
  const c=fixtureCompany('issue'+(index+1),i,addDays('2026-07-06',i%31));
  c.caseStatus=i<issue.recovered?'recovered':'unresolved';c.affectedAt=addDays('2026-09-07',i%18);c.recoveredAt=c.caseStatus==='recovered'?addDays(c.affectedAt,2):null;
  c.caseId=`CASE-${index+1}-${String(i+1).padStart(3,'0')}`;
  const flow=index===1?'bills':index===3?'invoices':'transactions',type=flow==='bills'?'bill_upload':flow==='invoices'?'invoice_upload':'transaction_update';
  addEvent(c,addDays(c.affectedAt,-1),flow,type,2+i%17);
  if(c.recoveredAt)addEvent(c,c.recoveredAt,flow,type,1+i%4);
  addEvent(c,addDays(c.integrated,5),'sync','accounting_sync',1);
  finishFixture(c);return c;
 }));

 let current={};
 function compute(){
  P.asof=appliedRange.preset==='lifetime'?overviewLatestAsOf:monthLast(appliedRange.end)>overviewLatestAsOf?overviewLatestAsOf:monthLast(appliedRange.end);
  const w=rolling(7),m=rolling(30),pw={start:addDays(w.start,-7),end:addDays(w.end,-7)},pm={start:addDays(m.start,-30),end:addDays(m.end,-30)};
  const weekly=periodUsers(w.start,w.end),monthly=periodUsers(m.start,m.end),prevW=periodUsers(pw.start,pw.end),prevM=periodUsers(pm.start,pm.end),weeks=chartWeeks(),freq=fourWeeks();
  const freqUsers=periodUsers(freq.start,freq.end),buckets=[0,0,0,0];
  freqUsers.forEach(u=>{const n=freq.starts.filter(s=>u.events.some(e=>inWindow(e,s,addDays(s,6)))).length;if(n)buckets[n-1]++;});
  const chart=weeks.map(week=>{const people=periodUsers(week,addDays(week,6)),fresh=people.filter(u=>u.first>=week).length;return {week,users:people.length,new:fresh,returning:people.length-fresh,ap:people.filter(u=>u.selectedEvents.some(e=>e.flow==='bills')).length,ar:people.filter(u=>u.selectedEvents.some(e=>e.flow==='invoices')).length,txn:people.filter(u=>u.selectedEvents.some(e=>['statements','transactions'].includes(e.flow))).length};});
  current={w,m,pw,pm,weekly,monthly,prevW,prevM,chart,freq,freqUsers,buckets,adoption:cohortData(adoption),journey:cohortData(journey)};
 }
 const outcomes=[{key:'core',label:'7-day core adoption',copy:'Started core activity within 7 days',definition:'Share of eligible companies that performed qualifying core activity within seven days of successful integration.'},{key:'converted',label:'28-day value conversion',copy:'Reached accounting sync within 28 days',definition:'Share of eligible companies that reached a qualifying accounting sync within 28 days of successful integration.'},{key:'sustained',label:'28-day sustained adoption',copy:'Active in at least 2 of the first 4 weeks',definition:'Share of eligible companies that were core-active in at least two of the four weeks following successful integration.'}];
 let lastNativeKpiAsOf=null;
 function renderKPIs(){
  // The React-owned KPI strip never receives demo values from this runtime.
  const status=$('#prototype-surface')?.dataset.overviewStatus||'current';
  const includesGap=appliedRange.preset!=='lifetime'&&
    appliedRange.start<='2026-07'&&appliedRange.end>='2026-05';
  const unavailable=status==='unavailable';
  const caveat=unavailable?'No verified data for this selection'
    :appliedRange.preset!=='lifetime'&&appliedRange.end<'2026-05'
      ?'Prior-to-March activity history is incomplete'
      :includesGap?'May–July event tracking incomplete'
      :status==='available'?'Reconstructed from recorded events':'';
  $('#po-page-context').innerHTML=icon('clock')+
    '<span>Reporting as of <strong style="font-weight:500;color:#677b97">'+
      cohortLabel(P.asof)+'</strong></span><span>·</span>'+
    '<button data-po-info="dates">How date ranges work</button>'+
    (caveat?'<span class="po-quality-caption">· '+esc(caveat)+'</span>':'');
  if(lastNativeKpiAsOf!==P.asof){
   lastNativeKpiAsOf=P.asof;
   window.dispatchEvent(new CustomEvent('aia:overview-asof',{detail:{asOf:P.asof}}));
  }
 }
 function chartDimensions(svg){const w=svg.clientWidth||580;const h=svg.clientHeight||235;return {w,h,left:31,right:10,top:22,bottom:28,plotW:w-41,plotH:h-50};}
 function niceMax(n){return Math.max(50,Math.ceil(n/50)*50);}
 function chartGrid(d,max){let s='';const step=max<=100?25:max<=250?50:100;for(let value=0;value<=max;value+=step){const i=value/step,y=d.top+d.plotH*(1-value/max);s+=`<line x1="${d.left}" y1="${y}" x2="${d.w-d.right}" y2="${y}" stroke="${i===0?'#dfe5ef':'#ecf0f6'}" ${i?'stroke-dasharray="2 5"':''}/><text x="${d.left-9}" y="${y+3}" text-anchor="end" fill="#9aa7b9" font-size="9">${value}</text>`;}return s;}
 function chartEmpty(svg){const d=chartDimensions(svg);svg.setAttribute('viewBox',`0 0 ${d.w} ${d.h}`);svg.innerHTML=`<text x="${d.w/2}" y="${d.h/2}" text-anchor="middle" fill="#96a3b6" font-size="11">No completed weeks in the available fixture</text>`;}
 function renderWeeklyChart(){ /* React owns #po-weekly-chart-view. */ }
 function renderFeatureChart(){ /* Native React owns module usage over time. */ }
 function renderCharts(){renderWeeklyChart();renderFeatureChart();}
 function renderFrequency(){ /* React owns #po-frequency-content. */ }
 function renderAdoption(){ /* The native React adoption cards own the report. */ }
 function renderJourney(){ /* The native React full-width funnel owns the report. */ }

 function renderMix(){ /* Native React owns module combinations. */ }
 function renderFriction(){ /* Native React owns the verified issue chart and drills. */ }
 function renderOverview(){
  compute();renderKPIs();renderFrequency();renderAdoption();renderJourney();renderMix();renderFriction();
  const data=current.chart;
  requestAnimationFrame(renderCharts);
 }
 // One record modal, with an explicit context for the clicked metric, period or stage.
 function metricWindow(){return P.drill?.window||(P.mode==='wau'?current.w:current.m);}
 function metricName(){return P.drill?.title||(P.mode==='wau'?'Weekly core-active users':P.mode==='mau'?'Monthly core-active users':'Stickiness');}
 function isCohortDrill(){return !!P.drill&&['adoption','stage','module','step'].includes(P.drill.kind);}
 function companySelectedWindow(c=P.company){return isCohortDrill()&&c?{start:c.observedStart,end:c.observedEnd}:metricWindow();}
 function selectedWindowLabel(){return isCohortDrill()?'First 28 days':P.drill?.windowLabel||(P.mode==='wau'?'Last 7 days':'Last 30 days');}
 function eventsForRecordCompany(c){const win=isCohortDrill()?{start:c.observedStart,end:c.observedEnd}:metricWindow();return wEvents(c.events,win.start,win.end);}
 function moduleMatch(c,win,module){const flows=module==='ap'?['bills']:module==='ar'?['invoices']:module==='txn'?['statements','transactions']:['bills','invoices','statements','transactions'];return c.events.some(e=>inWindow(e,win.start,win.end)&&flows.includes(e.flow));}
 function rowFromCompanies(u,companies){
  const ev=companies.flatMap(eventsForRecordCompany).sort((a,b)=>a.date.localeCompare(b.date));
  const statuses=unique(companies.map(companyStatus).filter(Boolean));
  return {...u,activeCompanies:companies,count:companies.length,selectedEvents:ev,actions:total(ev),days:countDays(ev),last:ev.at(-1)?.date||'',integrated:companies.map(c=>c.integrated).filter(Boolean).sort()[0]||'',status:statuses.length===1?statuses[0]:statuses.length?'Mixed':'',affected:companies.map(c=>c.affectedAt).filter(Boolean).sort()[0]||'',resolved:companies.some(c=>c.caseStatus==='unresolved')?'':companies.map(c=>c.recoveredAt).filter(Boolean).sort().at(-1)||''};
 }
 function groupRecordCompanies(companies){
  const groups=new Map();companies.forEach(c=>{const id=c.ownerId||c.email;if(!groups.has(id))groups.set(id,{id,email:c.email,companies:[]});groups.get(id).companies.push(c);});
  return [...groups.values()].map(u=>rowFromCompanies(u,u.companies));
 }
 function companyStatus(c){
  const d=P.drill;if(!d)return '';
  if(d.kind==='issue')return c.caseStatus==='recovered'?'Recovered':'Unresolved';
  if(isCohortDrill()){
   const matched=d.match(c);
   return matched?d.positive:d.negative;
  }
  return '';
 }
 function rawRecordRows(tab=P.tab){
  const d=P.drill;
  if(!d){
   const weeklyMap=new Map(current.weekly.map(u=>[u.id,u])),monthlyMap=new Map(current.monthly.map(u=>[u.id,u]));
   let rows=(P.mode==='wau'?current.weekly:current.monthly).map(u=>({...u,actions7:weeklyMap.get(u.id)?.actions||0,actions30:monthlyMap.get(u.id)?.actions||0,weeklyActive:weeklyMap.has(u.id),count:u.activeCompanies.length}));
   if(P.mode==='stickiness'){if(tab==='active')rows=rows.filter(u=>u.weeklyActive);if(tab==='monthly')rows=rows.filter(u=>!u.weeklyActive);}return rows;
  }
  if(isCohortDrill()){
   let cs=d.companies;
   if(tab==='matched')cs=cs.filter(d.match);else if(tab==='other')cs=cs.filter(c=>!d.match(c));
   return groupRecordCompanies(cs);
  }
  if(d.kind==='issue')return groupRecordCompanies(d.companies.filter(c=>tab==='all'||c.caseStatus===tab));
  if(d.kind==='mix')return groupRecordCompanies(d.companies);
  let rows=periodUsers(d.window.start,d.window.end).map(u=>({...u,count:u.activeCompanies.length}));
  if(d.kind==='weekly'){
   rows=rows.map(u=>({...u,status:u.first>=d.window.start?'Newly active':'Returning'}));
   if(tab!=='all')rows=rows.filter(u=>(u.first>=d.window.start)===(tab==='new'));
  }
  if(d.kind==='frequency'){
   rows=rows.map(u=>({...u,freqWeeks:current.freq.starts.filter(s=>u.events.some(e=>inWindow(e,s,addDays(s,6)))).length}));
   rows=rows.filter(u=>u.freqWeeks===Number(tab));
  }
  if(d.kind==='feature'){
   rows=rows.map(u=>rowFromCompanies(u,u.activeCompanies.filter(c=>moduleMatch(c,d.window,tab)))).filter(u=>u.count);
  }
  return rows;
 }
 function recordCandidates(){
  let rows=rawRecordRows();
  const q=P.query.trim().toLowerCase();
  if(q)rows=rows.filter(u=>u.email.toLowerCase().includes(q)||u.activeCompanies.some(c=>c.name.toLowerCase().includes(q)));
  if(P.companyFilter==='one')rows=rows.filter(u=>u.count===1);
  if(P.companyFilter==='many')rows=rows.filter(u=>u.count>1);
  if(P.integrationFilter!=='all')rows=rows.filter(u=>u.activeCompanies.some(c=>c.integration===P.integrationFilter));
  rows.sort((a,b)=>{const va=a[P.sort]??'',vb=b[P.sort]??'';let n=typeof va==='number'?va-vb:typeof va==='boolean'?Number(va)-Number(vb):String(va).localeCompare(String(vb));if(n===0)return a.email.localeCompare(b.email);return P.dir==='asc'?n:-n;});return rows;
 }
 function recordTabs(){
  const d=P.drill;
  if(!d){return P.mode==='stickiness'?[{key:'all',label:'All MAU',count:current.monthly.length},{key:'active',label:'Active in last 7d',count:current.weekly.length},{key:'monthly',label:'MAU only',count:current.monthly.length-current.weekly.length}]:[];}
  if(isCohortDrill()){
   const n=d.companies.length,matched=d.companies.filter(d.match).length;
   return [{key:'matched',label:d.positive,count:matched},{key:'other',label:d.negative,count:n-matched},{key:'all',label:'All eligible',count:n}];
  }
  if(d.kind==='issue')return [{key:'unresolved',label:'Unresolved',count:d.companies.filter(c=>c.caseStatus==='unresolved').length},{key:'recovered',label:'Recovered',count:d.companies.filter(c=>c.caseStatus==='recovered').length},{key:'all',label:'All affected',count:d.companies.length}];
  if(d.kind==='weekly')return [{key:'all',label:'All users',count:rawRecordRows('all').length},{key:'returning',label:'Returning',count:rawRecordRows('returning').length},{key:'new',label:'Newly active',count:rawRecordRows('new').length}];
  if(d.kind==='frequency')return current.buckets.map((count,i)=>({key:String(i+1),label:`${i+1} ${i?'weeks':'week'}`,count}));
  if(d.kind==='feature')return [['all','All modules'],['ap','AP / Bills'],['ar','AR / Invoices'],['txn','Transactions']].map(([key,label])=>({key,label,count:rawRecordRows(key).length}));
  return [];
 }
 function renderRecordTabs(){
  const opts=recordTabs();$('#po-record-tabs').hidden=!opts.length;
  $('#po-record-tabs').innerHTML=opts.map(({key,label,count})=>`<button class="po-record-tab" data-po-record-tab="${key}" id="po-record-tab-${key}" role="tab" aria-selected="${P.tab===key}" tabindex="${P.tab===key?'0':'-1'}" aria-controls="po-record-scroll">${esc(label)}<span>${nf(count)}</span></button>`).join('');
 }
 function renderRecordMeta(){
  const d=P.drill,rows=rawRecordRows(),n=rows.length,companies=rows.reduce((s,u)=>s+u.count,0);
  $('#po-record-eyebrow').textContent=metricName();
  let title='',subtitle='',context='';
  if(!d){
   const win=metricWindow(),s=P.mode==='stickiness';
   title=s?`${nf(current.weekly.length)} of ${nf(current.monthly.length)} monthly-active users`:`${nf(n)} core-active users`;
   subtitle=s?`Also active in the last 7 days · ${dateSpan(current.w.start,current.w.end)}`:`${selectedWindowLabel()} · ${dateSpan(win.start,win.end)}`;
   context=s?'MAU only means active in the last 30 days, but not the last 7. Expanded company activity uses the 30-day window.':'';
  }else if(isCohortDrill()){
   title=P.tab==='all'?`${nf(companies)} eligible companies`:`${nf(companies)} of ${nf(d.companies.length)} companies`;
   const segment=P.tab==='all'?'All eligible':P.tab==='matched'?d.positive:d.negative;
   const dates=d.companies.map(c=>c.integrated).sort();
   subtitle=`${segment} · Integrated ${dateSpan(dates[0],dates.at(-1))}`;
   context=d.note+' Each company has its own complete 28-day observation window.';
  }else if(d.kind==='weekly'){
   title=`${nf(n)} ${P.tab==='new'?'newly active':P.tab==='returning'?'returning':'core-active'} users`;
   subtitle=`${dateSpan(d.window.start,d.window.end)} · Completed calendar week`;
   context='Newly active means the first core event is in this week. Returning users have an earlier core event. The two groups do not overlap.';
  }else if(d.kind==='frequency'){
   title=`${nf(n)} core-active users`;
   subtitle=`Active in exactly ${P.tab} of 4 completed weeks · ${dateSpan(d.window.start,d.window.end)}`;
   context='Frequency is measured per user across companies. A company in the expansion can be active in fewer weeks than its user. One active week is not churn.';
  }else if(d.kind==='feature'){
   title=`${nf(n)} core-active users`;
   const module=recordTabs().find(t=>t.key===P.tab)?.label||'All modules';
   subtitle=`${module} · ${dateSpan(d.window.start,d.window.end)}`;
   context='Users are counted once per module and can appear in several module tabs. Activity columns include all workflows in the matching companies for this week.';
  }else if(d.kind==='mix'){
   title=`${nf(companies)} illustrative company matches`;
   subtitle=`${d.title} · ${dateSpan(d.window.start,d.window.end)}`;
   context=`Reference share: ${mix[d.index][1].toFixed(1)}%. The source denominator was not supplied. These sample matches demonstrate the drill, not the company count behind that percentage.`;
  }else if(d.kind==='issue'){
   const issue=issues[d.index];title=`${nf(companies)} ${P.tab==='all'?'affected':P.tab} cases`;
   subtitle=`${issue.module} · Snapshot incidence ${issue.rate.toFixed(1)}% (${nf(issue.affected)} / ${nf(issue.eligible)})`;
   context='Case totals match the source snapshot. User/company mappings are illustrative, with one sample company per case. Production eligibility and issue windows still need validation.';
  }
  $('#po-record-title').textContent=title;$('#po-record-subtitle').textContent=subtitle;
  $('#po-record-context').hidden=!context;
  $('#po-record-context').innerHTML=icon('info')+`<span>${esc(context)}</span>`;
 }
 function recordHeader(key,label,numeric=false){return `<th scope="col" ${numeric?'class="numeric"':''} ${P.sort===key?`aria-sort="${P.dir==='asc'?'ascending':'descending'}"`:''}><button data-po-sort="${key}">${label}${icon(P.sort===key?(P.dir==='asc'?'up':'down'):'sort')}</button></th>`;}
 function recordColumns(){
  const d=P.drill;
  if(!d&&P.mode==='stickiness')return [['email','User'],['count','Companies',true],['weeklyActive','7-day status'],['actions7','Core actions · 7d',true],['actions30','Core actions · 30d',true],['days','Active days · 30d',true],['last','Last core activity']];
  if(isCohortDrill())return [['email','User'],['count','Companies',true],['status','Cohort status'],['integrated','Integrated'],['actions','Core actions · 28d',true],['last','Last activity · 28d']];
  if(d?.kind==='issue')return [['email','User'],['count','Cases / companies',true],['status','Recovery status'],['affected','First affected'],['resolved','Recovered on'],['actions','Core actions · 28d',true]];
  if(d?.kind==='frequency')return [['email','User'],['count','Companies',true],['freqWeeks','Active weeks',true],['actions','Core actions · 4w',true],['days','Active days',true],['last','Last core activity']];
  const span=d?d.kind==='mix'?'28d':'week':P.mode==='wau'?'7d':'30d';
  return [['email','User'],['count','Companies',true],...(d?.kind==='weekly'?[['status','User segment']]:[]),['last','Last core activity'],['actions',`Core actions · ${span}`,true],['days','Active days',true]];
 }
 function statusHTML(value){const positive=['Achieved','Reached','Uses module','Completed','Recovered','Returning','Newly active','Active in window','Active in last 7d'].includes(value),warning=['Unresolved','Affected'].includes(value);return `<span class="po-status ${positive?'active':warning?'warning':'neutral'}">${esc(value||'Not recorded')}</span>`;}
 function companyExpansion(u){
  const contextual=isCohortDrill()||P.drill?.kind==='issue',issue=P.drill?.kind==='issue';
  const cols=contextual?issue?['Company','Integration','Case','Status','Affected','Recovered','Core actions']:['Company','Integration','Cohort status','Integrated','Observed through','Core actions','Last activity']:['Company','Integration','Bills','Invoices','Statements','Transactions','Sync','Last activity'];
  const caption=contextual?(issue?'Case-to-company mapping is illustrative':`${selectedWindowLabel()} after each company's integration`):`${selectedWindowLabel()} · ${dateSpan(metricWindow().start,metricWindow().end)}`;
  return `<tr class="po-company-detail"><td colspan="${recordColumns().length+1}"><p class="po-company-caption">${nf(u.count)} ${u.count===1?'company':'companies'} · ${esc(caption)}</p><table class="po-company-subtable"><thead><tr>${cols.map(c=>`<th scope="col">${c}</th>`).join('')}</tr></thead><tbody>${u.activeCompanies.map(c=>{
   const ev=eventsForRecordCompany(c),sums=groupSums(ev);
   let cells;
   if(issue)cells=[esc(c.caseId),statusHTML(companyStatus(c)),dateLabel(c.affectedAt),c.recoveredAt?dateLabel(c.recoveredAt):'Unresolved',nf(total(ev))];
   else if(contextual)cells=[statusHTML(companyStatus(c)),dateLabel(c.integrated),dateLabel(c.observedEnd),nf(total(ev)),ev.length?dateLabel(ev.at(-1).date):'No activity'];
   else cells=[...keys.map(k=>nf(sums[k])),ev.length?dateLabel(ev.at(-1).date):'No activity'];
   return `<tr><td><button class="company-name-button" data-po-company="${c.id}" data-po-owner="${u.id}" aria-haspopup="dialog" aria-controls="po-company-dialog">${esc(c.name)}</button></td><td><span class="integration-tag">${esc(c.integration)}</span></td>${cells.map(cell=>`<td>${cell}</td>`).join('')}</tr>`;
  }).join('')}</tbody></table></td></tr>`;
 }
 function renderRecords(){
  renderRecordTabs();renderRecordMeta();
  const rows=recordCandidates(),pages=Math.max(1,Math.ceil(rows.length/P.pageSize));P.pageNo=Math.max(1,Math.min(P.pageNo,pages));
  const start=(P.pageNo-1)*P.pageSize,visible=rows.slice(start,start+P.pageSize),cols=recordColumns();
  $('#po-clear-search').hidden=!P.query;$('#po-filter-count').textContent=Number(P.companyFilter!=='all')+Number(P.integrationFilter!=='all');
  $('#po-user-table').innerHTML=`<thead><tr><th scope="col"><span class="sr-only">Expand companies</span></th>${cols.map(c=>recordHeader(...c)).join('')}</tr></thead><tbody>${visible.length?visible.map(u=>{const expanded=P.expanded.has(u.id);return `<tr class="po-user-row ${expanded?'po-expanded':''}"><td><button class="po-expander" data-po-user="${u.id}" aria-label="${expanded?'Collapse':'Expand'} companies for ${esc(u.email)}" aria-expanded="${expanded}">${icon(expanded?'minus':'plus')}</button></td>${cols.map(([key,label,num])=>{
   let cell;if(key==='email')cell=esc(u.email);else if(key==='count')cell=`<span class="po-company-count">${u.count}</span>`;else if(key==='weeklyActive')cell=statusHTML(u.weeklyActive?'Active in last 7d':'MAU only');else if(key==='status')cell=statusHTML(u.status);else if(['last','integrated','affected','resolved'].includes(key))cell=u[key]?dateLabel(u[key]):key==='resolved'?'Not recovered':'No activity';else cell=nf(u[key]||0);
   return `<td ${num?'class="numeric"':''}>${cell}</td>`;
  }).join('')}</tr>${expanded?companyExpansion(u):''}`;}).join(''):`<tr><td colspan="${cols.length+1}" style="height:270px;text-align:center"><div class="po-empty"><strong>${P.query||P.companyFilter!=='all'||P.integrationFilter!=='all'?'No users match these filters':'No records in this segment'}</strong><span>${P.query?'Try a different user or company name.':'Select another segment to continue.'}</span>${P.query||P.companyFilter!=='all'||P.integrationFilter!=='all'?'<button data-po-clear-records>Clear search and filters</button>':''}</div></td></tr>`}</tbody>`;
  const companyCount=rows.reduce((n,u)=>n+u.count,0),unit=P.drill?.kind==='issue'?'sample cases / companies':P.drill?.kind==='mix'?'sample companies':'companies';
  $('#po-record-count').textContent=rows.length?`${start+1}–${Math.min(start+P.pageSize,rows.length)} of ${nf(rows.length)} users · ${nf(companyCount)} ${unit}`:'0 matching users';
  const pageItems=[];for(let i=1;i<=pages;i++)if(i===1||i===pages||Math.abs(i-P.pageNo)<=1)pageItems.push(i);
  $('#po-pagination').innerHTML=`<button data-po-page="${P.pageNo-1}" ${P.pageNo<=1?'disabled':''} aria-label="Previous page">${icon('left')}</button>`+pageItems.map((n,i)=>`${i&&n-pageItems[i-1]>1?'<span aria-hidden="true" style="padding:0 3px">…</span>':''}<button data-po-page="${n}" ${n===P.pageNo?'aria-current="page"':''} aria-label="Page ${n}">${n}</button>`).join('')+`<button data-po-page="${P.pageNo+1}" ${P.pageNo>=pages?'disabled':''} aria-label="Next page">${icon('right')}</button>`;
 }
 function beginRecordModal(trigger){
  P.recordTrigger=trigger||document.activeElement;P.query='';P.companyFilter='all';P.integrationFilter='all';P.sort='last';P.dir='desc';P.pageNo=1;P.expanded=new Set();
  $('#po-user-search').value='';$('#po-company-filter').value='all';$('#po-integration-filter').value='all';togglePOFilters(false);syncAllSelects();
  const first=recordCandidates()[0];if(first)P.expanded.add(first.id);
  hidePOTooltip();renderRecords();openDialog('po-record-dialog');$('#po-record-scroll').scrollTop=0;$('#po-record-scroll').scrollLeft=0;$('#po-record-dialog .close-button').focus({preventScroll:true});
 }
 function openRecords(mode){P.drill=null;P.mode=mode;P.tab='active';beginRecordModal();}
 function setRecordTab(key){
  if(!recordTabs().some(t=>t.key===key))return;P.tab=key;P.pageNo=1;renderRecords();$('#po-record-scroll').scrollTop=0;$('#po-record-tab-'+key)?.focus({preventScroll:true});
 }
 function togglePOFilters(open){$('#po-filter-panel').hidden=!open;$('#po-filter-button').setAttribute('aria-expanded',String(open));if(!open&&activeSelect?.trigger.closest('#po-filter-panel'))closeSelectMenu();}
 function clearRecordFilters(clearQuery=false){P.companyFilter='all';P.integrationFilter='all';P.pageNo=1;$('#po-company-filter').value='all';$('#po-integration-filter').value='all';if(clearQuery){P.query='';$('#po-user-search').value='';}syncAllSelects();renderRecords();}
 function openOutcome(key){openReportDrill('adoption:'+key+':matched',document.activeElement);}
 function openReportDrill(command,trigger){
  const [kind,key,requested='all',base='']=command.split(':');let d={kind,key,windowLabel:'Selected period'},tab=requested;
  if(kind==='weekly'||kind==='feature'){
   const v=current.chart[Number(key)];if(!v)return;
   Object.assign(d,{index:Number(key),title:kind==='weekly'?'Weekly core-active users':'Module usage',window:{start:v.week,end:addDays(v.week,6)},windowLabel:'Selected week'});
  }else if(kind==='frequency'){
   Object.assign(d,{title:'Core usage frequency',window:current.freq,windowLabel:'Last 4 completed weeks'});tab=key;
  }else if(kind==='adoption'){
   const o=outcomes.find(o=>o.key===key);if(!o)return;
   Object.assign(d,{title:o.label,companies:current.adoption.map(r=>r.company),match:c=>c.flags[key],positive:'Achieved',negative:'Not achieved',note:o.definition+' Not achieved does not mean churn.'});tab=requested==='all'?'all':'matched';
  }else if(kind==='stage'||kind==='next'){
   const labels={integrated:'Successful integration',work:'Started accounting work',sync:'Accounting sync'};
   let actualKey=key,pool=current.journey;
   if(kind==='next'){actualKey=key==='integrated'?'work':'sync';pool=pool.filter(r=>r.company.flags[key]);}
   if(requested==='workonly'){pool=pool.filter(r=>r.work);tab='other';}
   else tab=requested==='reached'?'matched':requested;
   Object.assign(d,{kind:'stage',key:actualKey,title:labels[actualKey],companies:pool.map(r=>r.company),match:c=>c.flags[actualKey],positive:'Reached',negative:'Not reached',note:(kind==='next'||requested==='workonly')?'This breakdown starts with companies that reached the previous stage. Not reached means no qualifying next step within the observation window.':'Companies are counted once per stage. Not reached is a stage outcome, not a retention or churn label.'});
  }else if(kind==='module'||kind==='step'){
   const module=kind==='module'?moduleDefs.find(m=>m.key===key):moduleDefs.find(m=>m.steps.some(s=>s.key===key));if(!module)return;
   const step=kind==='step'?module.steps.find(s=>s.key===key):null;
   let pool=kind==='module'?current.journey.filter(r=>r.work):current.journey.filter(r=>r.modules.includes(module.key));
   if(step?.denominator)pool=pool.filter(r=>r.steps.includes(step.denominator));
   Object.assign(d,{title:kind==='module'?module.label:module.label+' · '+step.label,companies:pool.map(r=>r.company),match:c=>(kind==='module'?c.modules:c.steps).includes(key),positive:kind==='module'?'Uses module':step.issue?'Affected':'Completed',negative:kind==='module'?'No module use':step.issue?'Not affected':'Not completed',note:kind==='module'?'Share is out of companies that started accounting work. Module memberships overlap and must not be added together.':step.issue?'An issue is an affected-company flag, not an additional funnel stage. Companies may have both an issue and successful activity.':`Share is out of ${step.denominator?'companies with '+step.denominatorLabel+' transactions':'companies in this module'}. Activity rows are not assumed to be sequential conversions.`});
   tab=requested==='all'?'all':'matched';
  }else if(kind==='mix'){
   if(!referenceAvailable())return;const index=Number(key),m=mix[index];if(!m)return;const win=rolling(28);
   const wanted=[['txn'],['ap'],['ap','txn'],['ap','ar'],['ap','ar','txn'],['ar'],['ar','txn'],[]][index].slice().sort().join(',');
   const companies=users.flatMap(u=>u.companies.filter(c=>{const ev=wEvents(c.events,win.start,win.end);if(!ev.length)return false;const mods=['ap','ar','txn'].filter(k=>moduleMatch(c,win,k)).sort().join(',');return mods===wanted;}).map(c=>({...c,ownerId:u.id})));
   Object.assign(d,{index,title:m[0],companies,window:win,windowLabel:'Last 28 days'});tab='all';
  }else if(kind==='issue'){
   if(!referenceAvailable())return;const index=Number(key),issue=issues[index];if(!issue)return;
   Object.assign(d,{index,title:issue.issue,companies:issueCases[index],window:rolling(28),windowLabel:'Last 28 days'});
   tab=['all','recovered','unresolved'].includes(requested)?requested:'all';
  }else return;
  if(['adoption','stage','module','step'].includes(d.kind)){
   const dates=d.companies.map(c=>c.integrated).sort();d.window={start:dates[0]||P.asof,end:dates.length?addDays(dates.at(-1),27):P.asof};d.windowLabel='First 28 days';
  }
  P.drill=d;P.mode='report';P.tab=tab;beginRecordModal(trigger);
 }

 // Company details use the same event records as the selected user's table.
 function selectedCompanyEvents(){return P.company?.events.filter(e=>e.date<=P.asof)||[];}
 function companyWindow(){
  const scope=$('#po-company-scope').value;
  if(scope==='lastmonth'){const end=previousMonthEnd(P.asof);return {start:monthFirst(end.slice(0,7)),end,label:'Last complete month'};}
  if(scope==='last4'){return {...fourWeeks(),label:'Last 4 completed weeks'};}
  return {...companySelectedWindow(),label:selectedWindowLabel()};
 }
 function showCompanyTab(tab,focus=false){
  if(!['overview','activity','journey'].includes(tab))return;P.companyTab=tab;closeSelectMenu();
  $$('#po-company-dialog [data-po-ctab]').forEach(b=>{const selected=b.dataset.poCtab===tab;b.setAttribute('aria-selected',String(selected));b.tabIndex=selected?0:-1;});
  ['overview','activity','journey'].forEach(t=>$('#po-c-'+t).hidden=t!==tab);
  if(focus)$('#po-c-'+tab+'-tab').focus({preventScroll:true});
 }
 function renderCompanyCadence(){
  const mode=$('#po-company-cadence').value,ev=selectedCompanyEvents();
  let periods;if(mode==='weekly'){periods=fourWeeks().starts.map(s=>({start:s,end:addDays(s,6),label:dateLabel(s)}));}
  else{const last=previousMonthEnd(P.asof).slice(0,7);periods=[-3,-2,-1,0].map(n=>{const key=shiftMonth(last,n);return {start:monthFirst(key),end:monthLast(key),label:shortMonth(key)};});}
  $('#po-company-cadence-caption').textContent='Last 4 completed '+(mode==='weekly'?'weeks':'months');
  const selected=periods.map(p=>wEvents(ev,p.start,p.end));
  $('#po-company-cadence-table').innerHTML=htmlTable(['Metric',...periods.map(p=>esc(p.label))],[['Core actions',...selected.map(e=>`<strong>${nf(total(e))}</strong>`)],['Active days',...selected.map(e=>nf(countDays(e)))],['Active users',...selected.map(e=>e.length?'1':'0')],['Accounting syncs',...selected.map(e=>nf(total(e.filter(x=>x.flow==='sync'))))]]).replace(/^<table[^>]*>|<\/table>$/g,'');
 }
 function renderCompanyOverview(){
  const c=P.company,ev=selectedCompanyEvents(),win=companySelectedWindow(),selected=wEvents(ev,win.start,win.end),syncs=ev.filter(e=>e.flow==='sync'),last=ev.at(-1)?.date,activation=syncs[0]?.date;
  $('#po-company-health-caption').textContent='As of '+cohortLabel(P.asof);
  const health=[['Core actions',nf(total(selected)),selectedWindowLabel()],['Active days',nf(countDays(selected)),`Of ${daysBetween(win.start,win.end)+1} calendar days`],['Accounting syncs',nf(total(selected.filter(e=>e.flow==='sync'))),'In the selected window'],['Lifetime core actions',nf(total(ev)),'All available fixture activity']];
  $('#po-company-health').innerHTML=health.map(([label,value,caption])=>`<div><label>${label}</label><strong>${value}</strong><small>${caption}</small></div>`).join('');
  const lastSync=syncs.at(-1)?.date;
  const activeWeeks=unique(ev.map(e=>mondayFor(e.date))).length,active4=fourWeeks().starts.filter(s=>ev.some(e=>inWindow(e,s,addDays(s,6)))).length;
  const healthInfo=[['Successful integration',c.integrated?cohortLabel(c.integrated):'Not recorded'],['First accounting sync',activation?cohortLabel(activation):'Not yet recorded'],['Last core activity',last?`${dateLabel(last)} · ${daysBetween(last,P.asof)} days ago`:'No recorded activity'],['Last accounting sync',lastSync?`${dateLabel(lastSync)} · ${daysBetween(lastSync,P.asof)} days ago`:'No recorded sync'],['Recent cadence',`${active4} of the last 4 completed weeks`],['Active weeks',`${activeWeeks} in available history`]];
  $('#po-company-health-info').innerHTML=healthInfo.map(([label,value])=>`<div><span>${label}</span><strong>${value}</strong></div>`).join('');
  const since=lastSync?total(ev.filter(e=>e.date>lastSync&&e.flow!=='sync')):total(ev.filter(e=>e.flow!=='sync'));
  $('#po-company-insight').innerHTML=icon('info')+`<span>${since?`<strong style="font-weight:500;color:#566f95">${nf(since)} core actions</strong> ${lastSync?'after the most recent recorded sync date':'with no recorded accounting sync'}. Work activity and accounting sync are shown separately.`:'Core work and accounting sync are tracked separately. No work is recorded after the latest sync date in this fixture.'}</span>`;
  renderCompanyCadence();
 }
 function renderCompanyActivity(){
  const ev=selectedCompanyEvents(),win=companyWindow(),selected=wEvents(ev,win.start,win.end);
  $('#po-company-activity-caption').textContent=`${win.label}: ${dateSpan(win.start,win.end)} · compared with all activity through ${cohortLabel(P.asof)}`;
  $('#po-company-activity-table').innerHTML=`<thead><tr><th scope="col">Workflow / event</th><th scope="col">${esc(win.label)}</th><th scope="col">Lifetime</th></tr></thead><tbody>${flowDefs.map(f=>{const isOpen=P.flowExpanded.has(f.key),children=f.key!=='sync',sum=(events,key)=>total(events.filter(e=>e.flow===key));return `<tr><td>${children?`<button class="po-flow-toggle" data-po-flow="${f.key}" aria-expanded="${isOpen}">${icon(isOpen?'down':'right')}${f.label}</button>`:f.label}</td><td><strong>${nf(sum(selected,f.key))}</strong></td><td><strong>${nf(sum(ev,f.key))}</strong></td></tr>${children&&isOpen?f.children.map(([key,label])=>`<tr class="po-child"><td>${label}</td><td>${nf(total(selected.filter(e=>e.type===key)))}</td><td>${nf(total(ev.filter(e=>e.type===key)))}</td></tr>`).join(''):''}`;}).join('')}<tr class="po-total"><td>Total core actions</td><td>${nf(total(selected))}</td><td>${nf(total(ev))}</td></tr></tbody>`;
  const expanded=flowDefs.filter(f=>f.key!=='sync').every(f=>P.flowExpanded.has(f.key));$('#po-expand-all-flows').textContent=expanded?'Collapse all':'Expand all';
 }
 function renderCompanyJourney(){
  const ev=selectedCompanyEvents(),c=P.company,idx=ev.findIndex(e=>e.flow==='sync'),before=idx<0?ev:ev.slice(0,idx),at=idx<0?[]:[ev[idx]],after=idx<0?[]:ev.slice(idx+1);
  const span=events=>events.length?dateSpan(events[0].date,events.at(-1).date):'-';
  const rows=[['Integration setup',c.integrated?cohortLabel(c.integrated):'-','0','Setup only; excluded from core actions'],['Before activation',span(before),nf(total(before)),'Core work before the first qualifying sync'],['First accounting sync',span(at),nf(total(at)),at.length?'Activation milestone; first recorded sync batch':'No qualifying sync recorded'],['After activation',span(after),nf(total(after)),'Continued work and subsequent syncs']];
  $('#po-company-journey-table').innerHTML=`<thead><tr><th scope="col">Stage</th><th scope="col">Date / period</th><th scope="col">Core actions</th><th scope="col">Context</th></tr></thead><tbody>${rows.map(row=>`<tr>${row.map((v,i)=>`<td style="${i===3?'white-space:normal;max-width:260px;font-size:10px;color:#8b9bb0;text-align:left':''}">${i===0?'<strong style="font-weight:500">'+v+'</strong>':v}</td>`).join('')}</tr>`).join('')}<tr class="po-total"><td>Total</td><td>Through ${dateLabel(P.asof)}</td><td>${nf(total(ev))}</td><td style="text-align:left;font-size:10px">Mutually exclusive stages</td></tr></tbody>`;
 }
 function openCompany(button){
  const row=rawRecordRows().find(u=>u.id===button.dataset.poOwner);
  const u=row||users.find(u=>u.id===button.dataset.poOwner),c=row?.activeCompanies.find(c=>c.id===button.dataset.poCompany)||fixtureCompanies.get(button.dataset.poCompany)||u?.companies.find(c=>c.id===button.dataset.poCompany);
  if(!u||!c)return;
  P.company=c;P.companyUser=u;P.companyTrigger=button;P.flowExpanded=new Set(['bills']);
  $('#po-company-title').textContent=c.name;
  $('#po-company-meta').innerHTML=`<span class="integration-tag">${esc(c.integration)}</span><span class="meta-separator">·</span><span class="company-owner">${esc(u.email)}</span>`;
  $('#po-company-back-label').textContent=metricName();
  const win=companySelectedWindow(c),active=c.events.some(e=>inWindow(e,win.start,win.end)),contextStatus=companyStatus(c);
  $('#po-company-window').innerHTML=`${statusHTML(contextStatus||(active?'Active in window':'No activity'))}<strong>${esc(selectedWindowLabel())}</strong><span>${dateSpan(win.start,win.end)}</span>`;
  $('#po-company-scope').value='selected';$('#po-company-cadence').value='weekly';syncAllSelects();
  renderCompanyOverview();renderCompanyActivity();renderCompanyJourney();showCompanyTab('overview');
  $$('#po-company-dialog .po-c-panel').forEach(panel=>panel.scrollTop=0);hidePOTooltip();openDialog('po-company-dialog');$('#po-company-back').focus({preventScroll:true});
 }

 // Supporting definitions surface unresolved source questions instead of
 // silently inventing production definitions during a UI refactor.
 const definitions={
  dates:{title:'Report windows',body:()=>`<section>
<h3>Published reporting date</h3>
<p>The selected date range is <strong>${esc(rangeLabel(appliedRange))}</strong>.
Live Overview metrics use the published Supabase snapshot and its ingestion watermark.
If a historical reporting date has no published generation, the widgets show an
unavailable state rather than prototype numbers.</p>
<h3>Rolling usage</h3>
<p>WAU is distinct users doing independent core accounting work in the last
7 rolling days. MAU uses 30 rolling days, and Stickiness is WAU divided by MAU.
Period comparisons use the immediately preceding non-overlapping 7 or 30 days.</p>
<h3>Completed weeks</h3>
<p>Weekly core-active users and module usage each show 12 completed Monday–Sunday
weeks in Asia/Kolkata. Core usage frequency counts which of the last four completed
weeks each person worked in. The incomplete current week is excluded.
First observed means first recorded qualifying work, not signup. Tracking was
incomplete during May–July 2026.</p></section>
<section>
<h3>Adoption and integration</h3>
<p>The three adoption outcomes and integration journey use the same mature
integration-company cohort with a full 28-day observation window.
Seven-day adoption requires independent core work in the first 7 days.
Value conversion requires a training sync, work on a later IST calendar day,
and a confirming sync within 28 days. Sustained adoption requires work in
at least two of the first four integration-relative weeks. These outcome
cards are not assumed to be consecutive funnel stages.</p>
<h3>Workflow and issues</h3>
<p>Module combinations classify distinct core-active companies during the last
rolling 28 days, versus the preceding 28 days. Every company belongs to one
combination per period. Issues that need attention use these adjacent periods,
and each issue has its own eligible-company denominator. A later success in the
same company and workflow is only a follow-up signal, not verified repair.</p>
<p>Independent core activity excludes Accounting Sync because it does not
distinguish human from automatic execution, as well as failed actions, internal
staff and non-client companies.</p></section>`},
  frequency:{title:'Core usage frequency',body:()=>`<h3>How consistently do users return to core work?</h3><p>Count distinct users who performed independent qualifying core accounting work in each of the four most recent completed Monday–Sunday weeks (Asia/Kolkata). Every user belongs in exactly one bucket: active in one, two, three or four of the weeks. The denominator is all users with work in those four completed weeks.</p><div class="po-notice">Automatic or unclassified Accounting Sync events are excluded, as are failed events, internal users and non-client companies. Frequency and rolling 7-day WAU do not use identical windows, so their totals need not match.</div>`},
    adoption:{title:'Adoption outcomes',body:()=>`<h3>Three outcomes, not an assumed funnel</h3><p>The supplied reference has 360 fully observed eligible companies: 232 performed core work within 7 days, 82 reached a qualifying sync within 28 days, and 61 were active in at least 2 of the first 4 weeks.</p><p>These are presented as separate outcomes. A company must not be forced into a sequential funnel without confirming the event and eligibility rules.</p><div class="po-notice">The integration journey starts with 386 companies, not 360. This prototype preserves those distinct populations. Confirm the exclusion rules before wiring production data.</div><p>The adoption outcomes are separate from the three live core-active user KPIs. Filtered cohort values are illustrative and derived from local dated fixtures.</p>`},
  journey:{title:'Integration journey',body:()=>`<h3>One aligned stage table</h3><p>The reference shows 386 successful integrations, 251 companies starting accounting work, and 203 reaching accounting sync, for integrations from 8 June to 6 September 2026.</p><p>Each stage shows its share of the initial cohort and conversion from the immediately prior stage. At the snapshot, these are 65.0% for starting work and 80.9% for progressing from work to sync.</p><div class="po-notice">The previous design showed a 28.6% next-step conversion on the final visible stage. No next stage was supplied, so that unexplained number is not carried into this presentation.</div><p>Stage membership, order and the mature-cohort rule still need verification against production queries. AP, AR and transaction branches overlap; they are not sequential funnel steps.</p>`},
  mix:{title:'Module combinations',body:()=>`<h3>Which workflows are used together?</h3><p>These are the supplied, mutually exclusive combinations for core-active companies over the last 28 days. Current and previous shares are shown together; exact changes are in the comparison table.</p><p>The reference reports 33.9% multi-module adoption, up 2.8 percentage points. Displayed category values are rounded. Reported deltas are preserved rather than recalculated from rounded shares.</p><div class="po-notice">The company denominator was not provided, so this prototype does not invent absolute company counts. The original observation end date also needs confirmation.</div>`},
  friction:{title:'Issues that need attention',body:()=>`<h3>Observed company workflow issues</h3><p>Each row reports distinct client companies with a failed action or deliberate review reversion, divided by companies attempting that same workflow in the latest 28 days. Previous incidence uses the preceding 28 days.</p><p>“Later success” means a successful action in the same company and workflow after the latest recorded failure. This is a follow-up signal, not proof that the original transaction or upload was fixed. “Needs review” means no later success was observed by the end of the selected period.</p><div class="po-notice">Reverting to Needs Review is deliberate workflow rework, not a software error. Categories can overlap across companies. All figures and company drill-downs use verified Supabase events and the current published snapshot, excluding internal users and non-client companies.</div>`},
  workflows:{title:'Accounting work by workflow',body:()=>`<p>Breakdown of the <strong>251 companies</strong> that started accounting work in the original integration cohort. A company may use several workflows, so the three totals are not additive.</p><div class="po-data-wrap">${htmlTable(['Workflow / step','Companies / count','Within workflow'],[
    ['<strong>Bills / AP</strong>','<strong>165</strong>','65.7% of companies doing work'],['Bill upload','145','87.9%'],['Bill entry created','132','80.0%'],['Review / correction','72','43.6%'],['Upload failed','12','Issue count'],
    ['<strong>Invoices / AR</strong>','<strong>37</strong>','14.7% of companies doing work'],['Invoice upload','34','91.9%'],['Invoice entry created','5','13.5%'],['Upload failed','4','Issue count'],
    ['<strong>Statements / Transactions</strong>','<strong>152</strong>','60.6% of companies doing work'],['Statement upload','152','100.0%'],['Transaction work','139','91.4%'],['Accounting ready','132','95.0% of transaction work'],['Reverted after ready','51','Issue count']
   ])}</div><div class="po-notice">Reference snapshot only. Workflow percentages have different denominators in the source. Each module and activity now opens a contextual user/company breakdown. Individual records are illustrative.</div>`},
 };
 function showPOInfo(key='dates'){
  // Chart-specific definitions remain available; unknown/obsolete keys
  // never open a misleading implementation-notes popup.
  const d=definitions[key];
  if(!d)return;
  $('#po-detail-title').textContent=d.title;
  $('#po-detail-body').innerHTML=d.body();
  openDialog('po-detail-dialog');
  $('#po-detail-dialog').scrollTop=0;
 }
 function showPOTooltip(target){
  const [type,indexText]=target.dataset.poTip.split(':'),i=Number(indexText),tip=$('#po-tooltip');let title='',rows=[],note='';
  if(type==='weekly'||type==='feature'){
   const d=current.chart[i];if(!d)return;title=dateSpan(d.week,addDays(d.week,6));
   rows=type==='weekly'?[['Total users',d.users],['Returning',d.returning],['Newly active',d.new]]:[['AP / Bills',d.ap],['AR / Invoices',d.ar],['Transactions',d.txn]];
   note=type==='weekly'?'Click to explore users. Newly active means their first core event is in this week.':'Click a point for its module, or the column for all users in that week.';
  }else if(type==='frequency'){title=`Active in exactly ${i+1} ${i?'weeks':'week'}`;rows=[['Users',current.buckets[i]],['Share',pct(current.buckets[i],current.freqUsers.length)+'%']];note=dateSpan(current.freq.start,current.freq.end);}
  else if(type==='mix'){const d=mix[i];title=d[0];rows=[['Current share',d[1].toFixed(1)+'%'],['Previous share',d[2].toFixed(1)+'%'],['Change',(d[3]>0?'+':'')+d[3].toFixed(1)+' pp']];note='Reported changes use unrounded source values.';}
  else return;
  tip.innerHTML=`<strong>${esc(title)}</strong>${rows.map(([label,value])=>`<div class="po-tip-row"><span>${esc(label)}</span><b>${typeof value==='number'?nf(value):esc(value)}</b></div>`).join('')}<small>${esc(note)}</small>`;
  (target.closest('dialog')||document.body).append(tip);tip.hidden=false;
  const r=target.getBoundingClientRect(),b=tip.getBoundingClientRect();tip.style.left=Math.max(12,Math.min(innerWidth-b.width-12,r.left+r.width/2-b.width/2))+'px';tip.style.top=Math.max(12,r.top-b.height-10<12?Math.min(r.bottom+8,innerHeight-b.height-12):r.top-b.height-10)+'px';
 }
 function hidePOTooltip(){const tip=$('#po-tooltip');tip.hidden=true;if(tip.parentElement!==document.body)document.body.append(tip);}
 function poExpand(id){
  if(P.moved){closeDialog('po-report-expanded');return;}
  const card=$('#'+id);if(!card)return;P.reportTrigger=card.querySelector('[data-po-expand]');P.placeholder=document.createElement('div');P.placeholder.className='po-placeholder'+(card.classList.contains('po-full')?' po-full':'');P.placeholder.style.height=card.offsetHeight+'px';P.placeholder.textContent='Report open in expanded view';card.before(P.placeholder);P.moved=card;
  $('#po-expanded-label').textContent=$('h2',card).textContent+' · Expanded view';$('#po-expanded-mount').append(card);openDialog('po-report-expanded');requestAnimationFrame(renderCharts);
 }
 function poRestore(){if(P.moved&&P.placeholder){P.placeholder.replaceWith(P.moved);P.moved=null;P.placeholder=null;requestAnimationFrame(()=>{renderCharts();P.reportTrigger?.focus({preventScroll:true});});}}

 function setPage(page){
  P.page=page;root.hidden=page!=='overview';$('#retention-main').hidden=page==='overview';
  // The global Help button belongs to Retention. Overview's obsolete
  // implementation-notes popup must not be exposed on the live dashboard.
  const help=$('#help-button');
  help.hidden=page==='overview';
  help.style.display=page==='overview'?'none':'';
  const heading=page==='overview'?$('#po-page-heading'):$('#retention-main .page-heading');heading.append($('.global-controls'));
  $('#dashboard-trigger>span').textContent=page==='overview'?'Product Overview':'Retention & Churn';
  const options=[['po-menu-item','overview'],['retention-menu-item','retention']];options.forEach(([id,p])=>{const el=$('#'+id),selected=page===p;el.classList.toggle('is-current',selected);el.setAttribute('aria-checked',String(selected));const check=$(':scope > svg',el);if(check)check.hidden=!selected;});
  $('#date-range-popover .date-scope-note span').textContent=page==='overview'?'End month sets the reporting cutoff. Start month limits weekly trends. All KPIs use their own rolling windows.':'Retention follows cohort dates. Churn includes completed months only.';
  $('#date-range-popover .date-popover-heading span').textContent=page==='overview'?'Point-in-time reporting':'Applies across this dashboard';
  document.title=`AI Accountant | ${page==='overview'?'Product Overview v2':'Retention & Churn v6'}`;
  toggleDashboardMenu(false);hidePOTooltip();closeDatePicker(false);closeSelectMenu();window.scrollTo(0,0);
  requestAnimationFrame(page==='overview'?renderCharts:renderChurnChart);
 }
 // Wrap only date-range rendering; retention calculations and interactions stay intact.
 const originalRender=renderDashboard;
 renderDashboard=function(){originalRender();renderOverview();};
 $('#po-menu-item').addEventListener('click',()=>{setPage('overview');$('#dashboard-trigger').focus();});
 $('#retention-menu-item').addEventListener('click',()=>{setPage('retention');$('#dashboard-trigger').focus();});
 $('#help-button').addEventListener('click',e=>{
  if(P.page==='overview'){
   e.preventDefault();
   e.stopImmediatePropagation();
  }
 },true);
 $('#dashboard-trigger').addEventListener('keydown',e=>{if(['ArrowUp','ArrowDown'].includes(e.key)){e.preventDefault();e.stopImmediatePropagation();toggleDashboardMenu(true);$('#'+(P.page==='overview'?'po-menu-item':'retention-menu-item')).focus();}},true);
 $('#dashboard-menu').addEventListener('keydown',e=>{
  if(!['ArrowDown','ArrowUp','Home','End'].includes(e.key))return;e.preventDefault();e.stopImmediatePropagation();const opts=[$('#po-menu-item'),$('#retention-menu-item')],i=opts.indexOf(document.activeElement);opts[e.key==='Home'?0:e.key==='End'?1:(i+1)%2].focus();
 },true);
 $('#po-user-search').addEventListener('input',e=>{P.query=e.target.value;P.pageNo=1;renderRecords();});
 $('#po-clear-search').addEventListener('click',()=>{P.query='';$('#po-user-search').value='';P.pageNo=1;renderRecords();$('#po-user-search').focus();});
 $('#po-filter-button').addEventListener('click',()=>togglePOFilters($('#po-filter-panel').hidden));
 $('#po-reset-filters').addEventListener('click',()=>clearRecordFilters());
 $('#po-company-filter').addEventListener('change',e=>{P.companyFilter=e.target.value;P.pageNo=1;renderRecords();});
 $('#po-integration-filter').addEventListener('change',e=>{P.integrationFilter=e.target.value;P.pageNo=1;renderRecords();});
 $('#po-company-cadence').addEventListener('change',renderCompanyCadence);
 $('#po-company-scope').addEventListener('change',renderCompanyActivity);
 $('#po-expand-all-flows').addEventListener('click',()=>{const all=flowDefs.filter(f=>f.key!=='sync').every(f=>P.flowExpanded.has(f.key));P.flowExpanded=all?new Set():new Set(keys.filter(k=>k!=='sync'));renderCompanyActivity();});
 $('#po-company-back').addEventListener('click',()=>closeDialog('po-company-dialog'));
 $('#po-company-dialog').addEventListener('close',()=>{hidePOTooltip();requestAnimationFrame(()=>{if(P.companyTrigger?.isConnected)P.companyTrigger.focus({preventScroll:true});});});
 $('#po-record-dialog').addEventListener('close',()=>{togglePOFilters(false);hidePOTooltip();requestAnimationFrame(()=>{if(P.recordTrigger?.isConnected)P.recordTrigger.focus({preventScroll:true});});});
 $('#po-record-dialog').addEventListener('cancel',e=>{if(!$('#po-filter-panel').hidden){e.preventDefault();togglePOFilters(false);$('#po-filter-button').focus();}});
 $('#po-report-expanded').addEventListener('close',()=>{poRestore();hidePOTooltip();});
 document.addEventListener('click',e=>{
  const drill=e.target.closest('[data-po-drill]');if(drill){openReportDrill(drill.dataset.poDrill,drill);return;}
  const b=e.target.closest('button');if(!b)return;
  if(b.dataset.poJourneyModule){P.journeyModule=b.dataset.poJourneyModule;renderJourney();document.querySelector(`[data-po-journey-module="${P.journeyModule}"]`)?.focus({preventScroll:true});return;}
  if(b.hasAttribute('data-po-journey-toggle')){P.journeyExpanded=!P.journeyExpanded;renderJourney();document.querySelector('[data-po-journey-toggle]')?.focus({preventScroll:true});return;}
  if(b.dataset.poMetric){b.dataset.poMetric==='value'?openOutcome('converted'):openRecords(b.dataset.poMetric);return;}
  if(b.dataset.poOutcome){openOutcome(b.dataset.poOutcome);return;}
  if(b.dataset.poInfo){showPOInfo(b.dataset.poInfo);return;}
  if(b.dataset.poCompany){openCompany(b);return;}
  if(b.dataset.poCtab){showCompanyTab(b.dataset.poCtab);return;}
  if(b.dataset.poFlow){const k=b.dataset.poFlow;P.flowExpanded.has(k)?P.flowExpanded.delete(k):P.flowExpanded.add(k);renderCompanyActivity();$(`[data-po-flow="${k}"]`)?.focus({preventScroll:true});return;}
  if(b.dataset.poUser){const id=b.dataset.poUser;P.expanded.has(id)?P.expanded.delete(id):P.expanded.add(id);renderRecords();$(`[data-po-user="${id}"]`)?.focus({preventScroll:true});return;}
  if(b.dataset.poSort){const key=b.dataset.poSort;P.dir=P.sort===key?(P.dir==='asc'?'desc':'asc'):'asc';P.sort=key;P.pageNo=1;renderRecords();$(`[data-po-sort="${key}"]`)?.focus({preventScroll:true});return;}
  if(b.dataset.poPage&&!b.disabled){P.pageNo=Number(b.dataset.poPage);renderRecords();$('#po-record-scroll').scrollTop=0;return;}
  if(b.dataset.poRecordTab){setRecordTab(b.dataset.poRecordTab);return;}
  if(b.hasAttribute('data-po-clear-records')){clearRecordFilters(true);return;}
  if(b.dataset.poExpand){poExpand(b.dataset.poExpand);return;}
  if(b.hasAttribute('data-po-reset-range')){resetDateRange();return;}
  if(b.dataset.poSeries){const k=b.dataset.poSeries;if(P.series.has(k)&&P.series.size===1)return;P.series.has(k)?P.series.delete(k):P.series.add(k);b.setAttribute('aria-pressed',String(P.series.has(k)));renderFeatureChart();return;}
  if(b.dataset.poChartView){const k=b.dataset.poChartView;P.chartTables[k]=!P.chartTables[k];b.textContent=P.chartTables[k]?'View chart':k==='mix'?'View comparison table':'View table';if(k==='mix'){renderMix();return;}$('#po-'+k+'-chart-view').hidden=P.chartTables[k];$('#po-'+k+'-data').hidden=!P.chartTables[k];requestAnimationFrame(renderCharts);return;}
 });
 document.addEventListener('pointerdown',e=>{if(!e.target.closest('.po-filter-wrap')&&!e.target.closest('.ui-select-menu'))togglePOFilters(false);},true);
 document.addEventListener('keydown',e=>{
  const tab=e.target.closest('[data-po-record-tab]'),ctab=e.target.closest('[data-po-ctab]');
  if((tab||ctab)&&['ArrowLeft','ArrowRight','Home','End'].includes(e.key)){
   e.preventDefault();const list=tab?recordTabs().map(t=>t.key):['overview','activity','journey'],val=tab?P.tab:P.companyTab,idx=list.indexOf(val),next=list[e.key==='Home'?0:e.key==='End'?list.length-1:(idx+(e.key==='ArrowRight'?1:list.length-1))%list.length];
   if(tab){setRecordTab(next);}else showCompanyTab(next,true);
  }
  if(e.key==='Escape')hidePOTooltip();
  const drill=e.target.closest('[data-po-drill]');if(drill&&drill.tagName.toLowerCase()!=='button'&&['Enter',' '].includes(e.key)){e.preventDefault();openReportDrill(drill.dataset.poDrill,drill);}
  const mt=e.target.closest('[data-po-journey-module]');if(mt&&['ArrowLeft','ArrowRight','Home','End'].includes(e.key)){e.preventDefault();const modules=['ap','ar','txn'],idx=modules.indexOf(P.journeyModule);P.journeyModule=modules[e.key==='Home'?0:e.key==='End'?2:(idx+(e.key==='ArrowRight'?1:2))%3];renderJourney();document.querySelector(`[data-po-journey-module="${P.journeyModule}"]`)?.focus({preventScroll:true});}
 });
 document.addEventListener('pointerover',e=>{const t=e.target.closest('[data-po-tip]');if(t)showPOTooltip(t);});
 document.addEventListener('pointerout',e=>{if(e.target.closest('[data-po-tip]')&&!e.relatedTarget?.closest?.('[data-po-tip]'))hidePOTooltip();});
 document.addEventListener('focusin',e=>{const t=e.target.closest('[data-po-tip]');if(t)showPOTooltip(t);});
 document.addEventListener('focusout',e=>{if(e.target.closest('[data-po-tip]'))hidePOTooltip();});
 document.addEventListener('scroll',hidePOTooltip,true);
 let resizeFrame;
 const resize=()=>{cancelAnimationFrame(resizeFrame);resizeFrame=requestAnimationFrame(renderCharts);hidePOTooltip();};
 window.addEventListener('resize',resize);
 if('ResizeObserver' in window){const observer=new ResizeObserver(resize);observer.observe(root);observer.observe($('#po-expanded-mount'));}
 // Only check original fixture totals when the original reference date is active.
  if(P.asof===SNAPSHOT_DATE){
   console.assert(current.weekly.length===153,'WAU fixture should reconcile to 153');
   console.assert(current.monthly.length===429,'MAU fixture should reconcile to 429');
   console.assert(current.buckets.join(',')==='299,50,29,42','Frequency fixture should reconcile');
   console.assert(current.prevW.length===181,'Prior 7-day fixture should reconcile');
   console.assert(current.prevM.length===292,'Prior 30-day fixture should reconcile');
  }
  setPage('overview');
 // Expose a small read-only test snapshot rather than internal mutable state.
 window.overviewPrototype={snapshot:()=>({asof:P.asof,wau:current.weekly.length,mau:current.monthly.length,previousWAU:current.prevW.length,previousMAU:current.prevM.length,frequency:current.buckets.slice(),weekly:current.chart.map(v=>({...v})),adoptionEligible:current.adoption.length,converted:current.adoption.filter(c=>c.converted).length,filteredUserCount:recordCandidates().length,drill:P.drill?{kind:P.drill.kind,key:P.drill.key,index:P.drill.index,tab:P.tab,tabs:recordTabs().map(t=>({key:t.key,label:t.label,count:t.count})),visibleCompanies:recordCandidates().reduce((n,u)=>n+u.count,0)}:null,journeyModules:moduleDefs.map(m=>({key:m.key,count:current.journey.filter(c=>c.modules?.includes(m.key)).length,steps:m.steps.map(s=>({key:s.key,count:current.journey.filter(c=>c.steps?.includes(s.key)).length}))})),page:P.page})};
})();

