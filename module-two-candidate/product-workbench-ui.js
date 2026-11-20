'use strict';
(()=>{
 const fallbackSpec='car-light-product-20261022.10';
 const priorRequest=businessRequest;
 businessRequest=function(){const d=priorRequest();if(d.module==='product-replacement')d.businessSpec=session?.genericGC?.productReplacement?.businessSpec||fallbackSpec;return d;};
 const previousCanGenerate=canGenerate;
 canGenerate=function(s){
  if(s?.module!=='product-replacement')return previousCanGenerate(s);
  if(session?.paidRequestsPaused||!s||s.state!=='frozen')return false;
  const cfg=session?.genericGC?.productReplacement;
  if(!session.mock&&cfg?.businessSpec!==fallbackSpec)return false;
  if(s.genericGC?.version!==(cfg?.businessSpec||fallbackSpec))return false;
  if(session.history?.some(x=>x.state==='running'))return false;
  if(session.mock)return true;
  return !!(cfg?.dailyEnabled&&cfg?.liveEnabled&&session.genericGC?.enabled);
 };
 const materials=document.createElement('p');materials.id='productViewHint';materials.className='hint';materials.hidden=true;
 materials.textContent='建议使用透明底 PNG，并提供适合画面的产品角度。展示底部、风扇或安装细节时，优先上传对应视角的真实素材。';
 $('uploads').after(materials);
 const referencePlaceholder=$('productSpecs').placeholder;
 const priorOptions=options;
 options=function(){priorOptions();const product=$('module').value==='product-replacement';
  $('productSceneField').hidden=true;materials.hidden=!product;
  $('productSpecs').placeholder=product?'留空则沿用参考图参数；填写后仅替换对应项。':referencePlaceholder;
  if(!product)return;
  $('moduleNote').textContent='重构场景，保留关键元素与卖点关系，将真实产品自然融入；可选参考图排版或 AI 自动排版。';
  if($('mode').value==='ai-rewrite')$('optionNote').textContent='按原意改写文案，移除参考品牌；默认保留原图参数，仅替换你填写的对应项。';
  $('generate').textContent=session?.mock?'模拟生成一次 · 免费':'生成图片 · 上限 $0.27';
  const localEditor=document.getElementById('localProductEditor');if(localEditor)localEditor.hidden=true;
  $('freeze').disabled=!ref||!productRef||!!job||!!(session&&!session.mock&&session.genericGC?.productReplacement?.businessSpec!==fallbackSpec);
  $('session').textContent=session?.mock?'模拟模式':session&&session.genericGC?.productReplacement?.businessSpec!==fallbackSpec?'后台仍是旧版，请重新运行启动命令；刷新页面不能更新后台。':session?.genericGC?.productReplacement?.liveEnabled?'产品替换 V10 已连接；准备不收费，点击生成才提交。':'产品替换已准备；当前服务未启用正式生成。';
 };
 const previousFreeze=$('freeze').onclick;let preparing=false;
 $('freeze').onclick=async()=>{
  if($('module').value!=='product-replacement')return previousFreeze();
  if(preparing||job||$('freeze').disabled)return;
  preparing=true;$('freeze').disabled=true;
  try{pendingOptions=businessRequest();const frozen=await api('/api/freeze',pendingOptions);display(frozen);if(frozen.state==='frozen')inputsLocked();await refreshSession();}
  catch(e){say(job?'任务已保存；请从生成记录查看，勿重复提交。':'准备停止：'+e.message+'；未发送生成请求。');if(!job)$('freeze').hidden=false;}
  finally{preparing=false;options();}
 };
 options();
})();

