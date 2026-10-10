
'use strict';
/* Compatibility runtime for the approved prototype surface.
   Retention KPI cards read live production aggregates through the app API.
   Remaining report fixtures and drill-down identities are illustrative until migrated.
   v6: company activity drill-down; card-level navigation; requested font stack.
   PP Neue Montreal is resolved from the viewer's installed fonts. The licensed
   font is NOT embedded. Add your licensed @font-face URL in production.
   Company activity details are deterministic illustrative data, not inferred
   facts about the named companies. Existing report calculations are preserved. */
const $ = (selector, root=document) => root.querySelector(selector);
const $$ = (selector, root=document) => [...root.querySelectorAll(selector)];
const icon = name => `<svg class="icon" aria-hidden="true"><use href="#i-${name}"/></svg>`;
const esc = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const fmt = new Intl.NumberFormat('en-US');
const dateLabel = iso => iso ? new Date(iso+'T12:00:00Z').toLocaleDateString('en-GB',{day:'numeric',month:'short',timeZone:'UTC'}).replace('Sept','Sep') : '-';
const cohortLabel = iso => new Date(iso+'T12:00:00Z').toLocaleDateString('en-GB',{day:'numeric',month:'short',year:'numeric',timeZone:'UTC'});
const cohorts = [
 ['2026-03-02',11,[7,6,3,2,4,4,2,1]],['2026-03-09',6,[4,3,2,2,2,1,1,2]],['2026-03-16',6,[4,4,2,2,3,2,1,3]],['2026-03-23',9,[4,1,3,2,1,0,2,2]],['2026-03-30',4,[2,0,0,0,0,0,0,0]],
 ['2026-04-06',6,[5,2,3,2,2,3,2,2]],['2026-04-13',7,[2,2,3,4,2,2,2,2]],['2026-04-20',6,[5,1,2,1,1,1,0,0]],['2026-04-27',7,[3,2,1,0,1,0,1,2]],
 ['2026-05-04',13,[10,6,3,3,3,2,1,1]],['2026-05-11',19,[16,9,10,7,6,7,6,6]],['2026-05-18',15,[9,8,6,8,6,7,4,4]],['2026-05-25',20,[10,10,9,9,9,4,3,3]],
 ['2026-06-01',21,[10,11,9,8,8,8,6,5]],['2026-06-08',16,[9,7,6,4,6,4,5,5]],['2026-06-15',17,[12,9,6,8,7,8,7,5]],['2026-06-22',18,[10,5,6,4,4,4,4,4]],['2026-06-29',27,[15,11,9,11,15,9,9,9]],
 ['2026-07-06',24,[12,6,8,8,6,5,3,5]],['2026-07-13',22,[12,10,10,8,7,1,4,3]],['2026-07-20',15,[7,5,6,3,2,2,2,2]],['2026-07-27',14,[6,6,5,3,1,2,1,2]],
 ['2026-08-03',15,[3,4,3,1,2,1,1,null]],['2026-08-10',22,[9,4,4,2,0,0,null,null]],['2026-08-17',35,[15,13,7,9,9,null,null,null]],['2026-08-24',19,[8,6,3,4,null,null,null,null]],['2026-08-31',25,[6,6,3,null,null,null,null,null]],
 ['2026-09-07',21,[8,5,null,null,null,null,null,null]],['2026-09-14',19,[11,null,null,null,null,null,null,null]],['2026-09-21',28,[null,null,null,null,null,null,null,null]],['2026-09-28',25,[null,null,null,null,null,null,null,null]]
].map(([date,n,values])=>({date,n,values}));
const months = [
 {month:'Apr',rate:45.5,delta:null,churned:15,eligible:33,entered:15,reactivated:0},
 {month:'May',rate:57.4,delta:11.9,churned:35,eligible:61,entered:21,reactivated:1},
 {month:'Jun',rate:52.7,delta:-4.7,churned:68,eligible:129,entered:37,reactivated:4},
 {month:'Jul',rate:60.4,delta:7.7,churned:125,eligible:207,entered:59,reactivated:2},
 {month:'Aug',rate:62.1,delta:1.7,churned:187,eligible:301,entered:68,reactivated:6},
 {month:'Sep',rate:67.6,delta:5.5,churned:269,eligible:398,entered:94,reactivated:12}
];
// Calendar-month filtering is deliberate: the supplied picker selected whole months.
// No date math uses the viewer's locale or time zone.
const SNAPSHOT_DATE='2026-10-04';
const CURRENT_MONTH=new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Kolkata',year:'numeric',month:'2-digit'}).format(new Date());
const [currentYear,currentMonthNumber]=CURRENT_MONTH.split('-').map(Number);
const LAST_COMPLETE_MONTH=new Date(Date.UTC(currentYear,currentMonthNumber-2,1)).toISOString().slice(0,7);
const MONTH_WINDOW_COUNT=6;
// Shareable, server-rendered historical Overview date selections.
const overviewQuery=new URLSearchParams(window.location.search);
const qStart=overviewQuery.get('from'),qEnd=overviewQuery.get('to');
const validOverviewMonth=s=>typeof s==='string'&&/^\d{4}-(0[1-9]|1[0-2])$/.test(s);
let appliedRange=window.location.pathname==='/overview'
  &&validOverviewMonth(qStart)&&validOverviewMonth(qEnd)&&qStart<=qEnd
  ?{preset:overviewQuery.get('preset')||'custom',start:qStart,end:qEnd}
  :{preset:'lifetime',start:null,end:null};
let retentionView='weekly';
let activationTotals={active:512,inactive:2210,total:2722,ttv:10.7,ttvN:512};
let liveRetentionKpis=null,retentionKpiRequest=0;

function retentionDateBounds(){
 if(appliedRange.preset==='lifetime')return {from:null,to:null};
 return {from:monthFirst(appliedRange.start),to:monthLast(appliedRange.end)};
}
function retentionMonthLabel(key){
 if(!key)return 'No completed month';
 return new Date(key+'-01T12:00:00Z').toLocaleDateString('en-GB',{month:'short',year:'numeric',timeZone:'UTC'}).replace('Sept','Sep');
}
function updateLiveRetentionCards(){
 const data=liveRetentionKpis;if(!data)return;
 const scope=rangeLabel(appliedRange),activation=data.activation,ttv=data.ttv,churn=data.churn;
 const activationRate=activation.rate_pct==null?'-':Number(activation.rate_pct).toFixed(1)+'%';
 $('#activation-card .metric-period').textContent=scope;
 $('#activation-card .metric-value').textContent=activationRate;
 $('#activation-card .metric-note').textContent=activation.integrated
   ? `${fmt.format(activation.activated)} of ${fmt.format(activation.integrated)} integrated companies activated`
   : 'No successful integrations in this range';
 $('#activation-card').setAttribute('aria-label',`Activation rate, ${activationRate}, ${scope}. View definition.`);

 const avgDays=ttv.avg_hours==null?null:Number(ttv.avg_hours)/24;
 const medianDays=ttv.median_hours==null?null:Number(ttv.median_hours)/24;
 $('#ttv-card .metric-period').textContent=scope;
 $('#ttv-card .metric-value').innerHTML=avgDays==null?'-':avgDays.toFixed(1)+'<span class="unit">days</span>';
 $('#ttv-card .metric-note').textContent=ttv.companies
   ? `${fmt.format(ttv.companies)} activated companies with measurable TTV`
   : 'No activated companies with measurable TTV';
 $('#ttv-modal-value').innerHTML=avgDays==null?'-':avgDays.toFixed(1)+' <span>days</span>';
 $('#ttv-description').textContent='Average time from first successful integration to the activation-closing sync: a later-day non-sync core job, followed by a qualifying Accounting Sync.';
 $('#ttv-scope-detail').hidden=false;
 $('#ttv-scope-detail').innerHTML=ttv.companies
   ? `<span>${esc(scope)} · ${fmt.format(ttv.companies)} companies · median ${medianDays.toFixed(1)} days</span>`
   : `<span>${esc(scope)} · no measurable TTV</span>`;

 const churnRate=churn.rate_pct==null?'-':Number(churn.rate_pct).toFixed(1)+'%';
 const churnPeriod=retentionMonthLabel(churn.month);
 $('#churn-metric-card .metric-period').textContent=churnPeriod;
 $('#churn-metric-card .metric-value').textContent=churnRate;
 $('#churn-metric-card .metric-note').textContent=churn.month
   ? `${fmt.format(churn.churned)} of ${fmt.format(churn.eligible)} eligible companies churned`
   : 'No completed month in this range';
 $('#churn-metric-card').setAttribute('aria-label',`Monthly churn, ${churnPeriod}: ${churnRate}. View definition.`);
 $('#churn-modal-period').textContent=churnPeriod;
 $('#churn-modal-value').textContent=churnRate;
 $('#churn-metric-description').textContent=churn.month
   ? `Share of companies activated before ${churnPeriod} with no core activity during that completed calendar month.`
   : 'Monthly churn is calculated only for completed calendar months.';
 $('#churn-modal-detail').innerHTML=churn.month
   ? `<span><strong>${fmt.format(churn.churned)}</strong> of <strong>${fmt.format(churn.eligible)}</strong> eligible companies</span>`
   : `<span>${esc(scope)}</span>`;
}
async function loadRetentionKpis(){
 const requestId=++retentionKpiRequest,bounds=retentionDateBounds();
 try{
  const response=await fetch('/api/retention-kpis',{
   method:'POST',
   headers:{'Content-Type':'application/json'},
   body:JSON.stringify(bounds)
  });
  if(!response.ok)throw new Error('retention_kpis_unavailable');
  const data=await response.json();
  if(requestId!==retentionKpiRequest)return;
  liveRetentionKpis=data;updateLiveRetentionCards();
 }catch(error){
  if(requestId!==retentionKpiRequest)return;
  console.error('retention-kpis',error);
 }
}
function shiftMonth(key,offset){const [year,month]=key.split('-').map(Number);return new Date(Date.UTC(year,month-1+offset,1)).toISOString().slice(0,7);}
function monthFirst(key){return key+'-01';}
function monthLast(key){return new Date(Date.parse(shiftMonth(key,1)+'-01T12:00:00Z')-86400000).toISOString().slice(0,10);}
function shortMonth(key){return new Date(key+'-01T12:00:00Z').toLocaleDateString('en-GB',{month:'short',year:'numeric',timeZone:'UTC'}).replace('Sept','Sep');}
function monthInRange(key,range=appliedRange){return range.preset==='lifetime'||Boolean(key&&range.start&&range.end&&key>=range.start&&key<=range.end);}
function dateInRange(iso,range=appliedRange){return Boolean(iso&&iso<=SNAPSHOT_DATE&&monthInRange(iso.slice(0,7),range));}
function rangeLabel(range){
 if(range.preset==='lifetime')return 'Lifetime';
 if(!range.start||!range.end)return 'Choose months';
 if(range.start===range.end)return shortMonth(range.start);
 if(range.start.slice(0,4)===range.end.slice(0,4))return shortMonth(range.start).split(' ')[0]+' – '+shortMonth(range.end);
 return shortMonth(range.start)+' – '+shortMonth(range.end);
}
function presetRange(value){return value==='lifetime'?{preset:'lifetime',start:null,end:null}:{preset:value,start:shiftMonth(LAST_COMPLETE_MONTH,1-Number(value)),end:LAST_COMPLETE_MONTH};}
function visibleChurnMonths(){return months.filter((m,i)=>monthInRange('2026-'+String(i+4).padStart(2,'0')));}
function retentionCohortLabel(date,view=retentionView){return view==='monthly'?shortMonth(date.slice(0,7)):cohortLabel(date);}

