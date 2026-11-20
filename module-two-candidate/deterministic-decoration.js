'use strict';
// Local scene -> decoration layer. No inference, scene extraction or network access.
globalThis.DeterministicDecoration=(()=>{
 const canonical=v=>Array.isArray(v)?v.map(canonical):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])])):v;
 const hash=v=>ProductCanvasFoundation.sha(new Blob([JSON.stringify(canonical(v))]));
 const need=(v,m)=>{if(!v)throw Error('Decoration: '+m);};
 const rect=b=>b&&['x','y','width','height'].every(k=>Number.isFinite(b[k]))&&b.width>0&&b.height>0;
 const inside=(a,b)=>rect(a)&&rect(b)&&a.x>=b.x&&a.y>=b.y&&a.x+a.width<=b.x+b.width&&a.y+a.height<=b.y+b.height;
 const overlap=(a,b)=>a.x<b.x+b.width&&a.x+a.width>b.x&&a.y<b.y+b.height&&a.y+a.height>b.y;
 const radii=r=>Array.isArray(r)?r:[r,r,r,r];
 const validRadius=(r,b)=>radii(r).length===4&&radii(r).every(n=>Number.isFinite(n)&&n>=0&&n<=Math.min(b.width,b.height)/2);
 const roundedContains=(q,b,r)=>{if(!inside(q,b))return false;const a=radii(r);return [[q.x,q.y],[q.x+q.width,q.y],[q.x+q.width,q.y+q.height],[q.x,q.y+q.height]].every(([x,y])=>[[b.x+a[0],b.y+a[0],a[0],x<b.x+a[0]&&y<b.y+a[0]],[b.x+b.width-a[1],b.y+a[1],a[1],x>b.x+b.width-a[1]&&y<b.y+a[1]],[b.x+b.width-a[2],b.y+b.height-a[2],a[2],x>b.x+b.width-a[2]&&y>b.y+b.height-a[2]],[b.x+a[3],b.y+b.height-a[3],a[3],x<b.x+a[3]&&y>b.y+b.height-a[3]]].every(([cx,cy,n,test])=>!test||(x-cx)**2+(y-cy)**2<=n*n));};
 const color=s=>typeof s==='string'&&/^#[0-9a-f]{6}$/i.test(s);
 function validate(c,layout){
  need(c?.schemaVersion==='deterministic-decoration-1','unsupported contract');
  const {width:w,height:h}=c.canvas||{},full={x:0,y:0,width:w,height:h};
  need(Number.isInteger(w)&&Number.isInteger(h)&&w>0&&h>0&&w*h<=16000000&&color(c.canvas.backgroundFill),'canvas');
  for(const key of ['panels','labelContainers','sceneAssets','comparisonGroups'])need(Array.isArray(c[key]),key);
  for(const key of ['panels','labelContainers','sceneAssets','comparisonGroups'])need(c[key].every(x=>typeof x.id==='string'&&x.id)&&new Set(c[key].map(x=>x.id)).size===c[key].length,'unique '+key);
  need(c.panels.length>0,'scene viewports required, including unframed scenes');
  const allEvidence=[];
  for(const a of c.sceneAssets){
   need(/^[a-f0-9]{64}$/.test(a.sha256)&&Number.isInteger(a.width)&&Number.isInteger(a.height)&&a.width>0&&a.height>0,'scene identity');
   need(a.cleanSceneOnlyReviewed===true&&a.bakedFramesAbsentReviewed===true&&a.cameraAndEvidenceReview==='reviewed'&&Array.isArray(a.protectedEvidenceBounds),'clean scene review');
   need(a.protectedEvidenceBounds.every(b=>inside(b,{x:0,y:0,width:a.width,height:a.height})),'evidence bounds');
  }
  for(const g of c.comparisonGroups){
   need(Array.isArray(g.panelIds)&&g.panelIds.length>0&&new Set(g.panelIds).size===g.panelIds.length&&g.mappingReview==='reviewed'&&typeof g.sharedSceneCoordinateSystem==='string'&&g.sharedSceneCoordinateSystem,'mapping review');
   need(Number.isFinite(g.sharedUniformScale)&&g.sharedUniformScale>0&&g.sharedTranslationInPanelCoordinates&&['x','y'].every(k=>Number.isFinite(g.sharedTranslationInPanelCoordinates[k])),'uniform mapping');
   need(g.panelIds.every(id=>c.panels.some(p=>p.id===id&&p.comparisonGroupId===g.id)),'group inventory');
   const assets=g.panelIds.map(id=>c.sceneAssets.find(a=>a.id===c.panels.find(p=>p.id===id).sceneAssetId));
   need(assets.every(a=>a&&a.width===assets[0].width&&a.height===assets[0].height),'shared scene dimensions');
  }
  for(const p of c.panels){
   const a=c.sceneAssets.find(a=>a.id===p.sceneAssetId),g=c.comparisonGroups.find(g=>g.id===p.comparisonGroupId);
   need(a&&g&&g.panelIds.includes(p.id)&&inside(p.outerRect,full)&&inside(p.sceneViewportRect,p.outerRect),'panel geometry');
   const r=p.cornerRadius,b=p.borderStyle;
   need(validRadius(r,p.outerRect)&&b&&Number.isFinite(b.width)&&b.width>=0&&b.width<=Math.min(p.outerRect.width,p.outerRect.height)/2&&color(b.color),'border');
   const v=p.sceneViewportRect,k=g.sharedUniformScale,t=g.sharedTranslationInPanelCoordinates;
   const mapped={x:v.x+t.x,y:v.y+t.y,width:a.width*k,height:a.height*k};
   need(inside(v,mapped),'scene must fill viewport without independent fit');
   const inset=Math.max(...radii(r),b.width),safe={x:p.outerRect.x+inset,y:p.outerRect.y+inset,width:p.outerRect.width-2*inset,height:p.outerRect.height-2*inset};
   for(const e of a.protectedEvidenceBounds){const q={x:mapped.x+e.x*k,y:mapped.y+e.y*k,width:e.width*k,height:e.height*k};need(inside(q,v)&&inside(q,safe),'protected evidence cropped by viewport/corner/border');allEvidence.push(q);}
  }
  need(c.panels.every((p,i)=>c.panels.slice(0,i).every(q=>!overlap(p.outerRect,q.outerRect))),'overlapping panels');
  const owned=[];
  for(const l of c.labelContainers){
   need(inside(l.rect,full)&&validRadius(l.cornerRadius,l.rect)&&(l.fillStyle===null||color(l.fillStyle)),'label');
   need(l.panelId===null||c.panels.some(p=>p.id===l.panelId&&inside(l.rect,p.outerRect)),'label panel');
   need(allEvidence.every(q=>!overlap(l.rect,q)),'label covers protected evidence');
   need(Array.isArray(l.retainedTextIndices),'text ownership');
   for(const i of l.retainedTextIndices){need(Number.isInteger(i)&&layout.text[i]&&inside(layout.text[i].box,l.rect),'text container');owned.push(i);}
  }
  need(owned.length===layout.text.length&&new Set(owned).size===owned.length,'complete unique text ownership');
  return c;
 }
 function checkGlyphs(c,plans){
  plans.forEach((p,i)=>{const l=c.labelContainers.find(l=>l.retainedTextIndices.includes(i));need(l,'glyph owner');
   const r=l.cornerRadius,b=l.rect;
   p.metrics.forEach((m,j)=>{if(m.ascent+m.descent===0)return;const q={x:p.positions[j].x-m.left,y:p.positions[j].y-m.ascent,width:m.left+m.right,height:m.ascent+m.descent},parent=c.panels.find(p=>p.id===l.panelId);need(roundedContains(q,b,r)&&(!parent||roundedContains(q,parent.outerRect,parent.cornerRadius)),'actual glyph escapes container');});
  });
 }
 async function render({contract,layout,sourceHash,assets,signal}){
  const c=structuredClone(contract);validate(c,layout);
  need(c.sourceHash===sourceHash&&c.textLayoutHash===await hash(layout),'source/layout binding');
  const abort=()=>{if(signal?.aborted)throw new DOMException('Composition interrupted','AbortError');};abort();
  const canvas=LocalProductCompose.canvas(c.canvas.width,c.canvas.height),ctx=canvas.getContext('2d'),images=new Map();
  try{
   for(const a of c.sceneAssets){abort();const blob=assets[a.id];need(blob instanceof Blob&&await ProductCanvasFoundation.sha(blob)===a.sha256,'scene hash');const image=await createImageBitmap(blob);images.set(a.id,image);need(image.width===a.width&&image.height===a.height,'scene size');}
   abort();ctx.fillStyle=c.canvas.backgroundFill;ctx.fillRect(0,0,canvas.width,canvas.height);
   const path=(b,r)=>{ctx.beginPath();ctx.roundRect(b.x,b.y,b.width,b.height,r);};
   for(const p of c.panels){const g=c.comparisonGroups.find(g=>g.id===p.comparisonGroupId),v=p.sceneViewportRect,t=g.sharedTranslationInPanelCoordinates,a=images.get(p.sceneAssetId);
    ctx.save();path(p.outerRect,p.cornerRadius);ctx.clip();ctx.beginPath();ctx.rect(v.x,v.y,v.width,v.height);ctx.clip();ctx.drawImage(a,v.x+t.x,v.y+t.y,a.width*g.sharedUniformScale,a.height*g.sharedUniformScale);ctx.restore();
    if(p.borderStyle.width){const n=p.borderStyle.width/2,b=p.outerRect;ctx.strokeStyle=p.borderStyle.color;ctx.lineWidth=p.borderStyle.width;path({x:b.x+n,y:b.y+n,width:b.width-2*n,height:b.height-2*n},radii(p.cornerRadius).map(r=>Math.max(0,r-n)));ctx.stroke();}
   }
   for(const l of c.labelContainers){if(l.fillStyle===null)continue;ctx.save();const p=c.panels.find(p=>p.id===l.panelId);if(p){path(p.outerRect,p.cornerRadius);ctx.clip();}ctx.fillStyle=l.fillStyle;path(l.rect,l.cornerRadius);ctx.fill();ctx.restore();}
   for(const m of c.evidenceMarkers||[]){
    need(m.reviewState==='source-style-reviewed'&&color(m.color)&&m.lineWidth>0&&m.lineWidth<=6&&m.gap>m.lineWidth&&m.cornerLength>0,'evidence marker review');
    const p=c.panels.find(p=>p.id===m.panelId),g=c.comparisonGroups.find(g=>g.id===p?.comparisonGroupId),a=c.sceneAssets.find(a=>a.id===p?.sceneAssetId),e=a?.protectedEvidenceBounds[m.evidenceIndex];need(e&&g,'evidence marker target');
    const k=g.sharedUniformScale,t=g.sharedTranslationInPanelCoordinates,b={x:p.sceneViewportRect.x+t.x+e.x*k-m.gap,y:p.sceneViewportRect.y+t.y+e.y*k-m.gap,width:e.width*k+2*m.gap,height:e.height*k+2*m.gap};need(inside(b,p.sceneViewportRect),'evidence marker outside panel');
    ctx.save();ctx.strokeStyle=m.color;ctx.lineWidth=m.lineWidth;const n=m.cornerLength;for(const [x,y,sx,sy]of [[b.x,b.y,1,1],[b.x+b.width,b.y,-1,1],[b.x+b.width,b.y+b.height,-1,-1],[b.x,b.y+b.height,1,-1]]){ctx.beginPath();ctx.moveTo(x+sx*n,y);ctx.lineTo(x,y);ctx.lineTo(x,y+sy*n);ctx.stroke();}ctx.restore();
   }
   abort();const blob=await LocalProductCompose.png(canvas);abort();return {blob,contractHash:await hash(c),backgroundHash:await ProductCanvasFoundation.sha(blob),canvas};
  }finally{for(const a of images.values())a.close();}
 }
 return {validate,render,checkGlyphs,hash};
})();
