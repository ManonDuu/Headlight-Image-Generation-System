'use strict';
let savedRecord=null,savedSignature=null,backendBusy=false,connected=false,pollBusy=false,pendingId=null,pendingRetry=null;
const generateSet=$('generateSet');
let viewerRecord=null,viewerSlot=null,notifiedResult=null,toastTimer=null,viewEpoch=0;
const signature=()=>JSON.stringify(buildPlan());
function remember(id){try{localStorage.setItem('module-three-active',id);}catch(e){}}
function recalled(){try{return localStorage.getItem('module-three-active');}catch(e){return null;}}
function controls(){const retryable=Boolean(savedRecord?.generation)&&savedRecord.generation.state!=='running'&&(savedRecord.generation.state==='paused'||savedRecord.generation.images?.some(t=>t.state==='stopped'));$('retrySet').hidden=!retryable;$('retryNotice').hidden=!retryable;$('retrySet').disabled=!connected||backendBusy||Boolean(pendingId);generateSet.disabled=!connected||backendBusy||Boolean(pendingId)||Boolean(savedRecord?.generation);}
const priorInvalidate=invalidate;
invalidate=function(){priorInvalidate();savedRecord=null;savedSignature=null;$('generationResults').replaceChildren();$('resultCollection').hidden=true;$('downloadSet').hidden=true;$('backendStatus').textContent='';controls();};
const originalGo=go;
go=function(target){document.querySelector('footer').hidden=false;$('historyPanel').hidden=true;originalGo(target);};
async function localAPI(path,body){
 let response;
 try{response=await fetch(path,{method:body===undefined?'GET':'POST',headers:body===undefined?{}:{'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000)});}
 catch(e){const error=new Error('本地服务连接中断，暂时无法确认提交状态；正在查询记录，不会重新发送生成请求');error.uncertain=true;throw error;}
 const data=await response.json();if(!response.ok)throw new Error(data.error||'请求未被接受');return data;
}
function encodeFile(file){return new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve({name:file.name,base64:String(reader.result).split(',')[1]});reader.onerror=()=>reject(new Error('图片读取失败，尚未提交生成'));reader.readAsDataURL(file);});}
async function prepareRecord(){const error=validate(3);if(error)throw new Error(error);if(savedRecord&&savedSignature===signature())return savedRecord;const current=signature(),plan=buildPlan(),uploads=[];for(const a of assets)uploads.push(await encodeFile(a.file));const r=await localAPI('/listing/api/prepare',{plan,uploads});if(current!==signature())throw new Error('资料已变化，尚未提交生成，请检查后再次开始');savedRecord=r;savedSignature=current;remember(r.id);return r;}
async function perform(action){if(backendBusy)return;backendBusy=true;controls();try{await action();}catch(e){$('backendStatus').textContent=e.message;}finally{backendBusy=false;if(!savedRecord?.generation&&!pendingId)generateSet.textContent='开始生成整套图片';controls();}}
function showResults(r){document.querySelector('footer').hidden=true;savedRecord=r;remember(r.id);$('historyPanel').hidden=true;document.querySelectorAll('[data-panel]').forEach(p=>p.hidden=p.dataset.panel!=='3');step=3;$('plans').hidden=true;$('summary').textContent=`${r.plan.count} 张 · ${r.plan.style.ratio} · ${r.plan.product.configuration}`;renderGeneration(r);}
function renderGeneration(r){
 const tasks=r.generation?.images||[],done=tasks.filter(t=>t.state==='completed').length,failed=tasks.filter(t=>t.state==='stopped').length,active=tasks.find(t=>t.state==='running'),waiting=r.plan.count-tasks.length;
 const running=r.generation?.state==='running'||Boolean(active);
 const budgetPaused=r.generation?.pauseReason==='budget-limit'||Boolean(r.generation?.error?.includes('预算'));
 const paused=r.generation?.state==='paused';
 if(r.generation){$('backendStatus').textContent=running?`正在生成，第 ${active?.slot||Math.min(tasks.length+1,r.plan.count)}／${r.plan.count} 张 · 已成功 ${done} 张`:`已成功生成 ${done} 张，失败 ${failed} 张${waiting?`，${waiting} 张未提交`:''}。${r.generation.error||''}`;}
 if(budgetPaused)$('backendStatus').textContent=`因每日预留预算上限暂停：已成功 ${done} 张，${waiting} 张未提交。该额度是本模块的保守预留额度，不等于 Google 实际扣款。失败或超时也占用预留额度；额度恢复后可继续本套，无需重新填写。`;
 const box=$('generationResults');box.replaceChildren();
 $('resultCollection').hidden=false;
 $('collectionCount').textContent=`共 ${r.plan.count} 张 · 成功 ${done} 张${failed?' · 失败 '+failed+' 张':''} · 点击缩略图查看大图`;
 for(const brief of r.plan.images){
  const t=tasks.find(t=>t.slot===brief.slot),card=el('article',undefined,'result-card');
  const media=el(t?.state==='completed'?'button':'div',undefined,'result-thumb');
  if(t?.state==='completed'){
   media.type='button';media.setAttribute('aria-label',`查看第 ${brief.slot} 张：${brief.sellingPoint}`);
   const img=el('img');img.src=`/listing/api/tasks/${r.id}/results/${brief.slot}`;img.alt=brief.sellingPoint;img.loading='lazy';media.append(img);media.onclick=()=>openViewer(r,brief.slot);
  }else{media.append(el('span',t?.state==='running'?'正在生成…':t?.state==='stopped'?'生成未完成':budgetPaused?'预算暂停 · 未提交':paused?'队列暂停 · 未提交':'等待生成'));}
  const info=el('div',undefined,'result-info');info.append(el('h3',`${brief.slot}. ${brief.sellingPoint}`));
  const status=t?.state==='completed'?'成功':t?.state==='running'?'生成中':t?.state==='stopped'?'失败':budgetPaused?'未提交（预算上限）':paused?'未提交（队列暂停）':'等待中';info.append(el('span',status,'task-status status-'+(t?.state||'waiting')));
  if(t?.error){const billing=t.diagnostic?.httpStatus===402;info.append(el('p',billing?'计费未通过（HTTP 402）。请检查反代服务的余额或计费状态；无需反复点击生成。':t.error,'result-error'));}
  if(t?.state==='completed'){const a=el('a','下载');a.href=`/listing/api/tasks/${r.id}/results/${brief.slot}`;a.download=t.file||`image-${brief.slot}`;info.append(a);}
  card.append(media,info);box.append(card);
 }
 if(!running&&r.generation){const stamp=r.id+':'+done+':'+failed;if(notifiedResult!==stamp){notifiedResult=stamp;notifyTask(`${paused?'任务已暂停':'出图结束'}：成功 ${done} 张${failed?'，失败 '+failed+' 张':''}。可在整套图片中查看、下载`);}}
 $('downloadSet').hidden=!done;$('downloadSet').href=`/listing/api/tasks/${r.id}/download`;$('downloadSet').download=`images-${r.id}.zip`;
 $('retrySet').textContent=failed?'重试失败图片并继续本套':'继续生成剩余图片';
 generateSet.textContent=running?'正在生成，请稍候':r.generation?'本任务已提交':'开始生成整套图片';controls();
}
generateSet.onclick=()=>perform(async()=>{
 if(pendingId||savedRecord?.generation)return;
 generateSet.textContent='正在准备整套图片…';$('backendStatus').textContent='正在保存资料，尚未提交模型';
 const r=await prepareRecord();pendingId=r.id;remember(r.id);showResults(r);$('backendStatus').textContent=`正在提交，第 1／${r.plan.count} 张；请勿重复点击`;
 try{const result=await localAPI(`/listing/api/tasks/${r.id}/generate-set`,{});pendingId=null;showResults(result);}
 catch(e){if(!e.uncertain)pendingId=null;throw e;}
 finally{await refreshTasks();}
});
$('retrySet').onclick=()=>perform(async()=>{
 if(pendingId||!savedRecord)return;
 const id=savedRecord.id,requestId=crypto.randomUUID();pendingRetry=requestId;pendingId=id;controls();
 $('backendStatus').textContent='正在提交重试，成功图片将保留…';
 try{const r=await localAPI(`/listing/api/tasks/${id}/retry-set`,{requestId});pendingId=null;pendingRetry=null;notifiedResult=null;showResults(r);}
 catch(e){if(!e.uncertain){pendingId=null;pendingRetry=null;}throw e;}
});
async function refreshTasks(){try{const {tasks}=await localAPI('/listing/api/tasks');$('savedTasks').replaceChildren();if(!tasks.length)$('savedTasks').append(el('p','暂无生成记录'));for(const t of tasks){const row=el('div',undefined,'order-row');row.append(el('span',`${t.configuration} · ${t.count} 张 · ${new Date(t.createdAt).toLocaleString()}`));const b=el('button','查看进度与结果');b.type='button';b.onclick=()=>perform(async()=>showResults(await localAPI(`/listing/api/tasks/${t.id}`)));row.append(b);$('savedTasks').append(row);}}catch(e){$('savedTasks').textContent='无法连接本地服务，恢复后点击刷新记录；不会重发任务';}}
function openHistory(){document.querySelector('footer').hidden=true;document.querySelectorAll('[data-panel]').forEach(p=>p.hidden=true);$('historyPanel').hidden=false;refreshTasks();}
$('openHistory').onclick=openHistory;$('historyTop').onclick=openHistory;$('refreshTasks').onclick=refreshTasks;
$('savePlan').onclick=()=>perform(async()=>{renderGeneration(await prepareRecord());$('backendStatus').textContent='方案已保存，尚未提交模型';await refreshTasks();});
$('simulate').onclick=()=>perform(async()=>{const r=await prepareRecord();await localAPI(`/listing/api/tasks/${r.id}/simulate`,{});$('simulationStatus').textContent='模拟完成；未提交模型，未生成图片';});
$('export').onclick=()=>perform(async()=>{const r=await prepareRecord(),url=URL.createObjectURL(new Blob([JSON.stringify(r.plan,null,2)],{type:'application/json'})),a=el('a');a.href=url;a.download='image-plan.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});
// The server owns palette definitions; preview and saved briefs use the same catalog.
let paletteCatalog=[];
const baseStyleUpdate=updateStyle;
updateStyle=function(){baseStyleUpdate();const color=$('color').value,rgb=[1,3,5].map(i=>parseInt(color.slice(i,i+2),16));const tint='#'+rgb.map(v=>Math.round(v+(255-v)*.08).toString(16).padStart(2,'0')).join('');$('palette').replaceChildren();for(const [c,label] of [[color,'主题色 '+color.toUpperCase()],[tint,'同色系过渡']]){const chip=el('span',label);chip.style.background=c;const v=[1,3,5].map(i=>parseInt(c.slice(i,i+2),16));chip.style.color=(v[0]*299+v[1]*587+v[2]*114)/1000>145?'#202423':'#ffffff';$('palette').append(chip);}};

async function poll(){if(pollBusy)return;if(!pendingId&&savedRecord?.generation?.state!=='running'&&!savedRecord?.generation?.images?.some(t=>t.state==='running'))return;const id=pendingId||savedRecord?.id;if(!id)return;pollBusy=true;try{const r=await localAPI(`/listing/api/tasks/${id}`);if(r.generation&&(!pendingRetry||r.generation.retryRequests?.includes(pendingRetry))){pendingId=null;pendingRetry=null;}if(savedRecord?.id===id){const changed=JSON.stringify(savedRecord.generation)!==JSON.stringify(r.generation);savedRecord=r;if(changed)renderGeneration(r);if(pendingId)$('backendStatus').textContent='提交状态仍待确认；不会重发请求，请稍后在生成记录查看';}}catch(e){$('backendStatus').textContent='连接暂时中断；任务可能仍在执行，正在恢复查询，不会重新提交';}finally{pollBusy=false;controls();}}
setInterval(poll,2500);
(async()=>{try{const c=await localAPI('/listing/api/capabilities');if(c.budget)$('budgetLimit').textContent=c.budget.unlimited?`今日测试不限额（洛杉矶日期 ${c.budget.authorizationDate}），已预留 $${c.budget.reservedUSD}`:`系统今日预留上限 $${c.budget.limitUSD}，可用 $${c.budget.remainingUSD}`;connected=Boolean(c.liveEnabled)&&c.generationRevision==='durable-set-v5-dated-authorization';paletteCatalog=c.palettes||[];displayCatalog=c.displayCatalog||{};updateStyle();$('connectionState').textContent=connected?`生成服务已连接 · 规则 ${String(c.rulesRevision||'').split('-')[0]}`:c.liveEnabled?'服务需要更新，请重新双击启动文件':'模型未连接，请使用启动文件';controls();const epoch=viewEpoch,id=recalled();if(id){const r=await localAPI(`/listing/api/tasks/${id}`);if(epoch===viewEpoch)showResults(r);}await refreshTasks();}catch(e){$('connectionState').textContent='无法连接服务，请双击启动整套附图模块';controls();}})();

function notifyTask(message){$('taskToast').textContent=message;$('taskToast').hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>{$('taskToast').hidden=true;},6000);}
function newTask(){
 if(backendBusy||pendingId){notifyTask('正在确认本次提交状态，请稍候再新建');return;}
 viewEpoch++;assets.forEach(a=>URL.revokeObjectURL(a.url));assets=[];selected=[];
 $('form').reset();$('count').value='6';$('type').value='led';$('color').value='#f4b400';$('ratio').value='1:1';$('case').value='title-sentence';
 for(const id of ['brand','configuration','fitment','facts','custom'])$(id).value='';
 savedRecord=null;savedSignature=null;notifiedResult=null;try{localStorage.removeItem('module-three-active');}catch(e){}
 $('imageViewer').close();$('summary').textContent='';$('plans').replaceChildren();$('plans').hidden=false;
 $('type').onchange();renderPhotos();renderPoints();updateStyle();invalidate();go(0);
 generateSet.textContent='开始生成整套图片';notifyTask('新任务已创建，历史任务与图片仍保留');$('configuration').focus();
}
$('newTask').onclick=newTask;
function openViewer(r,slot){viewerRecord=r;viewerSlot=slot;renderViewer();if(!$('imageViewer').open)$('imageViewer').showModal();}
function renderViewer(){
 const available=viewerRecord.generation.images.filter(t=>t.state==='completed').sort((a,b)=>a.slot-b.slot);
 const index=available.findIndex(t=>t.slot===viewerSlot),item=available[index],brief=viewerRecord.plan.images.find(b=>b.slot===viewerSlot);
 const url=`/listing/api/tasks/${viewerRecord.id}/results/${viewerSlot}`;
 $('viewerTitle').textContent=brief.sellingPoint;$('viewerImage').src=url;$('viewerImage').alt=brief.sellingPoint;
 $('viewerDownload').href=url;$('viewerDownload').download=item.file;$('viewerPosition').textContent=`${index+1} / ${available.length} · 原图预览`;
 $('viewerPrevious').disabled=index===0;$('viewerNext').disabled=index===available.length-1;
}
function moveViewer(delta){const items=viewerRecord.generation.images.filter(t=>t.state==='completed').sort((a,b)=>a.slot-b.slot),index=items.findIndex(t=>t.slot===viewerSlot),next=items[index+delta];if(next){viewerSlot=next.slot;renderViewer();}}
$('viewerPrevious').onclick=()=>moveViewer(-1);$('viewerNext').onclick=()=>moveViewer(1);$('closeViewer').onclick=()=>$('imageViewer').close();
$('imageViewer').addEventListener('keydown',e=>{if(e.key==='ArrowRight'){e.preventDefault();moveViewer(1);}if(e.key==='ArrowLeft'){e.preventDefault();moveViewer(-1);}});
$('imageViewer').addEventListener('click',e=>{if(e.target===$('imageViewer'))$('imageViewer').close();});