let reverseCohorts=false, movedReport=null, reportPlaceholder=null;
let churnView='trend';
function visibleCohorts(){
 const source=retentionView==='monthly'?monthlyCohorts:cohorts;
 const rows=source.filter(c=>monthInRange(c.date.slice(0,7)));
 return reverseCohorts ? rows.reverse() : rows;
}
function cellColors(ratio){
 const start=[239,244,255],end=[29,78,216];
 const rgb=start.map((value,i)=>Math.round(value+(end[i]-value)*ratio));
 const linear=rgb.map(value=>{let s=value/255;return s<=.04045?s/12.92:((s+.055)/1.055)**2.4});
 const luminance=.2126*linear[0]+.7152*linear[1]+.0722*linear[2];
 return `background:rgb(${rgb.join(',')});color:${luminance<.20?'#fff':'#203050'}`;
}
function heatCell(count,denominator,label,week,cohortKey){
 const period=retentionView==='monthly'?'Month':'Week';
 if(count===null || denominator===0)return '<td><span class="heat-cell unavailable" title="This return window is not yet eligible" aria-label="Not yet eligible">-</span></td>';
 const percent=(100*count/denominator).toFixed(1);
 const tip=`${label}|${period} ${week}|${count} retained · ${denominator-count} churned|${percent}% retention`;
 return `<td><button type="button" class="heat-cell" style="${cellColors(count/denominator)}" data-tip="${esc(tip)}" data-cohort="${esc(cohortKey)}" data-week="${week}" data-interval="${retentionView}" aria-haspopup="dialog" aria-controls="activation-dialog" aria-label="${esc(label)}, ${period.toLowerCase()} ${week}: ${count} retained, ${denominator-count} churned out of ${denominator} companies. View users and companies."><span class="percentage">${percent}%</span><span class="fraction">${count}/${denominator}</span></button></td>`;
}
function renderHeatmap(){
 const rows=visibleCohorts(),monthly=retentionView==='monthly';
 const period=monthly?'Month':'Week',columns=monthly?MONTH_WINDOW_COUNT:8;
 $('#retention-report').style.setProperty('--retention-height',Math.min(600,Math.max(365,232+rows.length*45))+'px');
 $('#heatmap-head').innerHTML=`<tr><th scope="col">Cohort ${period.toLowerCase()}</th><th scope="col" title="Companies in this activation cohort">n</th>${Array.from({length:columns},(_,i)=>`<th scope="col">${period} ${i+1}</th>`).join('')}</tr>`;
 $('.heatmap-table').classList.toggle('is-monthly',monthly);
 $('.heatmap-table').setAttribute('aria-label',`${monthly?'Monthly':'Weekly'} company retention`);
 $('.heatmap-scroll').setAttribute('aria-label',`${monthly?'Monthly':'Weekly'} retention. Scroll to browse all cohorts and return windows.`);
 $('#monthly-sample').hidden=!monthly;
 $('#retention-window-key').hidden=!monthly;
 $('#retention-view-description').textContent=monthly?'Monthly activation cohorts with completed calendar-month return windows. Month 1 is the calendar month after activation. Illustrative company-level activity. Select a cell to inspect retained and churned companies.':'Weekly activation cohorts. Select a cell to inspect retained and churned companies.';
 $('#heatmap-body').innerHTML=rows.length?rows.map(c=>`<tr><th scope="row">${retentionCohortLabel(c.date)}</th><td class="cohort-size">${c.n}</td>${c.values.map((n,i)=>heatCell(n,c.n,retentionCohortLabel(c.date),i+1,c.date)).join('')}</tr>`).join(''):`<tr><td colspan="${columns+2}"><div class="heatmap-empty">${icon('calendar')}<strong>No ${monthly?'monthly':'weekly'} cohorts in this range</strong><p>Try a wider date range to see retention.</p><button type="button" class="ui-text-button" data-reset-range>View lifetime</button></div></td></tr>`;
 const aggregate=Array.from({length:columns},(_,i)=>rows.reduce((a,c)=>{if(c.values[i]!==null){a.count+=c.values[i];a.n+=c.n;}return a},{count:0,n:0}));
 $('#heatmap-foot').innerHTML=rows.length?`<tr><th scope="row" title="Pooled retained companies divided by all eligible companies, not an unweighted mean of cohort percentages">Average</th><td class="cohort-size"></td>${aggregate.map((a,i)=>heatCell(a.count,a.n,'All visible eligible cohorts',i+1,'all')).join('')}</tr>`:'';
 $('#cohort-count').innerHTML=`<strong>${rows.length} ${monthly?'monthly':'weekly'} cohorts</strong> <span aria-hidden="true">·</span> ${fmt.format(rows.reduce((s,c)=>s+c.n,0))} companies`;
 $('.heatmap-scroll').scrollTop=0;
 $('.heatmap-scroll').scrollLeft=0;
 if(movedReport?.id==='retention-report')$('#expanded-label').textContent=`${monthly?'Monthly':'Weekly'} retention · Expanded view`;
 hideTooltip();
}

function renderChurn(){
 const visible=visibleChurnMonths(),latest=visible.at(-1);
 $('#selected-rate-label').textContent='Latest rate';
 $('#selected-rate').textContent=latest?latest.rate.toFixed(1)+'%':'-';
 $('#selected-month').textContent=latest?latest.month+' 2026':'No completed month';
 $('#selected-entered').textContent=latest?fmt.format(latest.entered):'-';
 $('#selected-reactivated').textContent=latest?fmt.format(latest.reactivated):'-';
 $('#entered-month').textContent=$('#reactivated-month').textContent=latest?'during '+latest.month:'In selected range';
 $('#churn-table-body').innerHTML=visible.map((m,i)=>`<tr class="${i===visible.length-1?'selected':''}"><td>${m.month} 2026</td><td>${m.rate.toFixed(1)}%</td><td class="${m.delta===null?'dash':m.delta>0?'bad-delta':'good-delta'}" title="Change from the preceding calendar month, even if it is outside the selected range">${m.delta===null?'-':(m.delta>0?'+':'')+m.delta.toFixed(1)+' pp'}</td><td>${m.churned}</td><td>${m.eligible}</td><td>${m.entered}</td><td>${m.reactivated}</td></tr>`).join('');
 $('#churn-date-scope').textContent=visible.length?(visible.length===1?visible[0].month+' 2026':visible[0].month+' – '+latest.month+' 2026'):'No completed months';
 $('#churn-footer-count').innerHTML=latest?`<strong>${latest.churned}</strong> of <strong>${latest.eligible}</strong> eligible companies in ${latest.month}`:'Only completed calendar months are included';
 $('#churn-empty').hidden=visible.length>0;
 $('#churn-empty-copy').textContent=appliedRange.start===CURRENT_MONTH?'October 2026 is still in progress. Its churn rate is not calculated yet.':'There is no monthly churn data for the selected dates. Try a wider or earlier range.';
 $('#churn-trend-view').hidden=visible.length===0||churnView!=='trend';
 $('#churn-data-view').hidden=visible.length===0||churnView!=='table';
 renderChurnChart();
}

function renderChurnChart(){
 const chart=$('#churn-chart'),visible=visibleChurnMonths();
 if(!chart||$('#churn-trend-view').hidden||!visible.length)return;
 const rect=chart.parentElement.getBoundingClientRect();
 const width=Math.max(230,Math.round(rect.width)),height=Math.max(190,Math.round(rect.height)),narrow=width<380;
 const left=narrow?36:46,right=narrow?10:20,top=24,bottom=32;
 const band=(width-left-right)/visible.length,barWidth=Math.max(14,Math.min(82,band*.48));
 const x=i=>left+band*(i+.5),y=rate=>top+(100-rate)/100*(height-top-bottom);
 const latestIndex=visible.length-1;
 chart.setAttribute('viewBox',`0 0 ${width} ${height}`);
 chart.innerHTML=`<title>Monthly churn rate bar chart</title><desc>${visible.map(m=>m.month+' 2026: '+m.rate+'%').join(', ')}. Bars start at zero on a zero-to-100-percent scale. The latest completed month in the selected range is highlighted.</desc>
 <g aria-hidden="true">${[0,25,50,75,100].map(rate=>`<line x1="${left}" x2="${width-right}" y1="${y(rate)}" y2="${y(rate)}" stroke="${rate===0?'#dfe5ee':'#edf0f5'}" ${rate===0?'':'stroke-dasharray="2 4"'}/><text x="${left-10}" y="${y(rate)+3}" fill="#8997aa" font-size="${narrow?9:10}" text-anchor="end">${rate}%</text>`).join('')}</g>
 ${visible.map((m,i)=>{
  const center=x(i),barTop=y(m.rate),barHeight=y(0)-barTop,isLatest=i===latestIndex;
  return `<g class="chart-data-point churn-bar-group" role="img" tabindex="0" aria-label="${m.month} 2026: ${m.rate}% churn; ${m.churned} of ${m.eligible} eligible companies. ${m.entered} entered churn, ${m.reactivated} reactivated." data-churn-point="${i}">
   <rect class="churn-bar" x="${center-barWidth/2}" y="${barTop}" width="${barWidth}" height="${barHeight}" rx="3" fill="${isLatest?'#315de5':'#8aa3ee'}"/>
   <rect class="bar-outline" x="${center-barWidth/2-3}" y="${barTop-3}" width="${barWidth+6}" height="${barHeight+6}" rx="5" fill="none" stroke="#315de5" stroke-width="1.5"/>
   <text class="bar-label" x="${center}" y="${barTop-11}" font-size="${narrow?10:12}" text-anchor="middle" fill="${isLatest?'#264cc5':'#526888'}" font-weight="${isLatest?'650':'550'}">${m.rate.toFixed(1)}%</text>
  </g>`;
 }).join('')}
 <g aria-hidden="true">${visible.map((m,i)=>`<text x="${x(i)}" y="${height-8}" fill="${i===latestIndex?'#375ec5':'#8290a5'}" font-size="${narrow?10:11}" text-anchor="middle" font-weight="${i===latestIndex?'600':'400'}">${m.month}</text>`).join('')}</g>`;
}
function setChurnView(view){
 if(!['trend','table'].includes(view))return;
 churnView=view;
 $$('[data-churn-view]').forEach(tab=>{const active=tab.dataset.churnView===view;tab.setAttribute('aria-selected',String(active));tab.tabIndex=active?0:-1;});
 $('#churn-trend-view').hidden=!visibleChurnMonths().length||view!=='trend';
 $('#churn-data-view').hidden=!visibleChurnMonths().length||view!=='table';
 hideChurnTooltip();
 if(view==='trend')requestAnimationFrame(renderChurnChart);
}
function showChurnTooltip(target){
 const m=visibleChurnMonths()[Number(target.dataset.churnPoint)];if(!m)return;
 const tip=$('#churn-tooltip');
 (target.closest('dialog')||document.body).append(tip);
 tip.innerHTML=`<div class="tip-heading">${m.month} 2026</div><div class="tip-rate">${m.rate.toFixed(1)}%<span class="tip-change ${m.delta<0?'negative':''}">${m.delta===null?'':(m.delta>0?'+':'')+m.delta.toFixed(1)+' pp vs prev.'}</span></div><div class="tip-row"><span>Churned / eligible</span><strong>${m.churned} / ${m.eligible}</strong></div><div class="tip-row"><span>Entered churn</span><strong>${m.entered}</strong></div><div class="tip-row"><span>Reactivated</span><strong>${m.reactivated}</strong></div>`;
 tip.hidden=false;
 target.setAttribute('aria-describedby','churn-tooltip');
 const box=(target.querySelector('.churn-bar')||target).getBoundingClientRect(),t=tip.getBoundingClientRect();
 let left=box.left+box.width/2-t.width/2;
 let top=box.top-t.height-12;
 if(top<12)top=box.bottom+8;
 tip.style.left=Math.max(12,Math.min(left,innerWidth-t.width-12))+'px';
 tip.style.top=Math.max(12,Math.min(top,innerHeight-t.height-12))+'px';
}
function hideChurnTooltip(){
 const tip=$('#churn-tooltip');if(!tip)return;
 tip.hidden=true;
 $$('.chart-data-point[aria-describedby]').forEach(p=>p.removeAttribute('aria-describedby'));
 if(tip.parentElement!==document.body)document.body.append(tip);
}
function toggleDashboardMenu(open,focusItem=false){
 if(open){closeDatePicker(false);closeSelectMenu();}
 $('#dashboard-menu').hidden=!open;
 $('#dashboard-trigger').setAttribute('aria-expanded',String(open));
 if(open&&focusItem)$('#retention-menu-item').focus();
}

// The drill-down deliberately uses fictitious companies, never copied emails.
const activeSeed=[
 ['arjun@ledgerdesk.example',['Northstar Traders'],'2026-10-01','2026-10-02',1,'2026-10-03'],
 ['meera@balanceworks.example',['Willow Textiles'],'2026-09-29','2026-10-01',2,'2026-10-03'],
 ['rohan@clearbooks.example',['Harbor Supplies'],'2026-09-28','2026-10-01',3,'2026-10-02'],
 ['kavya@accountingco.example',['Cedar Distributors'],'2026-09-25','2026-09-30',5,'2026-10-02'],
 ['dev@ledgerlane.example',['Maple Industries','Maple Logistics'],'2026-09-23','2026-09-30',7,'2026-10-03'],
 ['aisha@financedesk.example',['Stonebridge Foods','Stonebridge Retail'],'2026-09-21','2026-09-29',8,'2026-10-02'],
 ['neel@bookkeep.example',['Bluebird Engineering'],'2026-09-20','2026-09-28',8,'2026-09-30'],
 ['tara@precisebooks.example',['Summit Furnishings'],'2026-09-18','2026-09-27',9,'2026-10-01'],
 ['vikram@numbersco.example',['Oakfield Components','Oakfield Exports','Oakfield Stores'],'2026-09-15','2026-09-26',11,'2026-10-02'],
 ['priya@accountsdesk.example',['Silverline Packaging'],'2026-09-14','2026-09-25',11,'2026-09-29'],
 ['ananya@ledgerpro.example',['Greenfield Appliances'],'2026-09-12','2026-09-24',12,'2026-09-30'],
 ['kabir@accountable.example',['Horizon Wholesale','Horizon Services'],'2026-09-10','2026-09-23',13,'2026-09-28'],
 ['isha@booksmart.example',['Riverbend Manufacturing'],'2026-09-05','2026-09-20',15,'2026-09-27'],
 ['sahil@finledger.example',['Parkside Electronics'],'2026-08-28','2026-09-17',20,'2026-09-26'],
 ['nisha@ledgeroffice.example',['Evergreen Trading','Evergreen Exports'],'2026-08-23','2026-09-14',22,'2026-09-24'],
 ['amit@balancedesk.example',['Westhaven Equipment'],'2026-08-20','2026-09-10',21,'2026-09-22']
];
const inactiveSeed=[
 ['ash@companybooks.example',['Amber Office Supplies'],'2026-10-03',null,null,null],
 ['lina@finworks.example',['Elmwood Textiles','Elmwood Retail'],'2026-10-02',null,null,null],
 ['om@ledgerteam.example',['Crestline Components'],'2026-10-01',null,null,null],
 ['sana@bookoffice.example',['Meadow Foods'],'2026-09-30',null,null,null],
 ['jay@accountsteam.example',['Redwood Packaging','Redwood Trading'],'2026-09-28',null,null,null],
 ['diya@taxdesk.example',['Seabrook Furnishings'],'2026-09-24',null,null,null],
 ['ved@ledgerworks.example',['Aster Distributors'],'2026-09-20',null,null,null],
 ['rhea@financeoffice.example',['Pinecrest Electricals'],'2026-09-17',null,null,null],
 ['adi@bookworks.example',['Bellflower Industries','Bellflower Stores'],'2026-09-10',null,null,null],
 ['maya@numbersdesk.example',['Lakeside Trading'],'2026-09-04',null,null,null],
 ['raj@dailyledger.example',['Brookside Exports'],'2026-08-25',null,null,null],
 ['leela@accountingdesk.example',['Springfield Hardware','Springfield Wholesale'],'2026-08-17',null,null,null]
];
function toUsers(seed,prefix){return seed.map(([email,companies,signup,activated,days,last],i)=>({id:prefix+i,email,companies,signup,activated,days,last,count:companies.length}));}
const records={activated:toUsers(activeSeed,'a'),inactive:toUsers(inactiveSeed,'n'),retained:[],churned:[]};
const tableState={mode:'activation',tab:'activated',query:'',company:'all',month:'all',sort:'activated',direction:'desc',page:1,expanded:new Set(),pageSize:10};
let retentionContext=null;
const addDays=(iso,days)=>new Date(Date.parse(iso+'T12:00:00Z')+days*86400000).toISOString().slice(0,10);
const monthName=iso=>new Date(iso+'-01T12:00:00Z').toLocaleDateString('en-GB',{month:'long',year:'numeric',timeZone:'UTC'});
const hashText=value=>{let h=2166136261;for(const char of value){h^=char.charCodeAt(0);h=Math.imul(h,16777619);}return h>>>0;};