// File drops reuse the same original-byte upload handlers as the file picker.
(()=>{
 const style=document.createElement('style');
 style.textContent='.asset.file-drag-active{outline:2px solid #2563eb;outline-offset:4px;border-radius:12px;background:#eff6ff}';
 document.head.append(style);
 const hasFiles=e=>Array.from(e.dataTransfer?.types||[]).includes('Files');
 for(const id of ['source','product']){
  const input=$(id),zone=input.closest('.asset');let depth=0;
  if(!zone)continue;
  zone.addEventListener('dragenter',e=>{if(!hasFiles(e))return;e.preventDefault();depth++;if(!input.disabled)zone.classList.add('file-drag-active');});
  zone.addEventListener('dragover',e=>{if(!hasFiles(e))return;e.preventDefault();e.dataTransfer.dropEffect=input.disabled?'none':'copy';});
  zone.addEventListener('dragleave',()=>{depth=Math.max(0,depth-1);if(!depth)zone.classList.remove('file-drag-active');});
  zone.addEventListener('drop',e=>{
   if(!hasFiles(e))return;e.preventDefault();depth=0;zone.classList.remove('file-drag-active');
   if(input.disabled){say('当前任务已锁定，请新建任务后上传图片。');return;}
   const files=Array.from(e.dataTransfer.files||[]);
   if(files.length!==1){say('每个区域请一次拖入一张图片。');return;}
   const file=files[0];
   if(!['image/jpeg','image/png',''].includes(file.type)||file.size>4194304){say('请选择最多 4MB 的 JPEG 或 PNG 图片。');return;}
   const transfer=new DataTransfer();transfer.items.add(file);input.files=transfer.files;
   input.dispatchEvent(new Event('change',{bubbles:true}));
  });
 }
 // Dropping a file outside an upload area must not navigate away from the task.
 document.addEventListener('dragover',e=>{if(hasFiles(e))e.preventDefault();});
 document.addEventListener('drop',e=>{if(hasFiles(e))e.preventDefault();});
 $('uploadBox').querySelector('span').textContent='点击或拖入参考图';
 $('productHint').textContent='点击或拖入真实产品原图';
})();

// Direct-generation tasks reset locally, without waiting for legacy canvas/IDB history.
(()=>{
 const legacyNewTask=newTask.onclick;
 newTask.onclick=async()=>{
  if(polling||job?.state==='running'){say('当前任务仍在运行，请等待结果。');return;}
  if(job&&job.workflow!=='direct-generation')return legacyNewTask();
  job=null;ref=null;productRef=null;imageBlob=null;pendingOptions=null;
  for(const id of ['source','product','module','ratio','width','height','tone','mode','copy','freeze','productName','brandName','productSpecs','color','removeSource','removeProduct','productScene','layout'])$(id).disabled=false;
  for(const id of ['source','product','copy','productName','brandName','productSpecs'])$(id).value='';
  $('mode').value='ai-rewrite';$('layout').value='keep-reference';$('productScene').value='change';
  for(const id of ['mode','layout'])$(id).querySelectorAll('[data-legacy]').forEach(n=>n.remove());
  for(const id of ['reference','output','sourceSelected','productThumb','resultPanel','showResult','historyPanel','analyze','generate'])$(id).hidden=true;
  for(const id of ['uploadBox','productPlus','productHint','freeze'])$(id).hidden=false;
  for(const id of ['generate','saveImage','saveRecord','review'])$(id).disabled=true;
  for(const id of ['prompt','usage','acceptance'])$(id).textContent='';
  $('sourceName').textContent='参考图';$('productFileName').textContent='产品图';
  $('checks').replaceChildren();$('preflight').replaceChildren();
  const editor=document.getElementById('localProductEditor');if(editor)editor.hidden=true;
  options();syncChoices();say('新任务已就绪，请拖入或选择图片。之前的结果仍保存在生成记录中。');
 };
})();

(()=>{
 const repeat=document.createElement('button');repeat.id='repeatProduct';repeat.hidden=true;
 repeat.textContent='再生成一张 · 上限 $0.27';$('generate').after(repeat);
 let busy=false;
 const update=()=>{repeat.hidden=job?.module!=='product-replacement'||job?.workflow!=='direct-generation'||!['generated-pending-review','mock-result'].includes(job?.state);repeat.disabled=busy||polling||session?.history?.some(s=>s.state==='running');};
 const oldDisplay=display;display=function(s){const ready=oldDisplay(s);update();return ready;};
 const oldOptions=options;options=function(){oldOptions();update();};
 repeat.onclick=async()=>{if(busy||repeat.disabled||repeat.hidden)return;busy=true;update();try{const next=await api('/api/product/repeat',{id:job.id});display(next);inputsLocked();await refreshSession();say('相同素材与设置的新任务已准备。点击“生成图片”才收费，上限 $0.27；不会自动提交或重试。');}catch(e){say('准备未完成：'+e.message+'；未自动生成，请查看记录。');}finally{busy=false;update();}};
 update();
})();
