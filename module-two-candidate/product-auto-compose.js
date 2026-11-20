'use strict';
// Cached/prepared assets -> deterministic original-product composition, no model calls.
globalThis.ProductAutoCompose=(()=>{
 const F=ProductCanvasFoundation,L=LocalProductCompose;
 const decode=a=>new Blob([Uint8Array.from(atob(a.base64),c=>c.charCodeAt(0))],{type:a.mime});
 function soften(asset){if(asset.origin==='original-alpha')return 0;const n=asset.alpha.length,w=asset.c.width,h=asset.c.height,old=asset.alpha.slice(),d=asset.original.data;let count=0;
  // Only the one-pixel near-white contour loses coverage; retained RGB is never repainted.
  for(let y=1;y<h-1;y++)for(let x=1;x<w-1;x++){const i=y*w+x;if(old[i]===255&&[i-1,i+1,i-w,i+w].some(k=>old[k]===0)){const lo=Math.min(d[4*i],d[4*i+1],d[4*i+2]),hi=Math.max(d[4*i],d[4*i+1],d[4*i+2]);if(lo>225&&hi-lo<20){asset.alpha[i]=Math.round(255*(255-lo)/30);count++;}}}
  const ctx=asset.mask.getContext('2d'),m=ctx.getImageData(0,0,w,h);for(let i=0;i<n;i++)m.data[4*i+3]=asset.alpha[i];ctx.putImageData(m,0,0);return count;
 }
 function slotFor(plan,w,h,pw,ph){if(plan.productSlot)return plan.productSlot;
  const boxes=plan.layout.text.map(t=>t.box),margin=Math.min(w,h)*.035;h=Math.min(h,plan.defaultProductBottom||h);
  for(let scale=Math.min((w-2*margin)/pw,(h-2*margin)/ph);scale>.02;scale*=.94){const width=pw*scale,height=ph*scale,xs=[margin,(w-width)/2,w-margin-width,...boxes.map(b=>b.x+b.width+margin)],ys=[margin,(h-height)/2,h-margin-height,...boxes.map(b=>b.y+b.height+margin)];
   for(const y of ys)for(const x of xs)if(x>=margin&&y>=margin&&x+width<=w-margin&&y+height<=h-margin&&boxes.every(b=>x+width<=b.x-margin||x>=b.x+b.width+margin||y+height<=b.y-margin||y>=b.y+b.height+margin))return {x,y,width,height};
  }throw Error('排版没有可容纳原产品的空间，需要修正生成前布局');
 }
 function contactShadow(asset,w,h,x,y,scale){
  const pw=asset.c.width,ph=asset.c.height,d=asset.original.data;
  const visible=F.visibleBounds(asset.original,asset.alpha),bottom=visible.y+visible.height-1;let left=pw,right=-1;
  const opaque=i=>Math.round(asset.alpha[i]*d[i*4+3]/255)>0;
  for(let v=Math.max(visible.y,bottom-Math.ceil(visible.height*.025));v<=bottom;v++)for(let u=visible.x;u<visible.x+visible.width;u++)if(opaque(v*pw+u)){left=Math.min(left,u);right=Math.max(right,u);}
  const layer=L.canvas(w,h),ctx=layer.getContext('2d'),cx=x+(left+right+1)*scale/2,cy=y+(bottom+1)*scale;
  const rx=Math.max(2,(right-left+1)*scale*.56),ry=Math.max(2,rx*.085);
  ctx.save();ctx.translate(cx,cy);ctx.scale(rx,ry);const g=ctx.createRadialGradient(0,0,0,0,0,1);g.addColorStop(0,'rgba(0,0,0,.28)');g.addColorStop(.4,'rgba(0,0,0,.17)');g.addColorStop(1,'rgba(0,0,0,0)');ctx.fillStyle=g;ctx.beginPath();ctx.arc(0,0,1,0,Math.PI*2);ctx.fill();ctx.restore();
  return {layer,bounds:{cx,cy,rx,ry},method:'visible-alpha-bottom-contact'};
 }
 async function compose({source,reference,referenceHash,options,package:pkg}){
  if(!reference||await F.sha(reference)!==referenceHash)throw Error('参考图校验失败');
  if(pkg.sourceHash!==referenceHash||pkg.productHash!==(source?await F.sha(source):null)||JSON.stringify(pkg.options)!==JSON.stringify(options))throw Error('缓存与当前图片或规则不一致');
  let bg=decode(pkg.background);
  if(pkg.decoration){const d=pkg.decoration,r=await DeterministicDecoration.render({contract:d.contract,layout:pkg.proposal.layout,sourceHash:referenceHash,assets:Object.fromEntries(Object.entries(d.assets).map(([id,a])=>[id,decode(a)]))});if(r.contractHash!==d.contractHash||r.backgroundHash!==pkg.backgroundHash)throw Error('Decoration output binding mismatch');bg=r.blob;}if(await F.sha(bg)!==pkg.backgroundHash)throw Error('背景校验失败');
  const asset=source?await L.prepare(source):null;if(asset&&asset.origin!=='original-alpha'&&asset.removed<asset.alpha.length*.01)throw Error('无法可靠自动分离此产品；请换同一产品的透明PNG。');
  const softened=asset?soften(asset):0,bitmap=await createImageBitmap(bg),w=bitmap.width,h=bitmap.height;const sourceImage=await createImageBitmap(reference),relations=ReferenceLayoutAnchors.analyze(sourceImage,bitmap);sourceImage.close();bitmap.close();
  const geometryAudit=pkg.proposal.layout.text.length?await requireBackgroundGeometry(pkg,referenceHash,w,h):null;
  const plan=structuredClone(pkg.proposal);
  const completenessAudit=requireCompleteCopy(plan,options);
  if(plan.sourceProductGeometry&&(!pkg.anchorAudit?.productGeometryHash||await DeterministicDecoration.hash(plan.sourceProductGeometry)!==pkg.anchorAudit.productGeometryHash))throw Error('主体占比复核绑定变化');
  if(pkg.decoration)CopyLayoutContract.labelCoverage(pkg.decoration.contract.labelContainers,plan.layout.text);
  // Imported test backgrounds can have a different raster size. Transform
  // explicitly declared layout coordinates uniformly, never guess their units.
  mapLayout(plan,pkg.layoutCanvasDimensions,w,h);
  if(asset&&options.layoutMode==='keep-reference'&&!plan.productSlot){
   let label=0;for(const t of plan.layout.text){const idx=t.role==='title'?0:t.role==='subtitle'?1:-1,hb=idx>=0?relations.sourceHeadings[idx]:null,band=idx<0?relations.outputBands[label++]:null;
    if(hb){const sourceW=plan.layout.sourceGeometry.width,sourceH=plan.layout.sourceGeometry.height;t.box={x:w*.04,y:hb.y/sourceH*h,width:w*.92,height:hb.height/sourceH*h*1.2};t.align='center';t.fontSize=Math.min(256,t.box.height*.94);t.lineHeightPx=t.fontSize*1.2;}
    else if(band){t.box={x:band.x+band.width*.06,y:band.y+band.height*.22,width:band.width*.88,height:band.height*.58};t.align='center';t.fontSize=Math.min(256,band.height*.55);t.lineHeightPx=t.fontSize*1.2;}
   }
  }
  if(!plan.productSlot&&relations.outputBands.length===2&&/\bLED\b/i.test(options.productName||'')&&plan.layout.text.some(t=>/halogen/i.test(t.text))){const led=plan.layout.text.find(t=>/^LED(?: Light)?$/i.test(t.text));if(led)plan.defaultProductBottom=led.box.y;}
  const visible=asset?F.visibleBounds(asset.original,asset.alpha):null;
  const slot=asset?slotFor(plan,w,h,visible.width,visible.height):null;
  const placement=asset?(plan.sourceProductGeometry?fitReferenceBody(visible,plan.sourceProductGeometry,referenceHash,w,h):fitVisible(visible,slot)):{scale:1,x:0,y:0}, {scale,x,y}=placement;
  const policy={forbiddenSource:'headlights?',modes:{}};policy.modes[options.mode]={title:'Title Case',subtitle:'Sentence case',brand:'UPPERCASE'};
  const text=options.mode==='remove-all-copy'?[]:plan.layout.text;
  if(options.mode==='custom'&&text.map(t=>t.text).join('')!==options.customCopy)throw Error('自填文案必须原样保留');
  if(options.mode==='ai-rewrite'&&text.some(t=>t.role==='brand'&&t.text.toLowerCase()!==(options.brandName||'').trim().toLowerCase()))throw Error('未授权品牌');
  // Render-contract provenance is checked by the Ruby adapter; local host rechecks output safety.
  for(const t of text){if(t.presentation&&t.presentation.sourceHash!==referenceHash)throw Error('文字透视样式缺少当前源图绑定');t.mode=options.mode;if(/headlights?/i.test(t.text))throw Error('禁用文案');if(options.layoutTone==='adjust-color')Object.assign(t,TextPresentation.palette(t,options.color));}
  if(!InterTextFoundation.ready)await InterTextFoundation.load({normal:await (await fetch('/fonts/InterVariable.ttf')).blob(),italic:await (await fetch('/fonts/InterVariable-Italic.ttf')).blob()});
  const anchorAudit=options.layoutMode==='keep-reference'&&text.length?await applyTrustedAnchors(plan,pkg.proposal.layout,pkg.anchorAudit,reference,referenceHash,w,h,policy):null;
  const layoutAudit=prepareText(text,{width:w,height:h,mode:options.layoutMode,productSlot:plan.sourceProductGeometry?null:plan.productSlot,policy});
  if(geometryAudit)await requireBackgroundGeometry(pkg,referenceHash,w,h,plan.layout);
  if(pkg.decoration)DeterministicDecoration.checkGlyphs(pkg.decoration.contract,text.map(t=>InterTextFoundation.layout(t,policy,F.copyText)));
  if(!asset){
   const canvas=L.canvas(w,h),ctx=canvas.getContext('2d'),back=await createImageBitmap(bg);ctx.drawImage(back,0,0);back.close();
   const textPlans=text.map(t=>InterTextFoundation.layout(t,policy,F.copyText));
   for(const p of textPlans){if(p.box.x<0||p.box.y<0||p.box.x+p.box.width>w||p.box.y+p.box.height>h)throw Error('文字超出画布');InterTextFoundation.draw(ctx,p);}
   const blob=await L.png(canvas);return {blob,manifest:{workflow:'automatic-reference-local-text',sourceHash:referenceHash,backgroundHash:pkg.backgroundHash,outputHash:await F.sha(blob),width:w,height:h,textPlans,interReady:InterTextFoundation.ready,preparedLayout:plan.layout,layoutAudit,anchorAudit,geometryAudit,decorationContractHash:pkg.decoration?.contractHash||null,sceneReview:pkg.decorationReview||null,selectedOptions:options,newModelCalls:0,fixtureOnly:!!pkg.fixtureOnly,backgroundOrigin:pkg.backgroundTestSource||pkg.backgroundOrigin,visualAcceptance:'not-evaluated',warnings:[...(pkg.decorationReview?.limitations||[])]}};
  }
  const shadow=contactShadow(asset,w,h,x,y,scale);
  const mask=await L.png(asset.mask),s=new F.Session({enabled:true,policy});await s.load(source,{sourceHash:asset.sourceHash,mask,maskHash:await F.sha(mask)});s.transform({x,y,scale,rotation:0});await s.layers({background:bg,shadow:shadow.layer,backgroundConfirmedClean:true,text});const result=await s.exportPNG({width:w,height:h});
  Object.assign(result.manifest,{contactShadow:{method:shadow.method,bounds:shadow.bounds,layer:'behind-original-product'},unresolvedWhitePixels:asset.unresolvedWhitePixels,transparentPNGRecommended:asset.unresolvedWhitePixels>0});
  Object.assign(result.manifest,{workflow:'automatic-original-product',sourceHash:referenceHash,productHash:asset.sourceHash,backgroundHash:pkg.backgroundHash,sourcePixelsReused:true,automaticMask:asset.origin,alphaOnlyContourPixels:softened,productSlot:slot,preparedLayout:plan.layout,layoutAudit,anchorAudit,geometryAudit,visibleSourceBounds:visible,placementRule:'visible-alpha-uniform-bottom-anchor',decorationContractHash:pkg.decoration?.contractHash||null,sceneReview:pkg.decorationReview||null,selectedOptions:options,newModelCalls:0,visualAcceptance:'not-evaluated',fixtureOnly:!!pkg.fixtureOnly,warnings:[...(pkg.decorationReview?.limitations||[]),...(asset.origin==='original-alpha'?[]:['白底自动遮罩仍可能有白边、孔洞残白或银色边缘损失；结果可直接下载，修正为可选。']),...(options.mode==='preserve-reference'?(pkg.proposal.warnings||[]).flatMap(a=>(a.changes||[]).map(c=>c.action==='omit'?'原文处理：'+c.sourceText+'；'+c.reason:c.action==='brand-replacement'?'品牌替换：'+c.from+' → '+c.to:c.action==='copy-exception'?'原文具体例外：'+c.sourceText+'；'+c.reason:'')).filter(Boolean):[])]});return result;
 }
 async function requireBackgroundGeometry(pkg,sourceHash,w,h,renderedLayout=null){
  const fail=()=>{throw Error('背景面板或标签位置尚未通过几何复核，已停止叠字；不会自动移动文字、拉伸面板或覆盖双框。');};
  const canonical=v=>Array.isArray(v)?v.map(canonical):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])])):v;
  const layout=pkg.proposal.layout,a=pkg.geometryAudit,hash=await F.sha(new Blob([JSON.stringify(canonical(layout))]));
  if(!a||a.sourceHash!==sourceHash||a.backgroundHash!==pkg.backgroundHash||a.layoutHash!==hash||JSON.stringify(a.outputSize)!==JSON.stringify([w,h])||a.reviewState!=='verified-local-review'||a.verdict!=='pass'||a.reviewMethod!=='manual-pixel-geometry'||a.sourceStructureReviewed!==true||a.backgroundStructureReviewed!==true||a.inventoryComplete!==true||!Array.isArray(a.regions)||!Array.isArray(a.textOwners))fail();
  const panelCount=a.regions.filter(r=>r.kind==='panel').length;if(a.sourcePanelCount!==panelCount||a.backgroundPanelCount!==panelCount||a.regions.some(r=>typeof r.id!=='string'||!r.id))fail();
  if(a.structure==='unframed'){if(a.regions.length||a.textOwners.length||a.unframedClearanceReviewed!==true)fail();return a;}
  if(a.structure!=='framed'||!a.regions.some(r=>r.kind==='panel')||new Set(a.regions.map(r=>r.id)).size!==a.regions.length)fail();
  const edges=e=>e&&Object.keys(e).sort().join(',')==='bottom,left,right,top'&&Object.entries(e).every(([k,v])=>Array.isArray(v)&&v.length===2&&v.every(Number.isFinite)&&v[0]>=0&&v[0]<=v[1]&&v[1]<=(['left','right'].includes(k)?w:h))&&e.left[1]<e.right[0]&&e.top[1]<e.bottom[0];
  for(const r of a.regions){const e=r.expectedEdges,o=r.observedEdges;if(!['panel','container','header'].includes(r.kind)||r.measurementState!=='reviewed'||!edges(e)||!edges(o)||['left','top','right','bottom'].some(k=>Math.max(e[k][0],o[k][0])>Math.min(e[k][1],o[k][1])))fail();}
  if(a.textOwners.length!==layout.text.length||new Set(a.textOwners.map(o=>o.renderIndex)).size!==layout.text.length)fail();
  for(const o of a.textOwners){const r=a.regions.find(r=>r.id===o.regionId),t=(renderedLayout||layout).text[o.renderIndex],e=r?.observedEdges,b=t?.box;if(!Number.isInteger(o.renderIndex)||!b||!e||o.ownershipReviewed!==true)fail();if(renderedLayout&&(b.x<e.left[1]||b.y<e.top[1]||b.x+b.width>e.right[0]||b.y+b.height>e.bottom[0]))fail();}
  return a;
 }
 async function applyTrustedAnchors(plan,originalLayout,audit,reference,sourceHash,w,h,policy){
  const canonical=v=>Array.isArray(v)?v.map(canonical):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])])):v;
  const layoutHash=await F.sha(new Blob([JSON.stringify(canonical(originalLayout))]));
  if(!audit||audit.sourceHash!==sourceHash||audit.layoutHash!==layoutHash||audit.reviewState!=='verified-local-review'||audit.semanticReview!=='reviewed')throw Error('保留参考排版尚缺可信锚点复核；不会切换排版模式');
  if(audit.evidencePolicy==='reviewed-reflow-v1'){
   if(!audit.sourcePixelsReviewed||!audit.renderPixelsReviewed||JSON.stringify(audit.sourceElementIds)!==JSON.stringify(originalLayout.evidence.sourceBlocks.map(b=>b.id))||await DeterministicDecoration.hash(audit.nativeLayout)!==layoutHash||audit.glyphs?.length!==plan.layout.text.length)throw Error('重排布局像素复核绑定失效');
   for(let i=0;i<plan.layout.text.length;i++){const t=plan.layout.text[i],q=InterTextFoundation.layout(t,policy,F.copyText),g=audit.glyphs[i];if(q.text!==g.text||q.metrics.some((m,j)=>!Number.isFinite(g.widths[j])||Math.abs(m.width-g.widths[j])>0.1))throw Error('重排字形测量变化');}
   return {method:'reviewed-reflow-v1',sourceHash,layoutHash};
  }
  const blocks=originalLayout.evidence?.sourceBlocks||[],observed=audit.sourceBlocks||[],anchors=audit.renderAnchors||[];
  const rewrites=originalLayout.evidence?.rewrites||[];
  const clearance=(o,b)=>{const r=rewrites.filter(r=>r.blockId===b.id),q=o.clearanceBox,size=audit.sourceSize;
   return r.length===1&&r[0].action==='omit'&&r[0].renderIndex===-1&&r[0].omissionReason?.trim()&&o.outputAction==='omit'&&o.clearanceReview==='reviewed'&&o.sourceRecognitionReview==='manual-pixel-verified'&&o.recognizedSourceText===b.sourceText&&o.omissionReason===r[0].omissionReason&&!anchors.some(a=>a.blockId===b.id)&&q&&size?.length===2&&['x','y','width','height'].every(k=>Number.isFinite(q[k]))&&q.x>=0&&q.y>=0&&q.width>0&&q.height>0&&q.x+q.width<=size[0]&&q.y+q.height<=size[1];};
  if(observed.length!==blocks.length||blocks.some(b=>{const found=observed.filter(o=>o.id===b.id);return found.length!==1||found[0].sourceText!==b.sourceText||!(found[0].state==='reviewed-clearance-region'?clearance(found[0],b):found[0].matches===1&&found[0].state==='unique-ocr-phrase-anchor-candidate');})||anchors.length!==plan.layout.text.length||anchors.some((a)=>!Number.isInteger(a.renderIndex)||a.renderIndex<0||a.renderIndex>=plan.layout.text.length)||new Set(anchors.map(a=>a.renderIndex)).size!==anchors.length||anchors.some(a=>a.semanticState!=='reviewed'||a.glyphState!=='measured'))throw Error('锚点错读、重复、缺失或语义待定；停止保留排版');
  if(audit.evidencePolicy==='retained-and-clearance-v1'&&(rewrites.length!==blocks.length||blocks.some(b=>rewrites.filter(r=>r.blockId===b.id).length!==1)||rewrites.some(r=>!['render','omit'].includes(r.action))||rewrites.filter(r=>r.action==='render').length!==anchors.length||anchors.some(a=>!rewrites.some(r=>r.blockId===a.blockId&&r.action==='render'&&r.renderIndex===a.renderIndex)||!observed.some(o=>o.id===a.blockId&&o.state==='unique-ocr-phrase-anchor-candidate'))))throw Error('保留文字与清除区域关联不一致');
  if(audit.evidencePolicy==='retained-and-clearance-v1'&&anchors.some(a=>{const o=observed.find(o=>o.id===a.blockId),c=a.candidate,t=plan.layout.text[a.renderIndex];return !o||!c||c.sourceText!==o.sourceText||c.role!==t.role||!Array.isArray(a.measuredLines)||a.measuredLines.length!==c.sourceText.split('\n').length||a.measuredLines.some((l,i)=>l.sourceText!==c.sourceText.split('\n')[i]);}))throw Error('保留字形与源文字关联变化');
  const ordered=[...anchors].sort((a,b)=>a.renderIndex-b.renderIndex),measured=await ReferenceInkEvidence.extract(reference,ordered.map(a=>a.candidate));
  if(measured.sourceWidth!==audit.sourceSize[0]||measured.sourceHeight!==audit.sourceSize[1]||measured.roles.some((r,i)=>r.state!=='measured'&&!(ordered[i].measurementReview?.state==='reviewed-source-pixels'&&ordered[i].measurementReview.measurementState===r.state&&JSON.stringify(ordered[i].measurementReview.reasons)===JSON.stringify(r.reasons)&&r.lines.length>0)))throw Error('源图字形测量未通过，保留排版停止');
  const k=Math.min(w/measured.sourceWidth,h/measured.sourceHeight),dx=(w-measured.sourceWidth*k)/2,dy=(h-measured.sourceHeight*k)/2,changes=[];
  for(let i=0;i<ordered.length;i++){
   const role=measured.roles[i],expected=ordered[i].measuredLines,t=plan.layout.text[i];
   if(!Array.isArray(expected)||role.lines.length!==expected.length||role.lines.some((l,j)=>['x','y','width','height'].some(key=>Math.abs(l[key]-expected[j][key])>1)))throw Error('字形测量与复核记录不一致');
   const lines=role.lines,renderLines=t.text.split('\n'),sourceLines=ordered[i].candidate.sourceText.split('\n');
   if(lines.length!==renderLines.length||lines.length!==sourceLines.length||lines.length>1&&(ordered[i].lineMappingReview!=='reviewed'||sourceLines.some((line,j)=>line!==renderLines[j])))throw Error('多行角色对应尚未通过可信锚点复核');
   const ink={x:Math.min(...lines.map(l=>l.x)),y:lines[0].y,width:Math.max(...lines.map(l=>l.x+l.width))-Math.min(...lines.map(l=>l.x)),height:Math.max(...lines.map(l=>l.height))};
   const gaps=lines.slice(1).map((l,j)=>l.y-lines[j].y);
   if(lines.some(l=>Math.abs(l.x-ink.x)>ink.height*.12||Math.abs(l.height-ink.height)>ink.height*.12)||gaps.some(g=>g<=ink.height||Math.abs(g-gaps[0])>ink.height*.08))throw Error('多行字形大小、左边界或行距不一致，需要独立复核');
   const targetHeight=ink.height*k,box={x:dx+ink.x*k,y:dy+ink.y*k,width:ink.width*k,height:targetHeight*1.2+(gaps.length?gaps[0]*k*(lines.length-1):0)};
   const probe={...t,fontSize:100,lineHeightPx:140,box:{x:0,y:0,width:100000,height:100000}},metrics=InterTextFoundation.layout(probe,policy,F.copyText),glyphHeight=Math.max(...metrics.metrics.map(m=>m.ascent))+Math.max(...metrics.metrics.map(m=>m.descent));
   t.fontSize=Math.min(256,100*targetHeight/glyphHeight);t.lineHeightPx=gaps.length?gaps[0]*k:t.fontSize*1.25;t.box=box;
   changes.push({renderIndex:i,sourceInk:ink,targetInkHeight:targetHeight,mappedBox:box,lineCount:lines.length,sourceLineGap:gaps[0]||null,sourceRoleReviewed:true});
  }
  return {sourceHash,layoutHash,method:'local-ocr-plus-remeasured-source-ink',semanticReview:'reviewed-for-bound-source-and-layout',scale:k,changes,automaticGeneralSemanticDetection:false};
 }
 // Render coordinates have their own declared canvas. Source evidence never
 // supplies render units; an in-bounds model box is not verified localization.
 function mapLayout(plan,dimensions,w,h){
  if(!dimensions)return {mapped:false,units:'native-output-pixels'};
  if(!Array.isArray(dimensions)||dimensions.length!==2||!dimensions.every(n=>Number.isFinite(n)&&n>0))throw Error('布局画布尺寸无效');
  const [lw,lh]=dimensions,k=Math.min(w/lw,h/lh),dx=(w-lw*k)/2,dy=(h-lh*k)/2;
  const box=b=>{if(!b||!['x','y','width','height'].every(n=>Number.isFinite(b[n]))||b.x<0||b.y<0||b.width<=0||b.height<=0||b.x+b.width>lw+1e-6||b.y+b.height>lh+1e-6)throw Error('布局框超出声明画布，不能猜测坐标单位');return {x:b.x*k+dx,y:b.y*k+dy,width:b.width*k,height:b.height*k};};
  if(plan.productSlot)plan.productSlot=box(plan.productSlot);
  for(const t of plan.layout.text){t.box=box(t.box);t.fontSize*=k;t.lineHeightPx*=k;}
  return {mapped:true,scale:k,offset:[dx,dy],from:dimensions,to:[w,h]};
 }
 function prepareText(text,{width:w,height:h,mode,productSlot,policy}){
  const audit={mode,sourceLocalizationVerified:false,sourceBoxesRequiredForRendering:false,changes:[],reviewRequired:mode==='keep-reference'};
  if(!text.length)return audit;
  const valid=b=>b&&['x','y','width','height'].every(n=>Number.isFinite(b[n]))&&b.x>=0&&b.y>=0&&b.width>0&&b.height>0&&b.x+b.width<=w+1e-6&&b.y+b.height<=h+1e-6;
  const overlaps=(a,b)=>a.x<b.x+b.width&&a.x+a.width>b.x&&a.y<b.y+b.height&&a.y+a.height>b.y;
  if(productSlot&&!valid(productSlot))throw Error('产品区域超出输出画布');
  if(mode==='auto-layout'){
   const m=Math.min(w,h)*.04,gap=m*.4;
   const regions=productSlot?[
    {x:m,y:m,width:productSlot.x-2*m,height:h-2*m},
    {x:productSlot.x+productSlot.width+m,y:m,width:w-productSlot.x-productSlot.width-2*m,height:h-2*m},
    {x:m,y:m,width:w-2*m,height:productSlot.y-2*m},
    {x:m,y:productSlot.y+productSlot.height+m,width:w-2*m,height:h-productSlot.y-productSlot.height-2*m}
   ]:[{x:m,y:m,width:w-2*m,height:h-2*m}];
   const region=regions.filter(b=>valid(b)&&b.width>=w*.15&&b.height>=text.length*18+gap*(text.length-1)).sort((a,b)=>b.width*b.height-a.width*a.height)[0];
   if(!region)throw Error('没有安全文字区域，需要修正布局');
   const weights=text.map(t=>t.role==='title'?1.5:1),unit=(Math.min(region.height,h*.32)-gap*(text.length-1))/weights.reduce((a,b)=>a+b,0);let y=region.y;
   if(unit<12)throw Error('文字过多，无法安全排版');
   text.forEach((t,i)=>{t.box={x:region.x,y,width:region.width,height:unit*weights[i]};y+=t.box.height+gap;t.fontSize=Math.min(256,(t.role==='title'?.07:.04)*Math.min(w,h));t.lineHeightPx=t.fontSize*1.25;});
   audit.changes.push({kind:'deterministic-auto-layout',region,sourceGeometryUsed:false});audit.reviewRequired=true;
  }
  for(let i=0;i<text.length;i++){
   const t=text[i];if(!valid(t.box))throw Error('文字超出输出画布，不能猜测坐标单位');
   if(productSlot&&overlaps(t.box,productSlot))throw Error('文字框与产品区域重叠');
   if(text.slice(0,i).some(p=>overlaps(p.box,t.box)))throw Error('文字框互相重叠');
   const size=t.fontSize,leading=t.lineHeightPx,minSize=Math.max(10,Math.min(w,h)*.01,size*.5);let fitted=false,last;
   for(let k=0;k<30;k++){
    try{InterTextFoundation.layout(t,policy,F.copyText);fitted=true;break;}
    catch(e){if(!/exceeds|overlap/.test(e.message))throw e;last=e.message;}
    const next=t.fontSize*.95;if(next<minSize)break;t.fontSize=next;t.lineHeightPx=mode==='keep-reference'?leading:Math.max(leading*t.fontSize/size,t.fontSize*1.2);
   }
   if(!fitted)throw Error('文字无法在可读字号内放入布局：'+last);
   if(t.fontSize!==size){audit.changes.push({kind:'font-fit',index:i,from:size,to:t.fontSize,ratio:t.fontSize/size});if(t.fontSize/size<.8)audit.reviewRequired=true;}
  }
  return audit;
 }
 function requireCompleteCopy(plan,options){
  if(options.mode==='remove-all-copy'||options.mode==='custom')return {mode:options.mode};
  const rendered=plan.layout.text.map(t=>t.text).join(' ');
  if(options.mode==='preserve-reference'&&plan.layout.text.some(t=>/ensure[\s\S]*compatib|guarantee[\s\S]*compatib/i.test(t.text)&&!options.productParameters?.includes(t.text)))throw Error('保留原文中的兼容保证缺少依据；仍保持保留模式，不能因删除百分比就自动确认该保证');
  const repeated=plan.layout.text.filter(t=>t.role==='title'&&/CAN[ -]?BUS[\s\S]*(ready|support|enabled)/i.test(t.text));
  if(repeated.length>1)throw Error('同一CANBUS功能被重复填入主副卖点；需合并语义组，不能假造第二个承诺');
  const e=plan.layout.evidence,blocks=e?.sourceBlocks;
  if(!Array.isArray(blocks)||!blocks.length)throw Error('缺少原图逐元素文案清单；不能确认完整性');
  if(plan.copyDecisions){const ds=CopyLayoutContract.inventory(blocks,plan.copyDecisions);const shown=ds.filter(d=>d.action!=='remove');if(shown.length!==plan.layout.text.length||shown.some(d=>plan.layout.text[d.renderIndex]?.text!==d.text))throw Error('逐元素决策与实际文案不一致');return ds;}
  // Old proposals can still render only if every source element has a justified decision.
  for(const b of blocks){const decisions=(e.rewrites||[]).filter(r=>r.blockId===b.id);if(decisions.length!==1)throw Error('原文元素缺少唯一处理状态');const r=decisions[0];
   if(r.action==='render'&&plan.layout.text[r.renderIndex]?.text?.trim())continue;
   const brand=(e.facts||[]).some(f=>f.kind==='brand'&&f.value.trim()===b.sourceText.trim())&&!options.brandName?.trim();
   const unsupported99=b.sourceText.trim()==='99%'&&!options.productParameters?.includes('99%');
   if(r.action==='omit'&&(brand||unsupported99)&&r.omissionReason?.trim())continue;
   throw Error('文案完整性未通过：'+b.sourceText+'。未确认参数必须逐项处理，不能静默删除整组文案。');
  }return {sourceElementCount:blocks.length,legacyDecisionsChecked:true};
 }
 function fitReferenceBody(visible,g,sourceHash,w,h){
  if(g.sourceHash!==sourceHash||g.reviewState!=='manual-pixel-reviewed')throw Error('原图主体占比缺少绑定复核');
  return CopyLayoutContract.sourceOccupancy(visible,g.body,g.canvas,{width:w,height:h},g.anchor);
 }
 function fitVisible(b,slot){const scale=Math.min(slot.width/b.width,slot.height/b.height);return {scale,x:slot.x+(slot.width-b.width*scale)/2-b.x*scale,y:slot.y+slot.height-(b.y+b.height)*scale};}
 return {version:'product-auto-layout-20261018.5',compose,requireCompleteCopy,fitReferenceBody,requireBackgroundGeometry,soften,slotFor,contactShadow,fitVisible,mapLayout,prepareText,applyTrustedAnchors};
})();