/*
 * Deterministic demo identities, not inferred production records.
 * A company belongs to one activation cohort. Its identity is stable across
 * weeks, and each week's returning set matches the supplied cell numerator.
 * Demo activity dates are illustrative calendar-week dates only, not a change
 * to production return-window logic. Connect production company IDs and the
 * actual cohort/window predicate here when implementing the real dashboard.
 */
const cohortCatalog=new Map(cohorts.map((cohort,cohortIndex)=>{
 const brands=['Aster','Juniper','Mosaic','Atlas','Larch','Meadow','Cobalt','Orchard','Pinecrest','Evergreen','Crescent','Brookside','Redwood','Meridian','Cypress','Fernwood','Ashford','Riverstone','Westbrook','Brighton','Fairview','Hawthorne','Hillcrest','Eastwood','Parkside','Westridge','Seabrook','Woodland','Millstone','Kingsley','Newleaf'];
 const names=['ananya','rohan','meera','arjun','kavya','dev','aisha','neel','tara','vikram','priya','kabir','isha','aarav','diya','sahil','nisha','aman','leela','rahul'];
 const companies=[];
 let companyIndex=0,ownerIndex=0;
 while(companyIndex<cohort.n){
  const groupSize=Math.min([2,1,2,1,1][ownerIndex%5],cohort.n-companyIndex);
  const code=cohort.date.slice(5).replace('-','');
  const ownerId=`c${cohortIndex}-u${ownerIndex}`;
  const firstName=names[ownerIndex%names.length];
  const email=`${firstName}${ownerIndex>=names.length?ownerIndex+1:''}.${code}@ledgerdesk.example`;
  const brand=brands[(cohortIndex+ownerIndex*3)%brands.length];
  const signedUp=addDays(cohort.date,-(3+ownerIndex%12));
  const activated=addDays(cohort.date,ownerIndex%5);
  for(let j=0;j<groupSize;j++,companyIndex++){
   companies.push({id:`cohort-${cohortIndex}-company-${companyIndex}`,index:companyIndex,ownerId,email,
    name:`${brand} ${j===0?'Traders':'Retail'}${cohortIndex>0?' '+String(cohortIndex+1).padStart(2,'0'):''}`,
    integration:'Tally',signup:signedUp,activated,last:activated,returns:[],cohort:cohort.date});
  }
  ownerIndex++;
 }
 cohort.values.forEach((count,weekIndex)=>{
  if(count===null){companies.forEach(company=>company.returns.push(null));return;}
  const ranked=[...companies].sort((a,b)=>hashText(`${cohort.date}|${weekIndex}|${a.index}`)-hashText(`${cohort.date}|${weekIndex}|${b.index}`)||a.index-b.index);
  const returned=new Set(ranked.slice(0,count).map(company=>company.id));
  companies.forEach(company=>{
   const active=returned.has(company.id);company.returns.push(active);
   if(active)company.last=addDays(cohort.date,(weekIndex+1)*7+(company.index+weekIndex)%7);
  });
 });
 return [cohort.date,companies];
}));

/*
 * Explicitly synthetic company-level fixtures for new UI states.
 * The original screenshots supply only aggregate weekly / lifetime data.
 * They cannot identify unique monthly returners or date-filtered KPI values.
 * Never ship these fixtures as production metrics. Replace this adapter with
 * real company-created, successful-integration, activation and activity events.
 */
const demoActivatedCompanies=[...cohortCatalog.values()].flat();
// Keep the lifetime fixture aligned with the supplied 512 companies / 326 users.
let demoOwner=0,demoCursor=0;
while(demoCursor<demoActivatedCompanies.length){
 const size=demoOwner<186?2:1;
 for(let j=0;j<size&&demoCursor<demoActivatedCompanies.length;j++,demoCursor++){
  const c=demoActivatedCompanies[demoCursor];
  c.ownerId='active-user-'+demoOwner;
  c.email=`accountant.${String(demoOwner+1).padStart(3,'0')}@ledgerdesk.example`;
  c.ttvDays=1+hashText(c.id+'ttv')%23;
 }
 demoOwner++;
}
let ttvAdjustment=5478-demoActivatedCompanies.reduce((n,c)=>n+c.ttvDays,0),adjustCursor=0;
while(ttvAdjustment!==0){
 const c=demoActivatedCompanies[adjustCursor++%demoActivatedCompanies.length];
 if(ttvAdjustment>0){c.ttvDays++;ttvAdjustment--;}
 else if(c.ttvDays>1){c.ttvDays--;ttvAdjustment++;}
}
demoActivatedCompanies.forEach((c,i)=>{
 c.integrated=addDays(c.activated,-c.ttvDays);
 c.signup=addDays(c.integrated,-(1+i%5));
 c.days=Math.round((Date.parse(c.activated)-Date.parse(c.signup))/86400000);
});
const demoInactiveCompanies=Array.from({length:2210},(_,i)=>{
 const brand=['Sage','Cedar','Orion','Aspen','Birch','Linden','Acorn','Sequoia'][i%8];
 return {id:'inactive-company-'+i,ownerId:'inactive-user-'+Math.floor(i/2),email:`finance.${String(Math.floor(i/2)+1).padStart(4,'0')}@accounting.example`,
  name:`${brand} Trading ${String(i+1).padStart(4,'0')}`,integration:'Tally',signup:addDays('2026-02-01',hashText('signup'+i)%246),
  activated:null,integrated:null,days:null,ttvDays:null,last:null};
});
const demoMonthlyCatalog=new Map();
for(const c of demoActivatedCompanies){
 const key=c.activated.slice(0,7)+'-01';
 if(!demoMonthlyCatalog.has(key))demoMonthlyCatalog.set(key,[]);
 c.monthlyReturns=[];c.monthlyDates=[];
 for(let period=1;period<=MONTH_WINDOW_COUNT;period++){
  const target=shiftMonth(key.slice(0,7),period);
  if(target>LAST_COMPLETE_MONTH){c.monthlyReturns.push(null);c.monthlyDates.push(null);continue;}
  const thresholds=[.64,.52,.45,.39,.33,.29];
  const active=hashText(c.id+'monthly-activity-'+target)%10000 < thresholds[period-1]*10000;
  c.monthlyReturns.push(active);
  c.monthlyDates.push(active?target+'-'+String(1+hashText(c.id+target+'day')%28).padStart(2,'0'):null);
 }
 c.monthlyLast=[c.activated,...c.monthlyDates.filter(Boolean)].sort().at(-1);
 demoMonthlyCatalog.get(key).push(c);
}
const monthlyCohorts=[...demoMonthlyCatalog.entries()].sort(([a],[b])=>a.localeCompare(b)).map(([date,companies])=>({
 date,n:companies.length,values:Array.from({length:MONTH_WINDOW_COUNT},(_,index)=>
  shiftMonth(date.slice(0,7),index+1)>LAST_COMPLETE_MONTH?null:companies.filter(c=>c.monthlyReturns[index]===true).length)
}));

