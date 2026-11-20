'use strict';
// Offline internal orchestration. Consumes existing /api/freeze snapshots; never calls that API itself.
globalThis.ReferenceWorkflow=(()=>{
 const F=ProductCanvasFoundation,need=(v,m)=>{if(!v)throw Error(m);};
 const hashJSON=x=>F.sha(new Blob([JSON.stringify(x)]));
 const messages={
  'awaiting-assets':'等待经过核对的重构无字背景、布局和文案；未调用模型。',
  'awaiting-typography-review':'字形分割置信不足；可修改定位候选后重测，或审阅提取结果后继续。',
  'ready-to-compose':'离线输入已绑定，等待布局预检与合成。',
  'composing':'正在进行本地布局预检与合成。',
  'candidate':'内部候选已导出，尚未人工验收。',
  'accepted':'人工验收通过；仅代表此候选。',
  'rejected':'人工验收未通过，保留原始结果与原因。',
  'failed':'本地处理失败；未自动重试。',
  'interrupted':'上次本地处理被中断；没有自动重试。'
 };
 class Store {
  constructor(name='PictureOps.Internal.Reference.v1'){this.name=name;}
  async db(){if(this.handle)return this.handle;this.handle=await new Promise((yes,no)=>{const r=indexedDB.open(this.name,1);r.onupgradeneeded=()=>r.result.createObjectStore('tasks',{keyPath:'id'});r.onsuccess=()=>yes(r.result);r.onerror=()=>no(r.error);});return this.handle;}
  async read(id){const db=await this.db();return new Promise((yes,no)=>{const r=db.transaction('tasks').objectStore('tasks').get(id);r.onsuccess=()=>yes(r.result);r.onerror=()=>no(r.error);});}
  async list(){const db=await this.db();return new Promise((yes,no)=>{const r=db.transaction('tasks').objectStore('tasks').getAll();r.onsuccess=()=>yes(r.result.map(summary));r.onerror=()=>no(r.error);});}
  async write(record,revision){const db=await this.db();return new Promise((yes,no)=>{const tx=db.transaction('tasks','readwrite'),s=tx.objectStore('tasks'),r=s.get(record.id);let conflict=false;r.onsuccess=()=>{if((r.result?.revision??-1)!==revision){conflict=true;tx.abort();return;}s.put({...record,revision:revision+1});};tx.oncomplete=()=>yes(revision+1);tx.onabort=()=>no(Error(conflict?'历史已由另一个窗口更新，请重新打开。':'历史保存失败；未确认持久化。'));tx.onerror=()=>{};});}
  close(){this.handle?.close();this.handle=null;}
 }
 const summary=r=>({id:r.id,originalTaskId:r.frozen.id,state:r.state,message:messages[r.state],error:r.error||null,sourceHash:r.frozen.sourceHash,outputHash:r.outputHash||null,review:r.review||null,blockers:r.blockers,revision:r.revision,paidRequestsPaused:true,productionEnabled:false,fixtureOnly:r.fixtureOnly,legacyFindings:r.frozen.manualFindings||r.frozen.userFeedback||null});
 const blockers=o=>[
  {code:'RECONSTRUCTED_BACKGROUND',detail:'需要真正重构、无旧文字的背景，保持参考图主体/场景证据；不能直接复用带旧文案参考图。',provider:'人工或另行授权模型'},
  {code:'REVIEWED_LAYOUT',detail:`需要核对的文字角色、边界框、字号/字重/行距及分区布局（${o.layoutMode}）。由内部执行者提供，不新增用户坐标表单。`,provider:'人工或另行授权分析'},
  ...(o.mode==='remove-all-copy'?[]:[{code:'REVIEWED_COPY',detail:o.mode==='custom'?'按原始custom逐字分配文字角色，只允许必要换行。':'需要语义改写后的文案及事实核对，不能从参考图继承未提供参数。',provider:'人工或另行授权模型'}])
 ];
 class Workflow {
  #store;#r;#policy;#busy=false;
  constructor(store,record,policy){this.#store=store;this.#r=record;this.#policy=structuredClone(policy);}
  static async create({enabled=false,store,reference,frozen,policy,fixtureOnly=false}){
   need(store,'必须显式提供服务端存储；本地Store仅供离线夹具。');
   need(enabled,'internal feature disabled');need(frozen?.module==='reference-reconstruction'&&frozen.ruleTrace?.module==='reference-reconstruction','仅接收第一模块冻结记录。');
   need(reference instanceof Blob&&await F.sha(reference)===frozen.sourceHash,'参考图哈希不匹配。');
   const o=frozen.ruleTrace.selectedOptions;need(o&&['custom','ai-rewrite','remove-all-copy'].includes(o.mode),'缺少已冻结的表单选项。');
   need(Array.isArray(frozen.ruleTrace.expectedDimensions)&&frozen.ruleTrace.expectedDimensions.length===2,'缺少原生输出尺寸。');
   const record={id:crypto.randomUUID(),revision:-1,version:1,reference,frozen:structuredClone(frozen),frozenHash:await hashJSON(frozen),policyHash:await hashJSON(policy),state:'awaiting-assets',events:[],blockers:blockers(o),fixtureOnly};
   const w=new Workflow(store,record,policy);await w.#save('created');return w;
  }
  static async open({enabled=false,store,id,policy}){
   need(store,'必须显式提供服务端存储。');
   need(enabled,'internal feature disabled');const r=await store.read(id);need(r&&r.version===1,'内部历史不存在或版本不支持。');
   need(await hashJSON(r.frozen)===r.frozenHash&&await F.sha(r.reference)===r.frozen.sourceHash,'历史原图或冻结记录损坏；禁止合成。');
   need(await hashJSON(policy)===r.policyHash,'共享规则已变更；须新建候选，不静默替换历史规则。');
   if(r.assets){need(await F.sha(r.assets.background)===r.assets.backgroundHash&&await hashJSON(r.assets.plan)===r.assets.planHash,'历史背景或布局损坏。');}
   if(r.typographyEvidence)need(await hashJSON(r.typographyEvidence)===r.typographyEvidenceHash&&r.typographyEvidence.sourceHash===r.frozen.sourceHash,'字形证据损坏');
   if(r.output)need(await F.sha(r.output)===r.outputHash,'历史输出损坏；禁止下载。');
   const w=new Workflow(store,r,policy);if(r.state==='composing'){r.state='interrupted';r.error='本地处理未完成；请核对输入后重新提交素材包。';await w.#save('interrupted-on-open');}return w;
  }
  get status(){return structuredClone(summary(this.#r));}
  async #save(event){this.#r.events.push({event,at:new Date().toISOString()});try{this.#r.revision=await this.#store.write(this.#r,this.#r.revision);}catch(e){let saved;try{saved=await this.#store.read(this.#r.id);}catch(_){}if(saved)this.#r=saved;e.code='PERSISTENCE';throw e;}}
  async #exclusive(fn){need(!this.#busy,'操作正在进行，请勿重复提交。');this.#busy=true;try{return await fn();}finally{this.#busy=false;}}
  async supply({background,plan,evidence}){return this.#exclusive(async()=>{
   need(!['candidate','accepted','rejected'].includes(this.#r.state),'保留已有输出；修订请新建候选。');
   const bh=background instanceof Blob?await F.sha(background):null,ph=await hashJSON(plan);
   need(evidence?.sourceHash===this.#r.frozen.sourceHash&&evidence.backgroundHash===bh&&evidence.planHash===ph&&typeof evidence.reviewer==='string'&&evidence.reviewer.trim()&&typeof evidence.note==='string'&&evidence.note.trim(),'素材审核必须绑定原图、背景和布局哈希，并记录审核人/说明。');
   need(bh&&bh!==this.#r.frozen.sourceHash&&evidence.sceneReconstructed===true&&evidence.oldCopyAbsent===true&&evidence.layoutReviewed===true&&evidence.factsReviewed===true,'缺少重构背景/无旧字/布局/事实确认；不伪造自动识别。');
   need(Array.isArray(plan?.text),'缺少明确文字布局。');const o=this.#r.frozen.ruleTrace.selectedOptions;
   need(plan.text.every(t=>t.mode===o.mode&&['title','subtitle','body','brand'].includes(t.role)),'文字模式或角色与冻结表单冲突。');
   if(o.mode==='remove-all-copy')need(plan.text.length===0,'无字模式不能添加文字。');
   if(o.mode==='custom')need(plan.text.map(t=>t.text).join('')===o.customCopy,'custom必须逐字保持，角色拼接不可改词。');
   if(o.mode==='ai-rewrite')need(plan.text.length>0&&evidence.copyReviewed===true,'AI改写模式缺少已核对文案；内部路径不自动编造文案。');
   const b=await createImageBitmap(background),dims=this.#r.frozen.ruleTrace.expectedDimensions,match=b.width===dims[0]&&b.height===dims[1];b.close();need(match,'背景尺寸不匹配；不自动裁切或拉伸。');
   this.#r.typographyEvidence=null;this.#r.typographyEvidenceHash=null;this.#r.assets={background,backgroundHash:bh,plan:structuredClone(plan),planHash:ph,evidence:structuredClone(evidence)};this.#r.error=null;this.#r.state='ready-to-compose';this.#r.blockers=[];await this.#save('reviewed-package-supplied');return this.status;
  });}
  async #measureTypography(candidates){
   need(globalThis.ReferenceInkEvidence,'本地字形提取器未加载');
   const evidence=await ReferenceInkEvidence.extract(this.#r.reference,candidates);
   need(evidence.sourceHash===this.#r.frozen.sourceHash,'字形证据源图不匹配');
   this.#r.typographyEvidence=evidence;this.#r.typographyEvidenceHash=await hashJSON(evidence);
   this.#r.state=evidence.state==='measured'?'ready-to-compose':'awaiting-typography-review';
   await this.#save('reference-ink-measured');return this.status;
  }
  async measureTypography(candidates){return this.#exclusive(async()=>{
   need(['ready-to-compose','awaiting-typography-review'].includes(this.#r.state),'先提供已核对素材');
   return this.#measureTypography(candidates);
  });}
  async reviewTypography({reviewer,note}){return this.#exclusive(async()=>{
   need(this.#r.state==='awaiting-typography-review'&&reviewer?.trim()&&note?.trim(),'需要明确字形审阅');
   const e=this.#r.typographyEvidence;
   need(e?.roles.every(r=>r.lines.length===r.sourceText.split('\n').length&&r.lines.length>0&&r.lines.every(l=>l.sourceText.trim()&&l.height>0&&l.width>0)),'未检测到完整逐行字形；调整候选区域后重新测量');
   e.roles.forEach(r=>r.lines.forEach(l=>l.measurementKind='reviewed-visible-ink'));
   e.anchors=e.roles.flatMap(r=>r.lines);e.review={reviewer,note};e.state='reviewed';this.#r.typographyEvidenceHash=await hashJSON(e);this.#r.state='ready-to-compose';await this.#save('reference-ink-reviewed');return this.status;
  });}
  async compose(){return this.#exclusive(async()=>{
   need(this.#r.state==='ready-to-compose','素材未就绪或已有结果；不自动重试。');
   if(this.#r.frozen.ruleTrace.selectedOptions.layoutMode==='keep-reference'&&this.#r.assets.plan.text.length&&!this.#r.typographyEvidence&&!this.#r.assets.plan.typographyEvidence){
    const plan=this.#r.assets.plan,blocks=plan.evidence?.sourceBlocks;
    if(blocks?.length===plan.text.length&&blocks.every(b=>b.sourceBox))await this.#measureTypography(blocks.map((b,i)=>({sourceText:b.sourceText,role:plan.text[i].role,box:b.sourceBox})));
    else{this.#r.state='awaiting-typography-review';this.#r.blockers=[{code:'SOURCE_TEXT_REGIONS',detail:'缺少原图文字定位候选；可补入候选后重测，不调用模型。'}];await this.#save('reference-regions-required');}
    if(this.#r.state==='awaiting-typography-review')return this.status;
   }
   this.#r.state='composing';await this.#save('composition-started');
   try{
    const a=this.#r.assets,[width,height]=this.#r.frozen.ruleTrace.expectedDimensions;
    let renderText=a.plan.text,inheritance=null;
    if(this.#r.frozen.ruleTrace.selectedOptions.layoutMode==='keep-reference'&&renderText.length){
     const evidence=this.#r.typographyEvidence||a.plan.typographyEvidence;
     need(evidence&&evidence.sourceHash===this.#r.frozen.sourceHash&&Array.isArray(evidence.anchors)&&(evidence.roles?evidence.roles.length===renderText.length:evidence.anchors.length===renderText.length),'参考可见字高测量缺失；不能用模型字号或框高冒充已继承');
     need(globalThis.ReferenceTypeScale,'参考字形继承引擎未加载');
     const source=await createImageBitmap(this.#r.reference),dimensions={sourceWidth:source.width,sourceHeight:source.height,width,height,policy:this.#policy};source.close();
     if(this.#r.typographyEvidence)need(await hashJSON(evidence)===this.#r.typographyEvidenceHash&&evidence.sourceWidth===dimensions.sourceWidth&&evidence.sourceHeight===dimensions.sourceHeight,'字形证据绑定失效');
     need(evidence.anchors.every(x=>x.sourceHash===this.#r.frozen.sourceHash),'字形测量来源不匹配');
     const measured=evidence.roles?ReferenceTypeScale.fitRoles(renderText,evidence,dimensions):{fits:renderText.map((t,i)=>ReferenceTypeScale.fit(t,evidence.anchors[i],dimensions)),anchors:evidence.anchors};
     const fitted=measured.fits;renderText=fitted.map(x=>x.text);
     inheritance={fits:fitted.map(x=>x.audit),group:ReferenceTypeScale.validateGroup(renderText,measured.anchors,dimensions,this.#policy)};
    }
    const plans=renderText.map(t=>InterTextFoundation.layout(t,this.#policy,F.copyText));
    for(const p of plans){const b=p.box;need(b.x>=0&&b.y>=0&&b.x+b.width<=width&&b.y+b.height<=height,'文字越界；请执行者修正布局。');}
    const c=document.createElement('canvas');c.width=width;c.height=height;const ctx=c.getContext('2d'),bg=await createImageBitmap(a.background);ctx.drawImage(bg,0,0);bg.close();plans.forEach(p=>InterTextFoundation.draw(ctx,p));
    const blob=await new Promise((yes,no)=>c.toBlob(b=>b?yes(b):no(Error('PNG导出失败。')),'image/png'));
    this.#r.output=blob;this.#r.outputHash=await F.sha(blob);this.#r.state='candidate';this.#r.manifest={sourceHash:this.#r.frozen.sourceHash,backgroundHash:a.backgroundHash,planHash:a.planHash,outputHash:this.#r.outputHash,textPlans:plans,inheritance,width,height,fixtureOnly:this.#r.fixtureOnly,visualAcceptance:'not-evaluated',modelCalls:0};await this.#save('candidate-exported');return this.status;
   }catch(e){if(e.code==='PERSISTENCE')throw e;this.#r.output=null;this.#r.outputHash=null;this.#r.state='failed';this.#r.error=e.message;await this.#save('local-failure');throw e;}
  });}
  async review({verdict,note,reviewer}){return this.#exclusive(async()=>{need(this.#r.state==='candidate'&&['accepted','rejected'].includes(verdict)&&note?.trim()&&reviewer?.trim(),'需要候选和明确人工验收说明。');this.#r.review={verdict,note,reviewer,outputHash:this.#r.outputHash};this.#r.state=verdict;await this.#save('manual-review');return this.status;});}
  async download(){return this.#exclusive(async()=>{need(['candidate','accepted','rejected'].includes(this.#r.state)&&this.#r.output,'没有真实输出可下载。');if(this.#store.download)await this.#store.download(this.#r.id,this.#r.outputHash);else await F.download({blob:this.#r.output,manifest:{outputHash:this.#r.outputHash}},`INTERNAL-reference-${this.#r.id}.png`);await this.#save('download-dispatched');});}
  record(){const r=structuredClone(this.#r);delete r.reference;delete r.output;if(r.assets)delete r.assets.background;return r;}
 }
 return Object.freeze({Workflow,Store,hashJSON,productionEnabled:false});
})();
