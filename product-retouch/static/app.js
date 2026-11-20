(()=>{'use strict';const $=id=>document.getElementById(id);let token,connected=false,encoded,task,busy=false,url,outputURL,revision=0;const preset=()=>document.querySelector('input[name=preset]:checked').value;const names={refined:'精致',premium:'增强',hero:'强效'};const note=t=>$('status').textContent=t;
const colorLabel=t=>t.colorMode==='preserve'?'保持原色':Number(t.lightness)===0?'原色深浅 0':('原色'+(Number(t.lightness)<0?'调深 ':'调浅 ')+Math.abs(Number(t.lightness)));
function clearResult(){for(const id of ['result','download']){$(id).hidden=true;}if(outputURL)URL.revokeObjectURL(outputURL);outputURL=null;$('result').removeAttribute('src');$('download').removeAttribute('href');}
function dismissToast(){$('completionToast').hidden=true;}
function finishToast(s){$('toastTitle').textContent=s.state==='completed'?'✓ 图片生成成功':'生成已停止';$('toastMessage').textContent=s.state==='completed'?'精修结果已就绪，可以查看并下载。':(s.error||'未生成图片，未自动重试。');$('toastView').hidden=s.state!=='completed';$('completionToast').hidden=false;}
$('toastClose').onclick=dismissToast;
$('toastView').onclick=()=>{$('result').scrollIntoView({behavior:'smooth',block:'center'});dismissToast();};
async function api(path,data){const r=await fetch(path,{method:data?'POST':'GET',headers:{'X-Session-Token':token||'','Content-Type':'application/json'},body:data?JSON.stringify(data):undefined});const s=await r.json();if(!r.ok)throw Error(s.error||'请求失败');return s;}
function update(){task=null;$('generate').hidden=true;const v=Number($('lightness').value);$('lightnessField').hidden=$('colorMode').value!=='lightness';$('lightnessValue').value=v===0?'0 · 原始深浅':Math.abs(v)+(v<0?' · 调深':' · 调浅');}
function lock(v){busy=v;document.querySelectorAll('input,select,#prepare,#generate,#newTask').forEach(x=>x.disabled=v);if(!v)$('prepare').disabled=!encoded;}
document.querySelectorAll('input[name=preset],#colorMode,#ratio').forEach(x=>x.onchange=update);$('lightness').oninput=update;
async function loadFile(f){if(busy)return;const n=++revision;encoded=null;update();$('prepare').disabled=true;$('source').hidden=true;if(!f)return;if(!['image/jpeg','image/png'].includes(f.type)||f.size>4194304){note('请选择4MB以内的JPEG或PNG。');return;}const img=new Image(),candidate=URL.createObjectURL(f);try{await new Promise((ok,fail)=>{img.onload=ok;img.onerror=fail;img.src=candidate;});const bytes=new Uint8Array(await f.arrayBuffer());if(n!==revision){URL.revokeObjectURL(candidate);return;}let binary='';for(let i=0;i<bytes.length;i+=32768)binary+=String.fromCharCode(...bytes.subarray(i,i+32768));encoded=btoa(binary);if(url)URL.revokeObjectURL(url);url=candidate;$('source').src=url;$('source').hidden=false;$('prepare').disabled=!token;note('图片已载入。');}catch(e){URL.revokeObjectURL(candidate);note('图片无法读取。');}}
$('newTask').onclick=()=>{
 if(busy)return;
 dismissToast();++revision;encoded=null;task=null;
 for(const id of ['source','result']){$(id).hidden=true;$(id).removeAttribute('src');}
 $('download').hidden=true;$('download').removeAttribute('href');$('download').removeAttribute('download');
 if(url)URL.revokeObjectURL(url);if(outputURL)URL.revokeObjectURL(outputURL);url=null;outputURL=null;
 $('file').value='';document.querySelector('input[name=preset][value=refined]').checked=true;
 $('colorMode').value='preserve';$('lightness').value='0';$('ratio').value='1:1';
 update();$('prepare').disabled=true;$('dropzone').classList.remove('dragging');
 note('已开启新任务，请拖入或选择一张图片。');$('file').focus();window.scrollTo({top:0,behavior:'smooth'});
};
$('file').onchange=()=>loadFile($('file').files[0]);
const dropzone=$('dropzone');
const hasFiles=e=>Array.from(e.dataTransfer?.types||[]).includes('Files');
window.addEventListener('dragover',e=>{if(hasFiles(e))e.preventDefault();});
window.addEventListener('drop',e=>{if(hasFiles(e))e.preventDefault();dropzone.classList.remove('dragging');});
dropzone.addEventListener('dragover',e=>{if(!hasFiles(e))return;e.preventDefault();if(!busy){e.dataTransfer.dropEffect='copy';dropzone.classList.add('dragging');}});
dropzone.addEventListener('dragleave',e=>{if(!dropzone.contains(e.relatedTarget))dropzone.classList.remove('dragging');});
dropzone.addEventListener('drop',e=>{e.preventDefault();dropzone.classList.remove('dragging');if(busy)return;const files=Array.from(e.dataTransfer?.files||[]);if(files.length!==1){note('请每次拖入一张JPEG或PNG图片。');return;}loadFile(files[0]);});
async function show(s){const n=revision;if(s.state==='completed'){const r=await fetch('/retouch/api/task/'+s.id+'/image',{headers:{'X-Session-Token':token}});if(!r.ok)throw Error('图片读取失败');const blob=await r.blob();if(n!==revision)return;if(outputURL)URL.revokeObjectURL(outputURL);outputURL=URL.createObjectURL(blob);$('result').src=outputURL;$('result').hidden=false;$('download').href=outputURL;$('download').download=s.id+(s.outputMime==='image/png'?'.png':'.jpg');$('download').hidden=false;note('已生成，待人工核对质感、结构和比例。');}else if(s.state==='stopped')note(s.error||'已停止，未自动重试。');}
let historyItems=[],historyPage=1;const historyPageSize=20;
function renderHistory(){
 const pages=Math.max(1,Math.ceil(historyItems.length/historyPageSize));historyPage=Math.min(Math.max(1,historyPage),pages);
 $('history').replaceChildren();
 for(const t of historyItems.slice((historyPage-1)*historyPageSize,historyPage*historyPageSize)){
  const b=document.createElement('button');const states={prepared:'待生成',running:'生成中',completed:'已完成',stopped:'已停止'};
  b.textContent=(t.createdAt||'').slice(0,16)+' · '+names[t.preset]+' · '+colorLabel(t)+' · '+t.ratio+' · '+(t.rulesVersion||'旧规则')+' · '+(states[t.state]||t.state)+(t.error?'：'+t.error:'');
  b.onclick=()=>show(t).catch(e=>note(e.message));$('history').append(b);
 }
 $('historyPageInfo').textContent=historyItems.length?'第 '+historyPage+' / '+pages+' 页 · 共 '+historyItems.length+' 条':'暂无记录';
 $('historyPrev').disabled=historyPage<=1;$('historyNext').disabled=historyPage>=pages;
 $('historyPager').hidden=historyItems.length===0;
}
$('historyPrev').onclick=()=>{historyPage--;renderHistory();};
$('historyNext').onclick=()=>{historyPage++;renderHistory();};
async function records(){const s=await api('/retouch/api/session');historyItems=[...s.history].sort((a,b)=>(b.createdAt||'').localeCompare(a.createdAt||''));historyPage=1;renderHistory();return s;}
$('prepare').onclick=async()=>{if(!encoded||busy)return;lock(true);try{task=await api('/retouch/api/prepare',{imageBase64:encoded,preset:preset(),ratio:$('ratio').value,colorMode:$('colorMode').value,lightness:$('colorMode').value==='preserve'?0:Number($('lightness').value)});$('generate').hidden=!connected;const colorSummary=colorLabel(task);note(connected?'准备完成：'+names[preset()]+' · '+colorSummary+'。点击后一次完成去背景线材和材质精修，保留原图拍摄视角与结构比例，仅提交产品原图，仅1次模型调用，输出1张图片，保存返回的原始字节，不因尺寸不同判失败，也不标成2K，零重试。':'设置已保存；本模块尚未配置专用模型连接，未提交付费请求。');}catch(e){note(e.message);}finally{lock(false);}};
$('generate').onclick=async()=>{if(!task||busy)return;dismissToast();clearResult();lock(true);const started=Date.now();const id=task.id;task=null;$('generate').hidden=true;try{note('正在提交生成任务…');let s=await api('/retouch/api/generate',{id});while(s.state==='running'){note('正在生成 · 已等待 '+Math.floor((Date.now()-started)/1000)+' 秒；保留原图视角并精修材质，不会自动重试。');await new Promise(r=>setTimeout(r,2000));s=await api('/retouch/api/task/'+id);}if(s.state==='completed'){finishToast(s);try{await show(s);}catch(e){$('toastMessage').textContent='图片已生成，但预览读取失败；请从历史记录重新打开。';$('toastView').hidden=true;note('图片已生成，预览读取失败。'+e.message);}}else{await show(s);finishToast(s);}try{await records();}catch(e){note('任务已结束，记录刷新失败，请刷新页面查看。');}}catch(e){const message='未取得最终结果，请查看记录，勿重复提交。'+e.message;note(message);finishToast({state:'unknown',error:message});$('toastTitle').textContent='结果状态待确认';}finally{lock(false);}};
update();api('/retouch/api/session').then(async s=>{token=s.token;connected=s.generationEnabled;note(connected?'独立模型已配置：'+s.provider+' · 规则 '+s.rulesVersion+' · 单次精修，待人工验收。':'界面已就绪，尚未配置本模块专用模型连接。');await records();}).catch(()=>note('服务未连接，请重新启动独立精修模块。'));
})();