function recordTabs(){return tableState.mode==='retention'?['retained','churned']:['activated','inactive'];}
function statusBadge(status){return `<span class="return-status is-${status}">${status==='retained'?'Retained':'Churned'}</span>`;}
function groupedRetentionUsers(companies,status){
 const groups=new Map();
 for(const company of companies){
  if(!groups.has(company.ownerId))groups.set(company.ownerId,{id:company.ownerId,email:company.email,companyRows:[],status});
  groups.get(company.ownerId).companyRows.push(company);
 }
 return [...groups.values()].map(user=>{
  const rows=user.companyRows;
  const signup=rows.map(c=>c.signup).sort()[0],activated=rows.map(c=>c.activated).filter(Boolean).sort()[0]||null;
  return {...user,companies:rows.map(c=>c.name),count:rows.length,signup,activated,
   days:activated?Math.round((Date.parse(activated)-Date.parse(signup))/86400000):null,
   last:rows.map(c=>c.last).filter(Boolean).sort().at(-1)||null};
 });
}
function resetRecordState(mode){
 Object.assign(tableState,{mode,tab:mode==='retention'?'retained':'activated',query:'',company:'all',month:'all',
  sort:mode==='retention'?'email':'activated',direction:mode==='retention'?'asc':'desc',page:1,expanded:new Set()});
 $('#user-search').value='';$('#company-filter').value='all';$('#month-filter').value='all';
 toggleFilter(false);
}
function configureRecordDialog(){
 const isRetention=tableState.mode==='retention';
 const dialog=$('#activation-dialog');
 dialog.classList.toggle('retention-records',isRetention);
 $('#records-eyebrow').textContent=isRetention?'Retention breakdown':'Activation rate';
 $('#records-close').setAttribute('aria-label',isRetention?'Close retention details':'Close activation details');
 $('#records-tabs').setAttribute('aria-label',isRetention?'Return status in the selected period':'Activation status');
 $('#company-filter-label').textContent=isRetention?'Companies per user in this tab':'Companies per user';
 $('#records-table').setAttribute('aria-label',isRetention?'Sample users and company retention details':'Sample users and activation details');
 $('#retention-status-note').hidden=!isRetention;
 if(isRetention){
  dialog.setAttribute('aria-describedby','retention-status-note');
  $('#retention-status-copy').textContent=`Churned means no qualifying return in ${retentionContext.period} ${retentionContext.week}${retentionContext.windowText?' ('+retentionContext.windowText+')':''}. These companies may return in a later ${retentionContext.period.toLowerCase()}.`;
 }else dialog.removeAttribute('aria-describedby');
 const tabs=recordTabs();
 const labels=isRetention?['Retained','Churned']:['Activated','Did not activate'];
 const counts=isRetention?[retentionContext.retained,retentionContext.churned]:[activationTotals.active,activationTotals.inactive];
 [$('#tab-activated'),$('#tab-inactive')].forEach((button,i)=>{
  button.dataset.tab=tabs[i];
  button.innerHTML=`${labels[i]}<span class="tab-count">${fmt.format(counts[i])}</span>`;
  button.title=isRetention?`${fmt.format(counts[i])} ${labels[i].toLowerCase()} companies in ${retentionContext.period} ${retentionContext.week}`:'';
 });
 const monthKeys=[...new Set(tabs.flatMap(tab=>records[tab].map(user=>user.signup.slice(0,7))))].sort().reverse();
 $('#month-filter').innerHTML='<option value="all">Any month</option>'+monthKeys.map(month=>`<option value="${month}">${monthName(month)}</option>`).join('');
 const columns=[['email','User'],['count','Companies'],['signup','Signed up'],['activated','First activated'],
  isRetention?['status',`${retentionContext.period} ${retentionContext.week} status`]:['days','Time to activate (days)'],['last','Last core activity']];
 $('#records-table thead').innerHTML=`<tr><th scope="col"><span class="sr-only">Expand companies</span></th>${columns.map(([key,label])=>`<th scope="col"${isRetention&&key==='last'?' title="Latest recorded activity, which may be later than the selected return window"':''}><button class="sort-button" data-sort="${key}">${esc(label)}${icon('sort')}</button></th>`).join('')}</tr>`;
 switchTab(tableState.tab);
 syncAllSelects();
}
function openActivationRecords(){
 retentionContext=null;
 resetRecordState('activation');configureRecordDialog();openDialog('activation-dialog');
}
function openRetentionRecords(cell){
 const week=Number(cell.dataset.week),cohortKey=cell.dataset.cohort;
 const monthly=cell.dataset.interval==='monthly',source=monthly?monthlyCohorts:cohorts,period=monthly?'Month':'Week';
 if(!Number.isInteger(week)||week<1||week>(monthly?MONTH_WINDOW_COUNT:8))return;
 const selectedCohorts=(cohortKey==='all'?visibleCohorts():source.filter(c=>c.date===cohortKey)).filter(c=>c.values[week-1]!==null);
 if(!selectedCohorts.length)return;
 const retained=selectedCohorts.reduce((sum,c)=>sum+c.values[week-1],0),total=selectedCohorts.reduce((sum,c)=>sum+c.n,0);
 retentionContext={cohortKey,week,period,view:monthly?'monthly':'weekly',total,retained,churned:total-retained,cohorts:selectedCohorts.map(c=>c.date),
  windowText:cohortKey==='all'?'':monthly?monthName(shiftMonth(cohortKey.slice(0,7),week)):dateLabel(addDays(cohortKey,week*7))+' to '+dateLabel(addDays(cohortKey,week*7+6))};
 const catalog=monthly?demoMonthlyCatalog:cohortCatalog;
 const allCompanies=selectedCohorts.flatMap(c=>catalog.get(c.date));
 const returns=c=>monthly?c.monthlyReturns:c.returns;
 const displayCompany=c=>monthly?{...c,last:c.monthlyLast}:c;
 records.retained=groupedRetentionUsers(allCompanies.filter(c=>returns(c)[week-1]===true).map(displayCompany),'retained');
 records.churned=groupedRetentionUsers(allCompanies.filter(c=>returns(c)[week-1]===false).map(displayCompany),'churned');
 resetRecordState('retention');configureRecordDialog();
 $$('.heat-cell.is-inspected').forEach(b=>b.classList.remove('is-inspected'));
 cell.classList.add('is-inspected');
 openDialog('activation-dialog');
}
function filteredUsers(){
 const query=tableState.query.toLowerCase().trim();
 const users=records[tableState.tab].filter(user=>{
  const text=(user.email+' '+user.companies.join(' ')).toLowerCase();
  return text.includes(query)&&(tableState.company==='all'||(tableState.company==='single'?user.count===1:user.count>1))
   &&(tableState.month==='all'||user.signup.startsWith(tableState.month));
 });
 return users.sort((a,b)=>{
  const av=a[tableState.sort],bv=b[tableState.sort];
  if(av==null&&bv==null)return a.email.localeCompare(b.email);
  if(av==null)return 1;if(bv==null)return -1;
  const diff=typeof av==='number'?av-bv:String(av).localeCompare(String(bv));
  return (tableState.direction==='asc'?diff:-diff)||a.email.localeCompare(b.email);
 });
}
function companyDetails(user){
 const isRetention=tableState.mode==='retention';
 const companyRows=user.companyRows||user.companies.map(name=>({name,integration:'Tally',signup:user.signup,activated:user.activated,days:user.days,last:user.last}));
 const label=`${user.count} ${isRetention?tableState.tab+' ':''}${user.count===1?'company':'companies'} for this user`;
 return `<tr class="company-detail-row" id="details-${user.id}"><td colspan="7"><div class="detail-label">${label}</div><table class="company-table" aria-label="Companies for ${esc(user.email)}"><thead><tr><th scope="col">Company</th><th scope="col">Integration</th><th scope="col">Signed up</th><th scope="col">Activated</th><th scope="col">${isRetention?`${retentionContext.period} ${retentionContext.week} status`:'Time to activate'}</th><th scope="col">Last core activity</th></tr></thead><tbody>${companyRows.map(company=>`<tr><td title="${esc(company.name)}">${company.id?`<button type="button" class="company-name-button" data-open-company="${esc(company.id)}" aria-haspopup="dialog" aria-controls="company-dialog" aria-label="View ${esc(company.name)} activity">${esc(company.name)}</button>`:esc(company.name)}</td><td><span class="integration-tag">${esc(company.integration)}</span></td><td>${dateLabel(company.signup)}</td><td>${dateLabel(company.activated)}</td><td>${isRetention?statusBadge(tableState.tab):company.days===null?'-':company.days+' '+(company.days===1?'day':'days')}</td><td>${dateLabel(company.last)}</td></tr>`).join('')}</tbody></table></td></tr>`;
}
function paginationMarkup(pages){
 const current=tableState.page;
 const candidates=pages<=7?Array.from({length:pages},(_,i)=>i+1):[1,pages,current-1,current,current+1,...(current<=3?[2,3,4]:[]),...(current>=pages-2?[pages-3,pages-2,pages-1]:[])];
 const numbers=[...new Set(candidates.filter(number=>number>=1&&number<=pages))].sort((a,b)=>a-b);
 let previous=0;
 const links=numbers.map(number=>{
  const gap=previous&&number-previous>1?'<span class="page-ellipsis" aria-hidden="true">…</span>':'';
  previous=number;
  return gap+`<button class="page-button ${number===current?'current':''}" data-page="${number}" ${number===current?'aria-current="page"':''} aria-label="Page ${number}">${number}</button>`;
 }).join('');
 return `<button class="page-button" data-page="${current-1}" ${current===1?'disabled':''} aria-label="Previous page">${icon('left')}</button>${links}<button class="page-button" data-page="${current+1}" ${current===pages?'disabled':''} aria-label="Next page">${icon('right')}</button>`;
}
function emptyRecordMarkup(){
 if(tableState.mode==='retention'&&records[tableState.tab].length===0){
  const retainedTab=tableState.tab==='retained';
  const title=retainedTab?'No companies retained in this period':'No companies churned in this period';
  const description=retainedTab?`No companies in this selection had a qualifying return in ${retentionContext.period} ${retentionContext.week}.`:`Every company in this selection returned in ${retentionContext.period} ${retentionContext.week}.`;
  return `<tr><td colspan="7" class="empty-state"><strong>${title}</strong><p>${description}</p><button class="text-button" data-empty-tab="${retainedTab?'churned':'retained'}">View ${retainedTab?'churned':'retained'} companies</button></td></tr>`;
 }
 return '<tr><td colspan="7" class="empty-state"><strong>No matching users</strong><p>Try a different search or clear your filters.</p><button class="text-button" id="empty-reset">Clear search and filters</button></td></tr>';
}
function renderUsers(){
 const isRetention=tableState.mode==='retention';
 const users=filteredUsers(),pages=Math.max(1,Math.ceil(users.length/tableState.pageSize));
 tableState.page=Math.min(Math.max(1,tableState.page),pages);
 const start=(tableState.page-1)*tableState.pageSize,end=Math.min(start+tableState.pageSize,users.length),current=users.slice(start,end);
 $('#activation-table-body').innerHTML=current.length?current.map(user=>`<tr class="user-row ${tableState.expanded.has(user.id)?'expanded':''}"><td><button class="expand-user" data-user="${user.id}" aria-expanded="${tableState.expanded.has(user.id)}" aria-label="${tableState.expanded.has(user.id)?'Hide':'Show'} companies for ${esc(user.email)}" ${tableState.expanded.has(user.id)?`aria-controls="details-${user.id}"`:''}>${icon(tableState.expanded.has(user.id)?'minus':'plus')}</button></td><td title="${esc(user.email)}">${esc(user.email)}</td><td><span class="company-count">${user.count}</span></td><td>${dateLabel(user.signup)}</td><td>${dateLabel(user.activated)}</td><td>${isRetention?statusBadge(tableState.tab):user.days===null?'-':user.days}</td><td>${dateLabel(user.last)}</td></tr>${tableState.expanded.has(user.id)?companyDetails(user):''}`).join(''):emptyRecordMarkup();
 const userLabel=users.length?`${start+1} to ${end} of ${fmt.format(users.length)} ${isRetention?'users':'sample users'}`:`0 ${isRetention?'users':'sample users'}`;
 const companyCount=users.reduce((sum,user)=>sum+user.count,0);
 $('#pagination-label').textContent=userLabel+(isRetention?` · ${fmt.format(companyCount)} ${tableState.tab} ${companyCount===1?'company':'companies'}`:'');
 $('#pagination-controls').innerHTML=paginationMarkup(pages);
 $$('.sort-button',$('#records-table')).forEach(button=>{
  const isSorted=button.dataset.sort===tableState.sort;
  button.classList.toggle('sorted',isSorted);
  button.closest('th').setAttribute('aria-sort',isSorted?(tableState.direction==='asc'?'ascending':'descending'):'none');
  $('use',button).setAttribute('href',`#i-${isSorted?(tableState.direction==='asc'?'up':'down'):'sort'}`);
 });
 $('#clear-search').hidden=!tableState.query;
 const chips=[];
 if(tableState.company!=='all')chips.push(`<button class="filter-chip" data-remove-filter="company">${tableState.company==='single'?'1 company':'2+ companies'}${icon('close')}</button>`);
 if(tableState.month!=='all')chips.push(`<button class="filter-chip" data-remove-filter="month">Signed up: ${esc(monthName(tableState.month))}${icon('close')}</button>`);
 $('#active-filters').innerHTML=chips.join('');$('#active-filters').hidden=!chips.length;
 $('#filter-count').textContent='· '+chips.length;$('#filter-button').classList.toggle('has-filters',chips.length>0);syncAllSelects();
}
function switchTab(tab){
 if(!recordTabs().includes(tab))return;
 tableState.tab=tab;tableState.page=1;tableState.expanded.clear();
 tableState.sort=tableState.mode==='retention'?'email':tab==='activated'?'activated':'signup';
 tableState.direction=tableState.mode==='retention'?'asc':'desc';
 $$('.tab-button').forEach(button=>{const selected=button.dataset.tab===tab;button.setAttribute('aria-selected',String(selected));button.tabIndex=selected?0:-1;});
 const activeTab=$(`.tab-button[data-tab="${tab}"]`);
 $('#activation-records').setAttribute('aria-labelledby',activeTab.id);
 if(tableState.mode==='retention'){
  const context=retentionContext,percentage=(context.retained/context.total*100).toFixed(1);
  const all=context.cohortKey==='all';
  $('#activation-dialog-title').textContent=(all?'All eligible cohorts':retentionCohortLabel(context.cohortKey,context.view)+' cohort')+' · '+context.period+' '+context.week;
  $('#activation-meta').textContent=(all?context.cohorts.length+' cohorts · ':'')+fmt.format(context.total)+' companies · '+percentage+'% retained · '+(context.churned/context.total*100).toFixed(1)+'% churned · '+rangeLabel(appliedRange);
 }else{
  const count=tab==='activated'?activationTotals.active:activationTotals.inactive;
  $('#activation-meta').textContent=fmt.format(records[tab].length)+' users · '+fmt.format(count)+' companies · '+rangeLabel(appliedRange);
  $('#activation-dialog-title').textContent=fmt.format(count)+' of '+fmt.format(activationTotals.total)+' companies';
 }
 $('#activation-records').scrollTop=0;
 $('#activation-records').scrollLeft=0;
 renderUsers();
}
function resetFilters(clearSearch=false){
 tableState.company='all';tableState.month='all';tableState.page=1;
 $('#company-filter').value='all';$('#month-filter').value='all';
 if(clearSearch){tableState.query='';$('#user-search').value='';}
 renderUsers();
}
function toggleFilter(open){if(!open&&activeSelect?.trigger.closest('.filter-anchor'))closeSelectMenu();$('#filter-popover').hidden=!open;$('#filter-button').setAttribute('aria-expanded',String(open));}

function openDialog(id){closeDatePicker(false);closeSelectMenu();hideTooltip();hideChurnTooltip();toggleDashboardMenu(false);const d=$('#'+id);if(!d.open){d.showModal();document.body.classList.add('modal-open')}}
function closeDialog(id){const d=$('#'+id);if(d.open)d.close();}
function openInfo(key='all'){const titles={all:'Metric definitions',ttv:'Time to value',churn:'Monthly churn',retention:'Reading the heatmap'};$('#info-title').textContent=titles[key]||'Metric definition';const current=currentDefinitions();$('#info-body').innerHTML=key==='all'?Object.values(current).join(''):current[key];openDialog('info-dialog');}
function expandReport(id){
 if(movedReport){closeDialog('report-dialog');return;}
 const card=$('#'+id);if(!card)return;
 reportPlaceholder=document.createElement('div');reportPlaceholder.className='report-placeholder';reportPlaceholder.style.height=card.offsetHeight+'px';reportPlaceholder.textContent='Report open in expanded view';card.before(reportPlaceholder);movedReport=card;$('#report-mount').append(card);
 $('#expanded-label').textContent=id==='retention-report'?`${retentionView==='monthly'?'Monthly':'Weekly'} retention · Expanded view`:'Monthly churn · Expanded view';
 const button=$('[data-expand]',card);button.setAttribute('aria-label','Close expanded report');button.title='Close expanded report';
 openDialog('report-dialog');
 requestAnimationFrame(renderChurnChart);
}
function restoreReport(){if(movedReport&&reportPlaceholder){const button=$('[data-expand]',movedReport);const label=movedReport.id==='retention-report'?'Expand retention report':'Expand churn report';button.setAttribute('aria-label',label);button.title=label;reportPlaceholder.replaceWith(movedReport);movedReport=null;reportPlaceholder=null;requestAnimationFrame(renderChurnChart);}}
function csvDownload(type){
 let rows;
 const source=type==='retention'&&retentionView==='monthly'?'Illustrative company-level monthly activity':'Supplied dashboard snapshot';
 const meta=[['Global date range',rangeLabel(appliedRange)],['Data source',source],['As of',SNAPSHOT_DATE],[]];
 if(type==='retention'){
  const period=retentionView==='monthly'?'Month':'Week',length=retentionView==='monthly'?MONTH_WINDOW_COUNT:8;
  rows=[['Cohort '+period.toLowerCase(),'Cohort size',...Array.from({length},(_,i)=>period+' '+(i+1)+' retained')],...visibleCohorts().map(c=>[c.date,c.n,...c.values.map(v=>v===null?'Not yet eligible':v)])];
 }else rows=[['Month','Churn rate (%)','Change (pp)','Churned','Eligible','Entered churn','Reactivated'],...visibleChurnMonths().map(m=>[m.month+' 2026',m.rate,m.delta??'',m.churned,m.eligible,m.entered,m.reactivated])];
 const content=[...meta,...rows].map(row=>row.map(v=>`"${String(v).replace(/"/g,'""')}"`).join(',')).join('\r\n');
 const blob=new Blob(['\ufeff'+content],{type:'text/csv;charset=utf-8;'}),url=URL.createObjectURL(blob),a=document.createElement('a');
 a.href=url;a.download=`aia-${type}${type==='retention'?'-'+retentionView:''}-${appliedRange.preset==='lifetime'?'lifetime':appliedRange.start+'-to-'+appliedRange.end}.csv`;
 document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);toast('CSV downloaded for the selected date range');
}
let toastTimer;
function toast(message){const el=$('#toast');el.innerHTML=icon('check')+esc(message);el.hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>el.hidden=true,3000);}
function showTooltip(target){
 const data=target.dataset.tip?.split('|');if(!data)return;
 const tip=$('#heatmap-tooltip');(target.closest('dialog')||document.body).append(tip);tip.innerHTML=`<strong>${esc(data[0])} · ${esc(data[1])}</strong><div>${esc(data[3])}</div><div class="muted">${esc(data[2])}</div><div class="tip-action">Click to view users and companies</div>`;tip.hidden=false;
 const box=target.getBoundingClientRect(),rect=tip.getBoundingClientRect();let top=box.top-rect.height-8;if(top<12)top=box.bottom+8;const left=Math.max(12,Math.min(box.left+box.width/2-rect.width/2,window.innerWidth-rect.width-12));tip.style.left=left+'px';tip.style.top=top+'px';
}
function hideTooltip(){const tip=$('#heatmap-tooltip');tip.hidden=true;if(tip.parentElement!==document.body)document.body.append(tip);}

