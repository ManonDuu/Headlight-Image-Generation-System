'use strict';
(()=>{
 let preparing=false;
 let originalSourceHash=null;
 const originalField=document.createElement('label');originalField.className='field';originalField.hidden=true;
 originalField.textContent='核对参考图原文';
 const originalInput=document.createElement('textarea');originalInput.id='referenceCopyFallback';originalInput.rows=4;originalInput.placeholder='逐字粘贴参考图全部文字，保留大小写和标点';
 originalField.append(originalInput);$('optionNote').after(originalField);
 const priorRequest=businessRequest;
 businessRequest=function(){const d=priorRequest();if(d.module==='reference-reconstruction'&&d.mode==='preserve-reference'&&originalSourceHash===ref?.hash&&originalInput.value.trim())d.referenceCopy=originalInput.value;return d;};
 const priorNewTask=newTask.onclick;
 newTask.onclick=async()=>{if(polling||job?.state==='running')return priorNewTask();originalSourceHash=null;originalInput.value='';originalField.hidden=true;await priorNewTask();};
 const priorFreeze=$('freeze').onclick;
 $('freeze').onclick=async()=>{
  if($('module').value!=='reference-reconstruction')return priorFreeze();
  if(preparing||job||$('freeze').disabled)return;
  preparing=true;$('freeze').disabled=true;
  try{
   pendingOptions=businessRequest();
   const frozen=await api('/api/freeze',pendingOptions);
   display(frozen);
   if(frozen.state==='frozen'){
    inputsLocked();
    ['brandName','productSpecs','layout','color'].forEach(id=>$(id).disabled=true);
   }
   await refreshSession();
  }catch(e){
   if(!job&&$('mode').value==='preserve-reference'&&/文字提取不可用|低置信文字/.test(e.message)){originalSourceHash=ref?.hash;originalField.hidden=false;originalInput.disabled=false;}
   say(job?'任务已保存，但页面刷新失败；请从生成记录查看，勿重复提交。':'准备停止：'+e.message+'；未发送生图请求。');
   if(!job)$('freeze').hidden=false;
  }finally{preparing=false;options();}
 };
 const priorOptions=options;
 options=function(){priorOptions();if($('module').value==='reference-reconstruction'){
  $('moduleNote').textContent='学习参考图卖点与大致表现形式，按所选文案、排版、配色和比例重新设计。';
  $('session').textContent=session?.mock?'模拟模式':session?.referenceDaily?.enabled?'已连接':'';
  $('generate').textContent='生成图片 · 上限 $0.26';
  const productEditor=document.getElementById('localProductEditor');if(productEditor)productEditor.hidden=true;
  $('freeze').textContent='准备本次生成';
  const mode=$('mode').value;
  $('optionNote').textContent=mode==='preserve-reference'?'保留原文与大小写。':mode==='custom'?'请填写全部需要显示的文字。':mode==='remove-all-copy'?'不添加文字和标签。':'根据原图卖点改写文案。';
  if(preparing)$('freeze').disabled=true;
  if(job)['brandName','productSpecs','layout','color'].forEach(id=>$(id).disabled=true);
  if(originalSourceHash&&ref?.hash!==originalSourceHash){originalSourceHash=null;originalInput.value='';originalField.hidden=true;}
  if($('mode').value!=='preserve-reference')originalField.hidden=true;
  else if(originalInput.value)originalField.hidden=false;
  if(job){originalSourceHash=job.sourceHash;originalInput.value=job.rawUserOptions?.referenceCopy||'';originalInput.disabled=true;if(originalInput.value)originalField.hidden=false;}
 }};
 options();
})();
// Direct-generation records are tasks/results, not old layered preparations.
(()=>{
 const previousLoad=$('load').onclick;
 $('load').onclick=async()=>{
  const id=$('history').value;if(!id)return;
  let saved;try{saved=await api('/api/task/'+id);}catch(e){say(e.message);return;}
  if(saved.module!=='reference-reconstruction'||saved.workflow!=='direct-generation')return previousLoad();
  try{
   if(polling||job?.state==='running')throw Error('当前任务仍在运行');
   const reference=await readOriginalImage(await blob('/api/task/'+id+'/reference'));
   if(reference.hash!==saved.sourceHash)throw Error('原始参考图校验失败');
   await newTask.onclick();ref=reference;productRef=null;
   await enterModule(saved.module,false);
   $('reference').src=ref.data;$('reference').hidden=false;$('sourceThumb').src=ref.data;
   $('sourceSelected').hidden=false;$('uploadBox').hidden=true;$('sourceName').textContent='已保存的原始参考图';
   await showResult(saved);inputsLocked();options();syncChoices();
   $('historyPanel').hidden=true;
   if(saved.state==='running')await poll();
  }catch(e){say('恢复停止：'+e.message);}
 };
})();

// Keep mock mode explicit after polling and session refreshes too.
(()=>{
 const previousRefresh=refreshSession;
 refreshSession=async()=>{await previousRefresh();options();};
 const previousDisplay=display;
 display=function(record){const ready=previousDisplay(record);if(session?.mock&&record.module==='reference-reconstruction'&&record.state==='frozen')$('generate').textContent='模拟生成一次 · 免费';return ready;};
})();