$('#retention-view').addEventListener('change',event=>{retentionView=event.target.value;renderHeatmap();syncAllSelects();});
$('#cohort-order').addEventListener('change',event=>{reverseCohorts=event.target.value==='newest';renderHeatmap();});
$('#activation-card').addEventListener('click',()=>openInfo('activation'));
$('#ttv-card').addEventListener('click',()=>openDialog('ttv-dialog'));
$('#churn-metric-card').addEventListener('click',()=>openDialog('churn-dialog'));

$('#churn-definition').addEventListener('click',()=>openInfo('churn'));
$('#help-button').addEventListener('click',()=>openInfo());

$('#dashboard-trigger').addEventListener('click',()=>toggleDashboardMenu($('#dashboard-menu').hidden));
$('#retention-menu-item').addEventListener('click',()=>{toggleDashboardMenu(false);$('#dashboard-trigger').focus();});

$('#user-search').addEventListener('input',event=>{tableState.query=event.target.value;tableState.page=1;renderUsers();});
$('#clear-search').addEventListener('click',()=>{tableState.query='';$('#user-search').value='';tableState.page=1;renderUsers();$('#user-search').focus();});
$('#filter-button').addEventListener('click',()=>toggleFilter($('#filter-popover').hidden));
$('#reset-filters').addEventListener('click',()=>resetFilters());
$('#company-filter').addEventListener('change',event=>{tableState.company=event.target.value;tableState.page=1;renderUsers();});
$('#month-filter').addEventListener('change',event=>{tableState.month=event.target.value;tableState.page=1;renderUsers();});
$$('dialog').forEach(dialog=>{
 dialog.addEventListener('click',event=>{if(event.target===dialog){const r=dialog.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)dialog.close();}});
 dialog.addEventListener('close',()=>{closeSelectMenu();hideChurnTooltip();if(dialog.id==='report-dialog')restoreReport();if(dialog.id==='activation-dialog'){toggleFilter(false);$$('.heat-cell.is-inspected').forEach(cell=>cell.classList.remove('is-inspected'));}if(!$$('dialog[open]').length)document.body.classList.remove('modal-open');hideTooltip();});
 dialog.addEventListener('cancel',event=>{if(dialog.id==='activation-dialog'&&!$('#filter-popover').hidden){event.preventDefault();toggleFilter(false);$('#filter-button').focus();}});
});
document.addEventListener('click',event=>{
 if(event.target.closest('.ui-select-menu'))return;
 if(!event.target.closest('.dashboard-switcher'))toggleDashboardMenu(false);
 const button=event.target.closest('button');
 if(button?.dataset.cohort){openRetentionRecords(button);return;}
 if(button?.dataset.emptyTab){switchTab(button.dataset.emptyTab);$(`[data-tab="${button.dataset.emptyTab}"]`).focus();return;}
 if(button?.dataset.churnView){setChurnView(button.dataset.churnView);return;}
 if(button?.dataset.close){closeDialog(button.dataset.close);return;}
 if(button?.dataset.expand){expandReport(button.dataset.expand);return;}
 if(button?.dataset.export){csvDownload(button.dataset.export);return;}
 if(button?.dataset.tab){switchTab(button.dataset.tab);return;}
 if(button?.dataset.sort){const key=button.dataset.sort;if(tableState.sort===key)tableState.direction=tableState.direction==='asc'?'desc':'asc';else{tableState.sort=key;tableState.direction='asc'}tableState.page=1;renderUsers();const next=$(`[data-sort="${key}"]`);next?.focus({preventScroll:true});return;}
 if(button?.dataset.user){const id=button.dataset.user;tableState.expanded.has(id)?tableState.expanded.delete(id):tableState.expanded.add(id);renderUsers();$(`[data-user="${id}"]`)?.focus({preventScroll:true});return;}
 if(button?.dataset.page&&!button.disabled){tableState.page=Number(button.dataset.page);renderUsers();$('#activation-records').scrollTop=0;return;}
 if(button?.dataset.removeFilter){const key=button.dataset.removeFilter;tableState[key]='all';$('#'+(key==='company'?'company':'month')+'-filter').value='all';tableState.page=1;renderUsers();return;}
 if(button?.id==='empty-reset'){resetFilters(true);return;}
 if(!event.target.closest('.filter-anchor'))toggleFilter(false);
});

document.addEventListener('keydown',event=>{
 if(event.target.matches('.view-tab')&&['ArrowLeft','ArrowRight','Home','End'].includes(event.key)){
   event.preventDefault();const view=event.key==='Home'?'trend':event.key==='End'?'table':churnView==='trend'?'table':'trend';setChurnView(view);$(`[data-churn-view="${view}"]`).focus();
 }
 if(event.target.id==='dashboard-trigger'&&['ArrowDown','ArrowUp'].includes(event.key)){event.preventDefault();toggleDashboardMenu(true,true);}
 if(event.target.closest('#dashboard-menu')&&['ArrowDown','ArrowUp','Home','End'].includes(event.key)){event.preventDefault();$('#retention-menu-item').focus();}
 if(event.key==='Escape'){
   hideChurnTooltip();
   if(!$('#dashboard-menu').hidden){event.preventDefault();toggleDashboardMenu(false);$('#dashboard-trigger').focus();}
 }

 if(event.target.matches('.tab-button')&&['ArrowLeft','ArrowRight','Home','End'].includes(event.key)){event.preventDefault();const tabs=recordTabs(),tab=event.key==='Home'?tabs[0]:event.key==='End'?tabs[1]:tableState.tab===tabs[0]?tabs[1]:tabs[0];switchTab(tab);$(`[data-tab="${tab}"]`).focus();}
 if(event.key==='Escape')hideTooltip();
});
document.addEventListener('pointerover',event=>{const target=event.target.closest('[data-tip]');if(target)showTooltip(target)});
document.addEventListener('pointerout',event=>{if(event.target.closest('[data-tip]'))hideTooltip()});
document.addEventListener('focusin',event=>{if(event.target.matches('[data-tip]'))showTooltip(event.target)});
document.addEventListener('focusout',event=>{if(event.target.matches('[data-tip]'))hideTooltip()});
document.addEventListener('scroll',hideTooltip,true);window.addEventListener('resize',hideTooltip);

document.addEventListener('pointerover',event=>{const p=event.target.closest('[data-churn-point]');if(p)showChurnTooltip(p);});
document.addEventListener('pointerout',event=>{if(event.target.closest('[data-churn-point]')&&!event.relatedTarget?.closest?.('[data-churn-point]'))hideChurnTooltip();});
document.addEventListener('focusin',event=>{if(event.target.matches('[data-churn-point]'))showChurnTooltip(event.target);if(!event.target.closest('.dashboard-switcher'))toggleDashboardMenu(false);});
document.addEventListener('focusout',event=>{if(event.target.matches('[data-churn-point]'))hideChurnTooltip();});
document.addEventListener('scroll',hideChurnTooltip,true);
window.addEventListener('resize',hideChurnTooltip);
let chartResizeFrame;
if('ResizeObserver' in window){
 const chartObserver=new ResizeObserver(()=>{cancelAnimationFrame(chartResizeFrame);chartResizeFrame=requestAnimationFrame(renderChurnChart);});
 chartObserver.observe($('#churn-chart').parentElement);
}else{window.addEventListener('resize',()=>requestAnimationFrame(renderChurnChart));}
/* Shared, keyboard-operable listbox component. Native selects remain hidden
 * state holders so existing filtering logic needs no UI-specific branching. */
const uiSelects=new Map();
let activeSelect=null;
function placeSurface(panel,anchor,preferredWidth){
 const maxWidth=Math.max(200,innerWidth-24);
 panel.style.width=Math.min(preferredWidth,maxWidth)+'px';
 panel.style.maxHeight=Math.max(160,innerHeight-24)+'px';
 const r=anchor.getBoundingClientRect(),height=panel.getBoundingClientRect().height;
 let left=r.right-panel.getBoundingClientRect().width;
 let top=r.bottom+8;
 if(top+height>innerHeight-12)top=r.top-height-8;
 if(top<12)top=12;
 panel.style.left=Math.max(12,Math.min(left,innerWidth-panel.getBoundingClientRect().width-12))+'px';
 panel.style.top=Math.max(12,Math.min(top,innerHeight-height-12))+'px';
}
class UISelect{
 constructor(select){
  this.select=select;this.label=select.getAttribute('aria-label')||document.querySelector(`label[for="${select.id}"]`)?.textContent||'Select an option';
  this.host=document.createElement('span');this.host.className='ui-select-host';
  this.trigger=document.createElement('button');this.trigger.type='button';this.trigger.className='ui-control ui-select-trigger';
  this.trigger.id=select.id+'-trigger';this.trigger.dataset.size=select.dataset.size||'filter';
  this.trigger.setAttribute('role','combobox');this.trigger.setAttribute('aria-haspopup','listbox');
  this.trigger.setAttribute('aria-expanded','false');this.trigger.setAttribute('aria-controls',select.id+'-listbox');
  this.host.append(this.trigger);select.after(this.host);
  select.hidden=true;select.tabIndex=-1;select.setAttribute('aria-hidden','true');
  const label=document.querySelector(`label[for="${select.id}"]`);if(label)label.htmlFor=this.trigger.id;
  this.panel=document.createElement('div');this.panel.id=select.id+'-listbox';this.panel.className='ui-select-menu ui-menu-surface';
  this.panel.setAttribute('role','listbox');this.panel.setAttribute('aria-label',this.label);this.panel.hidden=true;document.body.append(this.panel);
  this.trigger.addEventListener('click',()=>activeSelect===this?this.close():this.open());
  this.trigger.addEventListener('keydown',e=>{
   if(['ArrowDown','ArrowUp','Home','End'].includes(e.key)){e.preventDefault();this.open(e.key==='End'?'last':e.key==='Home'?'first':'selected');}
  });
  this.panel.addEventListener('click',e=>{
   e.stopPropagation();const option=e.target.closest('[data-select-value]');
   if(option&&!option.disabled){this.select.value=option.dataset.selectValue;this.close(true);this.select.dispatchEvent(new Event('change',{bubbles:true}));this.sync();}
  });
  this.panel.addEventListener('keydown',e=>this.keydown(e));
  select.addEventListener('change',()=>this.sync());
  this.sync();
 }
 sync(){
  const option=this.select.selectedOptions[0];
  this.trigger.innerHTML=(this.select.dataset.leading?icon(this.select.dataset.leading):'')+`<span class="ui-select-value">${esc(option?.textContent||'Select')}</span><svg class="icon chevron" aria-hidden="true"><use href="#i-down"/></svg>`;
  this.trigger.setAttribute('aria-label',this.label+': '+(option?.textContent||'Select'));this.trigger.disabled=this.select.disabled;
 }
 open(target='selected'){
  closeSelectMenu();closeDatePicker(false);toggleDashboardMenu(false);
  this.panel.innerHTML=[...this.select.options].map((o,i)=>`<button type="button" class="ui-select-option" role="option" aria-selected="${o.selected}" data-select-value="${esc(o.value)}" tabindex="-1" ${o.disabled?'disabled':''}><span><strong>${esc(o.textContent)}</strong>${o.dataset.description?`<small>${esc(o.dataset.description)}</small>`:''}</span>${icon('check')}</button>`).join('');
  (this.trigger.closest('dialog')||document.body).append(this.panel);this.panel.hidden=false;
  this.trigger.setAttribute('aria-expanded','true');activeSelect=this;
  this.position();
  const options=$$('.ui-select-option:not(:disabled)',this.panel);
  const focus=target==='first'?options[0]:target==='last'?options.at(-1):$('.ui-select-option[aria-selected="true"]',this.panel)||options[0];
  focus?.focus({preventScroll:true});focus?.scrollIntoView({block:'nearest'});
 }
 position(){placeSurface(this.panel,this.trigger,this.select.id==='retention-view'?266:Math.max(186,this.trigger.getBoundingClientRect().width));this.panel.style.maxHeight=Math.min(310,innerHeight-24)+'px';}
 close(focus=false){this.panel.hidden=true;this.trigger.setAttribute('aria-expanded','false');if(activeSelect===this)activeSelect=null;if(focus)this.trigger.focus({preventScroll:true});}
 keydown(e){
  const options=$$('.ui-select-option:not(:disabled)',this.panel),current=Math.max(0,options.indexOf(document.activeElement));
  let next=null;
  if(e.key==='ArrowDown')next=(current+1)%options.length;
  if(e.key==='ArrowUp')next=(current+options.length-1)%options.length;
  if(e.key==='Home')next=0;if(e.key==='End')next=options.length-1;
  if(next!==null){e.preventDefault();e.stopPropagation();options[next]?.focus();return;}
  if(e.key==='Tab'){this.close(true);return;}
  if(e.key.length===1&&!e.ctrlKey&&!e.metaKey&&e.key!==' '){
   const now=Date.now();this.search=(now-(this.searchAt||0)<650?this.search||'':'')+e.key.toLowerCase();this.searchAt=now;
   options.find(o=>o.textContent.trim().toLowerCase().startsWith(this.search))?.focus();
  }
 }
}
function closeSelectMenu(focus=false){activeSelect?.close(focus);}
function syncAllSelects(){for(const select of uiSelects.values())select.sync();}
function initSelects(){
 $$('select[data-ui-select]').forEach(select=>uiSelects.set(select.id,new UISelect(select)));
 document.addEventListener('pointerdown',e=>{if(activeSelect&&!activeSelect.panel.contains(e.target)&&!activeSelect.trigger.contains(e.target))closeSelectMenu();},true);
 document.addEventListener('keydown',e=>{
  if(e.key==='Escape'&&activeSelect){e.preventDefault();e.stopImmediatePropagation();closeSelectMenu(true);}
 },true);
 window.addEventListener('resize',()=>{if(activeSelect)activeSelect.position();});
 document.addEventListener('scroll',e=>{if(activeSelect&&!activeSelect.panel.contains(e.target))closeSelectMenu();},true);
}

let draftRange=null,pickerYear=2026,awaitingEnd=false,pickerEdit=null;
function datePickerOpen(){return !$('#date-range-popover').hidden;}
function openDatePicker(){
 closeSelectMenu();toggleDashboardMenu(false);hideTooltip();hideChurnTooltip();
 draftRange={...appliedRange};awaitingEnd=false;pickerEdit=null;
 pickerYear=Number((appliedRange.end||CURRENT_MONTH).slice(0,4));
 $('#date-range-popover').hidden=false;$('#date-range-trigger').setAttribute('aria-expanded','true');
 renderDatePicker();
 $(`[data-preset="${draftRange.preset}"]`)?.focus({preventScroll:true});
}
function closeDatePicker(focus=true){
 const panel=$('#date-range-popover');if(!panel||panel.hidden)return;
 panel.hidden=true;$('#date-range-trigger').setAttribute('aria-expanded','false');draftRange=null;awaitingEnd=false;pickerEdit=null;
 if(focus)$('#date-range-trigger').focus({preventScroll:true});
}
function positionDatePicker(){if(datePickerOpen())placeSurface($('#date-range-popover'),$('#date-range-trigger'),innerWidth<=620?414:586);}
function renderDatePicker(focusMonth=null){
 if(!draftRange)return;
 const range=draftRange;
 $$('[data-preset]').forEach(b=>b.setAttribute('aria-pressed',String(range.preset===b.dataset.preset)));
 for(const size of ['3','6','12'])$('#preset-'+size+'-desc').textContent=rangeLabel(presetRange(size));
 $('#start-month-label').textContent=range.preset==='lifetime'?'All time':range.start?shortMonth(range.start):'Choose month';
 $('#end-month-label').textContent=range.preset==='lifetime'?'Present':range.end?shortMonth(range.end):'Choose month';
 $('#start-month-field').classList.toggle('is-picking',pickerEdit==='start'||range.preset==='custom'&&!range.start);
 $('#end-month-field').classList.toggle('is-picking',awaitingEnd||pickerEdit==='end');
 $('#picker-year').textContent=pickerYear;
 $('#previous-year').disabled=pickerYear<=2026;$('#next-year').disabled=pickerYear>=currentYear;
 const names=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
 $('#month-grid').innerHTML=names.map((name,i)=>{
  const key=pickerYear+'-'+String(i+1).padStart(2,'0'),future=key>CURRENT_MONTH,current=key===CURRENT_MONTH;
  const selected=range.preset!=='lifetime'&&range.start&&range.end&&key>=range.start&&key<=range.end;
  const endpoint=selected&&(key===range.start||key===range.end);
  return `<button type="button" class="month-button ${selected?'in-range':''} ${endpoint?'is-endpoint':''} ${current?'is-current':''}" data-month="${key}" aria-label="${monthName(key)}${current?', current month, in progress':''}" aria-pressed="${Boolean(selected)}" ${future?'disabled':''} title="${monthName(key)}${current?' (in progress)':''}">${name}</button>`;
 }).join('');
 $('#date-picker-instructions').textContent=awaitingEnd?'Choose an end month, or Apply to use just this month.':range.preset==='custom'?'Choose a month. Choose another to extend the range.':'Choose a preset or select months for a custom range.';
 const partial=range.preset!=='lifetime'&&range.end===CURRENT_MONTH;
 $('#draft-range-summary').innerHTML=range.preset==='lifetime'?'All available data':range.start&&range.end?
  `${dateLabel(monthFirst(range.start))} ${range.start.slice(0,4)} – ${dateLabel(partial?SNAPSHOT_DATE:monthLast(range.end))} ${range.end.slice(0,4)}${partial?'<span class="partial-period">Current month is partial</span>':''}`:'Select your date range';
 $('#apply-date-range').disabled=range.preset!=='lifetime'&&!(range.start&&range.end);
 positionDatePicker();
 if(focusMonth)$(`[data-month="${focusMonth}"]`)?.focus({preventScroll:true});
}
function choosePreset(value){
 if(value==='custom'){
  draftRange={preset:'custom',start:draftRange.start,end:draftRange.end};awaitingEnd=false;pickerEdit=draftRange.start?null:'start';
 }else{draftRange=presetRange(value);awaitingEnd=false;pickerEdit=null;pickerYear=Number((draftRange.end||CURRENT_MONTH).slice(0,4));}
 renderDatePicker();
}
function chooseMonth(key){
 if(key>CURRENT_MONTH)return;
 if(pickerEdit==='start'){
  const end=draftRange.end&&draftRange.end>=key?draftRange.end:key;
  draftRange={preset:'custom',start:key,end};pickerEdit=null;awaitingEnd=true;
 }else if(pickerEdit==='end'||awaitingEnd){
  const start=draftRange.start||key;
  draftRange={preset:'custom',start:start<key?start:key,end:start<key?key:start};awaitingEnd=false;pickerEdit=null;
 }else{draftRange={preset:'custom',start:key,end:key};awaitingEnd=true;pickerEdit=null;}
 renderDatePicker(key);
}
function overviewReportingUrl(range){
 if(range.preset==='lifetime')return '/overview';
 const q=new URLSearchParams({from:range.start,to:range.end,preset:range.preset||'custom'});
 return '/overview?'+q.toString();
}
function applyDateRange(){
 if(!draftRange||draftRange.preset!=='lifetime'&&!(draftRange.start&&draftRange.end))return;
 if(window.location.pathname==='/overview'){
   window.location.assign(overviewReportingUrl(draftRange));
   return;
 }
 appliedRange={...draftRange};closeDatePicker();renderDashboard();
 $('#range-live-status').textContent='Date range changed to '+rangeLabel(appliedRange)+'.';
}
function resetDateRange(){
 if(window.location.pathname==='/overview'){
   window.location.assign('/overview');return;
 }
 appliedRange=presetRange('lifetime');closeDatePicker(false);renderDashboard();
 $('#range-live-status').textContent='Date range reset to Lifetime.';
}
function initDatePicker(){
 $('#date-range-trigger').addEventListener('click',()=>datePickerOpen()?closeDatePicker():openDatePicker());
 $('#date-range-trigger').addEventListener('keydown',e=>{if(['ArrowDown','ArrowUp'].includes(e.key)){e.preventDefault();openDatePicker();}});
 $('#close-date-picker').addEventListener('click',()=>closeDatePicker());
 $('#cancel-date-range').addEventListener('click',()=>closeDatePicker());
 $('#apply-date-range').addEventListener('click',applyDateRange);
 $('#reset-range').addEventListener('click',resetDateRange);
 $('#previous-year').addEventListener('click',()=>{if(pickerYear>2020){pickerYear--;renderDatePicker();}});
 $('#next-year').addEventListener('click',()=>{if(pickerYear<2026){pickerYear++;renderDatePicker();}});
 $('#start-month-field').addEventListener('click',()=>{draftRange.preset='custom';pickerEdit='start';awaitingEnd=false;renderDatePicker();$('#month-grid button:not(:disabled)')?.focus();});
 $('#end-month-field').addEventListener('click',()=>{draftRange.preset='custom';pickerEdit='end';awaitingEnd=true;renderDatePicker();$('#month-grid button:not(:disabled)')?.focus();});
 $('#date-range-popover').addEventListener('click',e=>{
  const preset=e.target.closest('[data-preset]'),month=e.target.closest('[data-month]');
  if(preset)choosePreset(preset.dataset.preset);if(month&&!month.disabled)chooseMonth(month.dataset.month);
 });
 $('#month-grid').addEventListener('keydown',e=>{
  const current=e.target.closest('[data-month]');if(!current)return;
  let target=null;
  if(e.key==='ArrowLeft')target=shiftMonth(current.dataset.month,-1);
  if(e.key==='ArrowRight')target=shiftMonth(current.dataset.month,1);
  if(e.key==='ArrowUp')target=shiftMonth(current.dataset.month,-3);
  if(e.key==='ArrowDown')target=shiftMonth(current.dataset.month,3);
  if(e.key==='Home')target=pickerYear+'-01';
  if(e.key==='End')target=pickerYear===2026?CURRENT_MONTH:pickerYear+'-12';
  if(target){e.preventDefault();if(target<='2026-10'&&target>='2020-01'){pickerYear=Number(target.slice(0,4));renderDatePicker(target);}}
 });
 document.addEventListener('pointerdown',e=>{
  if(datePickerOpen()&&!e.target.closest('#date-range-popover')&&!e.target.closest('#date-range-trigger'))closeDatePicker(false);
 },true);
 document.addEventListener('keydown',e=>{
  if(!datePickerOpen())return;
  if(e.key==='Escape'){e.preventDefault();e.stopImmediatePropagation();closeDatePicker();return;}
  if(e.key==='Tab'){
   const focusable=$$('button:not(:disabled)', $('#date-range-popover')).filter(el=>el.getClientRects().length);
   if(e.shiftKey&&document.activeElement===focusable[0]){e.preventDefault();focusable.at(-1)?.focus();}
   else if(!e.shiftKey&&document.activeElement===focusable.at(-1)){e.preventDefault();focusable[0]?.focus();}
  }
 },true);
 document.addEventListener('click',e=>{if(e.target.closest('[data-reset-range]'))resetDateRange();});
 document.addEventListener('scroll',e=>{if(datePickerOpen()&&!$('#date-range-popover').contains(e.target))positionDatePicker();},true);
 window.addEventListener('resize',positionDatePicker);
}

function prepareActivationData(){
 const active=demoActivatedCompanies.filter(c=>dateInRange(c.signup));
 const inactive=demoInactiveCompanies.filter(c=>dateInRange(c.signup));
 const ttvCompanies=demoActivatedCompanies.filter(c=>dateInRange(c.integrated));
 activationTotals={active:active.length,inactive:inactive.length,total:active.length+inactive.length,
  ttv:ttvCompanies.length?ttvCompanies.reduce((sum,c)=>sum+c.ttvDays,0)/ttvCompanies.length:null,ttvN:ttvCompanies.length};
 records.activated=groupedRetentionUsers(active,'activated');
 records.inactive=groupedRetentionUsers(inactive,'inactive');
}
function updateActivationMetrics(){
 const scope=rangeLabel(appliedRange),filtered=appliedRange.preset!=='lifetime';
 const rate=activationTotals.total?(100*activationTotals.active/activationTotals.total).toFixed(1)+'%':'-';
 const ttv=activationTotals.ttv===null?null:activationTotals.ttv.toFixed(1);
 const sample=filtered?'<span class="metric-sample" title="Illustrative company-level data for this prototype">Sample data</span>':'';
 $('#activation-card .metric-period').textContent=scope;
 $('#activation-card .metric-value').innerHTML=rate+sample;
 $('#activation-card .metric-note').textContent=activationTotals.total?`${fmt.format(activationTotals.active)} of ${fmt.format(activationTotals.total)} companies activated`:'No companies signed up in this range';
 $('#activation-card').setAttribute('aria-label',`Activation rate, ${rate}, ${scope}${filtered?', sample data':''}. View users and companies.`);
 $('#ttv-card .metric-period').textContent=scope;
 $('#ttv-card .metric-value').innerHTML=(ttv===null?'-':ttv+'<span class="unit">days</span>')+sample;
 $('#ttv-card .metric-note').textContent=ttv===null?'No eligible integrations in this range':'From integration to first later-day sync';
 $('#ttv-modal-value').innerHTML=ttv===null?'-':ttv+' <span>days</span>';
 $('#ttv-scope-detail').hidden=!filtered;
 $('#ttv-scope-detail').innerHTML=`<span>${esc(scope)} · ${activationTotals.ttvN} eligible companies</span><span class="sample-pill">Sample data</span>`;
}
function updateChurnMetric(latest){
 const value=latest?latest.rate.toFixed(1)+'%':'-',period=latest?latest.month+' 2026':rangeLabel(appliedRange);
 const delta=latest?.delta==null?'':`${latest.delta>0?'+':''}${latest.delta.toFixed(1)} pp`;
 $('#churn-metric-card .metric-period').textContent=period;
 $('#churn-metric-card .metric-value').textContent=value;
 $('#churn-metric-card .metric-note').textContent=latest?'Activated companies with no core activity in '+latest.month:'No completed months in this range';
 $('#churn-metric-card').setAttribute('aria-label',`Month-on-month churn, ${period}: ${latest?value:'not available'}. View definition.`);
 $('#churn-modal-period').textContent=period;
 $('#churn-modal-value').textContent=value;
 $('#churn-metric-description').textContent=latest?`Share of eligible activated companies with no core activity in ${monthName('2026-'+String(months.indexOf(latest)+4).padStart(2,'0'))}.`:'Monthly churn is calculated only for completed calendar months. No completed month with data falls within the selected range.';
 const previous=latest?months[months.indexOf(latest)-1]:null;
 $('#churn-modal-detail').innerHTML=latest?`<span><strong>${latest.churned}</strong> of <strong>${latest.eligible}</strong> eligible companies</span>`:`<span>${esc(rangeLabel(appliedRange))}</span>`;
}
function renderDashboard(){
 prepareActivationData();renderHeatmap();renderChurn();loadRetentionKpis();
 $('#date-range-value').textContent=rangeLabel(appliedRange);
 $('#date-range-trigger').title='Global date range: '+rangeLabel(appliedRange);
 $('#reset-range').hidden=appliedRange.preset==='lifetime';
 syncAllSelects();
 requestAnimationFrame(renderChurnChart);
}
function currentDefinitions(){
 const latest=visibleChurnMonths().at(-1),rate=activationTotals.total?(100*activationTotals.active/activationTotals.total).toFixed(1)+'%':'Not available';
 const live=liveRetentionKpis,activation=live?.activation,ttv=live?.ttv,churn=live?.churn;
 const liveActivationRate=activation?.rate_pct==null?rate:Number(activation.rate_pct).toFixed(1)+'%';
 const liveTtvDays=ttv?.avg_hours==null?activationTotals.ttv:Number(ttv.avg_hours)/24;
 const liveChurnRate=churn?.rate_pct==null?(latest?latest.rate.toFixed(1)+'%':'Not available'):Number(churn.rate_pct).toFixed(1)+'%';
 return {
  activation:`<section class="definition-block"><h3>Activation rate</h3><div class="definition-value">${liveActivationRate}</div><p>A company starts from its first successful integration. Its first qualifying Accounting Sync after integration is treated as the guided training sync. Training-day activity does not count. The company activates only after it returns on a later IST calendar day, completes a non-sync core job that is not failed, and then completes a qualifying Accounting Sync. Internal staff activity from aiaccountant.com, korefi.ai, and karboncard.com is excluded throughout.</p>${activation?`<div class="formula">${activation.activated} activated companies ÷ ${activation.integrated} integrated companies × 100</div>`:''}</section>`,
  ttv:`<section class="definition-block"><h3>Average time to value</h3><div class="definition-value">${liveTtvDays==null?'Not available':liveTtvDays.toFixed(1)+' days'}</div><p>Time to value runs from the first successful integration to the same Accounting Sync that closes activation after independent post-training core work. Only activated companies enter the average.</p>${ttv?`<div class="formula">${ttv.companies} companies · median ${(Number(ttv.median_hours)/24).toFixed(1)} days</div>`:''}</section>`,
  churn:`<section class="definition-block"><h3>Monthly churn</h3><div class="definition-value">${liveChurnRate}</div><p>For the latest completed calendar month in the selected range, a company is eligible if it activated before the month began. It is churned when it has no core activity during that month. Internal staff activity from aiaccountant.com, korefi.ai, and karboncard.com is excluded from the activity clock.</p>${churn?.month?`<div class="formula">${churn.churned} churned companies ÷ ${churn.eligible} eligible companies × 100</div>`:''}</section>`,
  retention:`<section class="definition-block"><h3>Retention</h3><p>The global range selects activation cohort start dates. Return windows are evaluated using all available data through the snapshot, not truncated at the end of the cohort filter.</p><p>Weekly keeps the supplied cohort data. Monthly groups unique companies by activation calendar month. Month 1 is the next calendar month; only completed return months are eligible. Monthly data here is illustrative company-level activity, not a mean or sum of weekly percentages.</p><p>Each cell counts unique retained companies. Average pools retained and eligible companies across visible cohorts. A missing window is not yet eligible. In the drill-down, Churned means no qualifying return in the selected window, not permanent churn. A user can own companies in both tabs.</p></section>`,
  scope:`<section class="definition-block"><h3>Global date range</h3><p>Current selection: <strong>${esc(rangeLabel(appliedRange))}</strong>. Activation and time to value select companies by first successful integration date. Churn uses the latest completed calendar month inside the selected range. Current, incomplete churn months are excluded.</p></section>`
 };
}


/* v6 company drill. The event adapter below is deliberately a local fixture.
 * Weekly and monthly demonstrations use their respective existing v5 catalogs,
 * which were independently mocked. Do not combine them into production data.
 * Every table, health signal and journey in one drill uses the SAME event list.
 * A selected retained cell has events in its window; a churned cell has none.
 * Replace buildCompanyEvents with a server-side company/activity lookup. */
const COMPANY_FLOWS=[
 {key:'bills',label:'Bills',children:[['bill_upload','Bill uploaded'],['bill_create','Record created (bill)'],['bill_edit','Bills bulk edited'],['vendor_resolved','Vendor mismatch resolved']]},
 {key:'invoices',label:'Invoices',children:[['invoice_upload','Invoice uploaded'],['invoice_create','Record created (invoice)']]},
 {key:'statements',label:'Statements',children:[['statement_upload','Statement uploaded']]},
 {key:'transactions',label:'Transactions',children:[['transaction_update','Entry updated']]},
 {key:'sync',label:'Accounting sync',children:[['accounting_sync','Qualifying accounting sync']]}
];
const companyDrill={company:null,context:null,events:[],tab:'overview',trigger:null,expanded:new Set(['bills']),journeyExpanded:new Set()};
const mondayFor=iso=>{const d=new Date(iso+'T12:00:00Z');return addDays(iso,-((d.getUTCDay()+6)%7));};
const daysBetween=(a,b)=>Math.floor((Date.parse(b+'T12:00:00Z')-Date.parse(a+'T12:00:00Z'))/86400000);
const fullDate=iso=>iso?cohortLabel(iso):'Not available';
const numberCell=n=>`<span class="${n===0?'zero':'has-activity'}">${fmt.format(n)}</span>`;
function sumEvents(events,type=null){return events.reduce((sum,e)=>sum+(!type||e.type===type?e.count:0),0);}
function eventsWithin(events,start,end){return events.filter(e=>(!start||e.date>=start)&&(!end||e.date<=end));}
function firstEvent(events){return events.length?events[0]:null;}
function lastEvent(events){return events.length?events.at(-1):null;}
function relativeDate(iso){if(!iso)return 'No recorded activity';const d=daysBetween(iso,SNAPSHOT_DATE);return d===0?'Today':d===1?'1 day ago':fmt.format(d)+' days ago';}
function eventTime(e){return e?dateLabel(e.date)+' '+e.timestamp.slice(11,16):'No activity';}
function companySelectedWindow(c,context){
 if(!context)return null;
 if(context.view==='monthly'){
  const month=shiftMonth(c.activated.slice(0,7),context.week);
  return {start:month+'-01',end:monthLast(month),label:'Month '+context.week,dates:monthName(month),cohort:monthName(c.activated.slice(0,7))};
 }
 const start=addDays(c.cohort,context.week*7),end=addDays(start,6);
 return {start,end,label:'Week '+context.week,dates:dateLabel(start)+' to '+dateLabel(end)+' 2026',cohort:fullDate(c.cohort)};
}
function buildCompanyEvents(c,view){
 if(!c.activated)return [];
 const events=[];
 const push=(date,type,count,time='14:00')=>{if(count>0&&date<=SNAPSHOT_DATE)events.push({date,type,count,timestamp:date+'T'+time+':00Z',user:c.ownerId});};
 // Integration itself is setup. Only recorded work events and syncs are counted.
 push(c.integrated||addDays(c.activated,-2),'bill_upload',8+hashText(c.id+'pre')%35,'10:00');
 push(addDays(c.activated,-1),'bill_create',4+hashText(c.id+'precreate')%19,'15:00');
 push(c.activated,'accounting_sync',1,'11:30');
 push(c.activated,'bill_upload',6+hashText(c.id+'activationwork')%22,'14:00');
 const activity=(date,index,start)=>{
  const h=hashText(c.id+'|'+view+'|'+index);
  // More than one active day only when it remains inside the known return window.
  if(date>start&&h%3===0)push(start,'bill_upload',3+h%12,'10:15');
  push(date,'bill_upload',12+h%82,'09:45');
  push(date,'bill_create',8+(h>>>4)%66,'10:20');
  push(date,'bill_edit',h%3===0?1+(h>>>8)%6:0,'10:40');
  push(date,'vendor_resolved',h%5===0?1+(h>>>10)%3:0,'11:15');
  push(date,'invoice_upload',h%4===0?2+(h>>>12)%13:0,'12:00');
  push(date,'invoice_create',h%4===0?1+(h>>>15)%10:0,'12:30');
  push(date,'statement_upload',h%6===0?1+(h>>>7)%4:0,'13:00');
  push(date,'transaction_update',h%5===0?3+(h>>>3)%16:0,'14:00');
  if(h%4===0)push(date,'accounting_sync',1,'16:00');
 };
 if(view==='monthly'){
  c.monthlyReturns.forEach((returned,i)=>{if(returned===true){const date=c.monthlyDates[i];activity(date,i,date.slice(0,7)+'-01');}});
 }else{
  c.returns.forEach((returned,i)=>{if(returned===true){const start=addDays(c.cohort,(i+1)*7);activity(addDays(start,(c.index+i)%7),i,start);}});
 }
 return events.sort((a,b)=>a.timestamp.localeCompare(b.timestamp));
}
function companyRecentPeriods(view='weekly'){
 if(view==='monthly')return Array.from({length:4},(_,i)=>{const month=shiftMonth(LAST_COMPLETE_MONTH,i-3);return {start:month+'-01',end:monthLast(month),label:shortMonth(month),secondary:''};});
 const current=mondayFor(SNAPSHOT_DATE);
 return Array.from({length:4},(_,i)=>{const start=addDays(current,(i-4)*7);return {start,end:addDays(start,6),label:dateLabel(start),secondary:'to '+dateLabel(addDays(start,6))};});
}
function companyComparison(){
 const mode=$('#company-activity-scope').value,selected=companyDrill.window;
 if(mode==='selected'&&selected)return selected;
 if(mode==='recent'){const periods=companyRecentPeriods('weekly');return {start:periods[0].start,end:periods.at(-1).end,label:'Last 4 weeks',dates:dateLabel(periods[0].start)+' to '+dateLabel(periods.at(-1).end)+' 2026'};}
 if(mode==='selected'&&!selected)return {start:appliedRange.start?appliedRange.start+'-01':null,end:appliedRange.end?monthLast(appliedRange.end):SNAPSHOT_DATE,label:'Dashboard range',dates:rangeLabel(appliedRange)};
 return {start:LAST_COMPLETE_MONTH+'-01',end:monthLast(LAST_COMPLETE_MONTH),label:'Last complete month',dates:monthName(LAST_COMPLETE_MONTH)};
}
function renderCompanyOverview(){
 const {company:c,events}=companyDrill;
 const total=sumEvents(events),last=lastEvent(events),sync=lastEvent(events.filter(e=>e.type==='accounting_sync'));
 const activeWeeks=new Set(events.filter(e=>e.timestamp>=c.activated+'T11:30:00Z').map(e=>mondayFor(e.date))).size;
 const recent=companyRecentPeriods('monthly'),activeMonths=recent.filter(p=>eventsWithin(events,p.start,p.end).length).length;
 const sinceSync=sync?sumEvents(events.filter(e=>e.timestamp>sync.timestamp)):null;
 $('#company-health-grid').innerHTML=[
  ['Lifetime core actions',fmt.format(total),'All recorded core events',false],
  ['Active weeks',fmt.format(activeWeeks),'Since activation',false],
  ['Last core activity',last?dateLabel(last.date)+' 2026':'No activity',relativeDate(last?.date),true],
  ['Last accounting sync',sync?dateLabel(sync.date)+' 2026':'No sync',sync?relativeDate(sync.date):'Not recorded',true]
 ].map(([label,value,note,date])=>`<div class="company-health-cell"><span class="company-health-label">${label}</span><strong class="company-health-value ${date?'is-date':''}">${value}</strong><span class="company-health-meta">${note}</span></div>`).join('');
 $('#company-signal-grid').innerHTML=[
  ['Activated',c.activated?fullDate(c.activated):'Not activated',c.activated?'Qualifying accounting sync':''],
  ['Integration → qualifying sync',c.ttvDays!=null?c.ttvDays+' '+(c.ttvDays===1?'day':'days'):'Not available','Successful integration to later-day sync'],
  ['Recent cadence',`Active in ${activeMonths} of 4 months`,shortMonth(recent[0].start.slice(0,7))+' to '+shortMonth(recent.at(-1).start.slice(0,7))],
  ['Core actions since last sync',sinceSync===null?'Not available':fmt.format(sinceSync),'Recorded after the most recent sync']
 ].map(([label,value,note])=>`<div class="company-signal"><span>${label}</span><strong title="${esc(note)}">${value}</strong></div>`).join('');
 const insight=$('#company-insight'),weeks=companyRecentPeriods('weekly');
 const hasRecent=eventsWithin(events,weeks[0].start,weeks.at(-1).end).length>0;
 const returnedLater=companyDrill.window&&companyDrill.status==='churned'?events.find(e=>e.date>companyDrill.window.end):null;
 let insightCopy;
 if(returnedLater)insightCopy=`<strong>Returned after this window.</strong> Next core activity: ${fullDate(returnedLater.date)}. The churned status is period-specific.`;
 else if(companyDrill.status==='retained'&&!hasRecent)insightCopy='<strong>Retained then, no recent activity.</strong> No core actions in the last 4 completed weeks.';
 else if(sinceSync>0)insightCopy=`<strong>Activity continued after the last sync.</strong> ${fmt.format(sinceSync)} core actions were recorded after ${dateLabel(sync.date)} without another accounting sync.`;
 else if(!c.activated)insightCopy='<strong>No qualifying activation recorded.</strong> This company has not reached the activation milestone.';
 else insightCopy='<strong>No core actions after the last sync.</strong> Recent activity is separate from the selected retention window.';
 insight.classList.toggle('neutral',!sinceSync);
 insight.innerHTML=icon('info')+'<span>'+insightCopy+'</span>';
 renderCompanyCadence();
}
function renderCompanyCadence(){
 const view=$('#company-cadence-view').value,periods=companyRecentPeriods(view);
 $('#company-cadence-caption').textContent=view==='weekly'?'Last 4 completed weeks':'Last 4 completed months';
 const rows=periods.map(p=>{const events=eventsWithin(companyDrill.events,p.start,p.end);return {core:sumEvents(events),days:new Set(events.map(e=>e.date)).size,users:new Set(events.map(e=>e.user)).size,syncs:sumEvents(events,'accounting_sync')};});
 $('#company-cadence-table').innerHTML=`<thead><tr><th scope="col">Activity</th>${periods.map((p,i)=>`<th scope="col" class="${i===3?'selected-col':''}">${p.label}${p.secondary?'<small>'+p.secondary+'</small>':''}</th>`).join('')}</tr></thead><tbody>${[['core','Core actions'],['days','Active days'],['users','Active users'],['syncs','Accounting syncs']].map(([key,label])=>`<tr><th scope="row">${label}</th>${rows.map((row,i)=>`<td class="${i===3?'selected-col':''}">${numberCell(row[key])}</td>`).join('')}</tr>`).join('')}</tbody>`;
}
function renderCompanyActivity(){
 const scope=companyComparison(),{events}=companyDrill,selected=eventsWithin(events,scope.start,scope.end);
 $('#company-activity-caption').innerHTML=`<strong>${esc(scope.label)}: ${esc(scope.dates)}</strong><span class="comparison-dot">·</span><span>Compared with lifetime</span>`;
 $('#company-activity-table').innerHTML=`<thead><tr><th scope="col">Workflow / event</th><th scope="col" class="selected-col">${esc(scope.label)}<small>${esc(scope.dates)}</small></th><th scope="col">Lifetime<small>Through 4 Oct 2026</small></th></tr></thead><tbody>${COMPANY_FLOWS.map(flow=>{
  const types=new Set(flow.children.map(([key])=>key));
  const inPeriod=sumEvents(selected.filter(e=>types.has(e.type))),all=sumEvents(events.filter(e=>types.has(e.type)));
  const expanded=companyDrill.expanded.has(flow.key),expandable=flow.key!=='sync';
  return `<tr class="flow-group"><th scope="row">${expandable?`<button type="button" class="flow-toggle" data-company-flow="${flow.key}" aria-expanded="${expanded}" aria-label="${expanded?'Collapse':'Expand'} ${flow.label} activity">${icon('right')}${flow.label}</button>`:`<span style="padding-left:19px">${flow.label}</span>`}</th><td class="selected-col">${numberCell(inPeriod)}</td><td>${numberCell(all)}</td></tr>`+(expanded&&expandable?flow.children.map(([type,label])=>`<tr class="flow-child"><th scope="row">${label}</th><td class="selected-col">${numberCell(sumEvents(selected,type))}</td><td>${numberCell(sumEvents(events,type))}</td></tr>`).join(''):'');
 }).join('')}</tbody><tfoot><tr><th scope="row">Total core actions</th><td>${fmt.format(sumEvents(selected))}</td><td>${fmt.format(sumEvents(events))}</td></tr></tfoot>`;
 $('#company-expand-all').textContent=COMPANY_FLOWS.filter(f=>f.key!=='sync').every(f=>companyDrill.expanded.has(f.key))?'Collapse all':'Expand all';
}
function renderCompanyJourney(){
 const {company:c,events}=companyDrill,activated=c.activated?c.activated+'T11:30:00Z':null;
 const phases=[
  {key:'before',label:'Before activation',events:events.filter(e=>!activated||e.timestamp<activated)},
  {key:'activation',label:'Activation reached',events:events.filter(e=>e.timestamp===activated)},
  {key:'after',label:'After activation',events:events.filter(e=>activated&&e.timestamp>activated)}
 ];
 $('#company-milestones').innerHTML=[['Signed up',fullDate(c.signup),'Account created'],['Integrated',fullDate(c.integrated),'Setup, not a core event'],['Activated',c.activated?fullDate(c.activated):'Not activated',c.activated?'11:30 · Qualifying sync':'No qualifying sync']].map(([label,date,note])=>`<div class="journey-milestone"><span>${label}</span><strong>${date}</strong><small>${note}</small></div>`).join('');
 $('#company-journey-table').innerHTML=`<thead><tr><th scope="col">Phase</th><th scope="col">First activity</th><th scope="col">Last activity</th><th scope="col">Core events</th></tr></thead><tbody>${phases.map(phase=>{
  const items=phase.events,expanded=companyDrill.journeyExpanded.has(phase.key),expandable=phase.key!=='activation'&&items.length>0;
  return `<tr class="journey-phase"><td>${expandable?`<button class="flow-toggle" type="button" data-company-phase="${phase.key}" aria-expanded="${expanded}">${icon('right')}${phase.label}</button>`:`<strong style="padding-left:19px">${phase.label}</strong>`}</td><td>${items.length?fullDate(items[0].date):'<span class="zero">No activity</span>'}${items.length?'<small>'+items[0].timestamp.slice(11,16)+'</small>':''}</td><td>${items.length?fullDate(items.at(-1).date):'<span class="zero">No activity</span>'}${items.length?'<small>'+items.at(-1).timestamp.slice(11,16)+'</small>':''}</td><td>${numberCell(sumEvents(items))}</td></tr>`+(expanded?COMPANY_FLOWS.map(flow=>{
   const types=new Set(flow.children.map(([key])=>key)),subset=items.filter(e=>types.has(e.type));
   return subset.length?`<tr class="journey-child"><td>${flow.label}</td><td>${dateLabel(subset[0].date)}</td><td>${dateLabel(subset.at(-1).date)}</td><td>${numberCell(sumEvents(subset))}</td></tr>`:'';
  }).join(''):'');
 }).join('')}</tbody>`;
 $('#company-journey-total').innerHTML=`<span>Before + activation + after</span><strong>${fmt.format(sumEvents(events))} total core events</strong>`;
}
function setCompanyTab(tab,focus=false){
 if(!['overview','activity','journey'].includes(tab))return;
 closeSelectMenu();companyDrill.tab=tab;
 $$('#company-dialog .company-tab').forEach(b=>{const selected=b.dataset.companyTab===tab;b.setAttribute('aria-selected',String(selected));b.tabIndex=selected?0:-1;});
 ['overview','activity','journey'].forEach(t=>{$('#company-'+t+'-panel').hidden=t!==tab;});
 if(focus)$('#company-'+tab+'-tab').focus({preventScroll:true});
}
function openCompanyDrill(button){
 const id=button.dataset.openCompany;
 const user=records[tableState.tab].find(u=>u.companyRows?.some(c=>c.id===id));
 const c=user?.companyRows.find(c=>c.id===id);if(!c)return;
 companyDrill.company=c;companyDrill.trigger=button;
 companyDrill.context=tableState.mode==='retention'?{...retentionContext}:null;
 companyDrill.status=tableState.tab;companyDrill.window=companySelectedWindow(c,companyDrill.context);
 const view=companyDrill.context?.view||'weekly';
 companyDrill.events=buildCompanyEvents(c,view);
 companyDrill.expanded=new Set(['bills']);companyDrill.journeyExpanded=new Set();
 $('#company-dialog-title').textContent=c.name;
 $('#company-heading-meta').innerHTML=`<span class="integration-tag">${esc(c.integration)}</span><span class="meta-separator">·</span><span class="company-owner">${esc(c.email)}</span>`;
 $('#company-back-label').textContent=companyDrill.context?'Retention breakdown':'Activation breakdown';
 $('#company-back').setAttribute('aria-label','Back to '+(companyDrill.context?'retention':'activation')+' breakdown');
 $('#company-window-context .company-context-note').textContent=companyDrill.context?'Status applies to this return window':'Status as of 4 Oct 2026';
 const window=companyDrill.window;
 $('#company-context-main').innerHTML=window?statusBadge(companyDrill.status)+`<strong>${esc(window.cohort)} cohort · ${esc(window.label)}</strong><span>${esc(window.dates)}</span>`:`<strong>${c.activated?'Activated':'Not activated'}</strong><span>Dashboard range: ${esc(rangeLabel(appliedRange))}</span>`;
 const selectedOption=$('#company-activity-scope option[value="selected"]');
 selectedOption.textContent=window?'Selected '+(view==='monthly'?'month':'week'):'Dashboard date range';
 selectedOption.dataset.description=window?window.dates:rangeLabel(appliedRange);
 $('#company-activity-scope').value=window?'selected':'latest';
 $('#company-cadence-view').value='weekly';
 renderCompanyOverview();renderCompanyActivity();renderCompanyJourney();syncAllSelects();setCompanyTab('overview');
 $$('.company-panel').forEach(panel=>panel.scrollTop=0);
 openDialog('company-dialog');
 $('#company-back').focus({preventScroll:true});
}
function initCompanyDrill(){
 document.addEventListener('click',event=>{
  const button=event.target.closest('button');if(!button)return;
  if(button.dataset.openCompany){openCompanyDrill(button);return;}
  if(button.dataset.companyTab){setCompanyTab(button.dataset.companyTab);return;}
  if(button.dataset.companyFlow){const key=button.dataset.companyFlow;companyDrill.expanded.has(key)?companyDrill.expanded.delete(key):companyDrill.expanded.add(key);renderCompanyActivity();$(`[data-company-flow="${key}"]`)?.focus({preventScroll:true});return;}
  if(button.dataset.companyPhase){const key=button.dataset.companyPhase;companyDrill.journeyExpanded.has(key)?companyDrill.journeyExpanded.delete(key):companyDrill.journeyExpanded.add(key);renderCompanyJourney();$(`[data-company-phase="${key}"]`)?.focus({preventScroll:true});return;}
 });
 $('#company-back').addEventListener('click',()=>closeDialog('company-dialog'));
 $('#company-cadence-view').addEventListener('change',renderCompanyCadence);
 $('#company-activity-scope').addEventListener('change',renderCompanyActivity);
 $('#company-expand-all').addEventListener('click',()=>{
  const all=COMPANY_FLOWS.filter(f=>f.key!=='sync').every(f=>companyDrill.expanded.has(f.key));
  companyDrill.expanded=all?new Set():new Set(COMPANY_FLOWS.filter(f=>f.key!=='sync').map(f=>f.key));renderCompanyActivity();
 });
 $('#company-dialog').addEventListener('close',()=>{const trigger=companyDrill.trigger;requestAnimationFrame(()=>{if(trigger?.isConnected&&$('#activation-dialog').open)trigger.focus({preventScroll:true});});});
 $('.company-tabs').addEventListener('keydown',event=>{
  if(!event.target.matches('.company-tab')||!['ArrowLeft','ArrowRight','Home','End'].includes(event.key))return;
  event.preventDefault();const tabs=['overview','activity','journey'],index=tabs.indexOf(event.target.dataset.companyTab);
  setCompanyTab(tabs[event.key==='Home'?0:event.key==='End'?2:(index+(event.key==='ArrowRight'?1:2))%3],true);
 });
}

initSelects();
initCompanyDrill();
initDatePicker();
renderDashboard();
renderUsers();


