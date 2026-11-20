'use strict';
// Local review candidate, not automatic acceptance. No network or model access.
globalThis.ReferenceCandidate=(()=>{
 const need=(v,m)=>{if(!v)throw Error(m);};
 async function compose({reference,background,plan,options,policy}){
  const F=ProductCanvasFoundation,source=await createImageBitmap(reference),bg=await createImageBitmap(background);
  const relations=ReferenceLayoutAnchors.analyze(source,bg);
  const warnings=[],text=structuredClone(plan.text),geometry=plan.sourceGeometry;
  need(geometry?.coordinateSpace==='source-pixels'&&geometry.width===source.width&&geometry.height===source.height,'Reliable source dimensions/coordinate units required');
  const sourceHash=await F.sha(reference),backgroundHash=await F.sha(background);
  need(sourceHash!==backgroundHash,'Reconstructed background required; never paint over original reference');
  need(options.module==='reference-reconstruction','Product replacement must use its identity-preserving pipeline');
  const rewrites=plan.evidence?.rewrites||[],blocks=plan.evidence?.sourceBlocks||[];
  text.forEach((t,i)=>{
   need(!new RegExp(policy.forbiddenSource,'i').test(t.text),'Forbidden final copy');
   if(options.mode==='ai-rewrite'){
    need(t.role!=='brand'||(options.brandName?.trim()&&t.text.toLowerCase()===options.brandName.trim().toLowerCase()),'Unapproved brand');
    const nums=t.text.match(/\d+(?:\.\d+)?\s*(?:%|[a-z°]+)?/gi)||[];
    need(nums.every(n=>(options.productParameters||'').split(/[,;\n]/).some(p=>p.trim()===n.trim())),'Unapproved numeric parameter');
   }
   const rw=rewrites.find(r=>r.action==='render'&&r.renderIndex===i),b=blocks.find(b=>b.id===rw?.blockId);
   need(b?.sourceBox&&Object.values(b.sourceBox).every(Number.isFinite),'Missing reliable text position');
   const box=b.sourceBox;need(box.x>=0&&box.y>=0&&box.width>0&&box.height>0&&box.x+box.width<=source.width&&box.y+box.height<=source.height,'Invalid source position');
   if(options.layoutMode==='keep-reference'){
    const headingIndex=t.role==='title'?0:t.role==='subtitle'?1:-1;
    const heading=headingIndex>=0?relations.sourceHeadings[headingIndex]:null;
    const labelIndices=text.map((v,index)=>({v,index})).filter(({v})=>!['title','subtitle'].includes(v.role));
    const labelIndex=labelIndices.findIndex(v=>v.index===i),container=labelIndex>=0?relations.outputBands[labelIndex]:null;
    const ctx=document.createElement('canvas').getContext('2d');const formatted=F.copyText(t.text,t,policy);
    ctx.font=`${t.style} ${t.weight} 100px ${InterTextFoundation.family}`;const m=ctx.measureText(formatted),ink=Math.max(m.actualBoundingBoxAscent+m.actualBoundingBoxDescent,1);
    if(heading){
     // Reproduce overall text occupancy and common group axis, not incorrect model-box centers.
     const desiredWidth=heading.width/source.width*bg.width;
     t.fontSize=Math.min(256,desiredWidth/Math.max(m.width,1)*100);
     const height=ink*t.fontSize/100;
     t.box={x:bg.width*.04,y:heading.y/source.height*bg.height,width:bg.width*.92,height:height*1.08};
     t.align='center';t.lineHeightPx=Math.max(t.fontSize*1.25,height*1.1);
    }else if(container){
     // Match label order to the actual regenerated containers; source y is never copied onto a changed background.
     t.fontSize=Math.min(256,container.height*.55/ink*100,container.width*.88/Math.max(m.width,1)*100);
     const height=ink*t.fontSize/100;
     t.box={x:container.x+container.width*.06,y:container.y+(container.height-height)/2,width:container.width*.88,height:height*1.05};
     t.align='center';t.lineHeightPx=Math.max(t.fontSize*1.25,height*1.1);
    }else{
     t.box={x:box.x*bg.width/source.width,y:box.y*bg.height/source.height,width:box.width*bg.width/source.width,height:box.height*bg.height/source.height};
     warnings.push({code:'ANCHOR_NOT_DETECTED',role:t.role,detail:'No pixel-derived group/container found; original proposed layout retained for inspection.'});
    }
   }

  });
  if(options.mode==='custom')need(text.map(t=>t.text).join('')===options.customCopy,'Custom copy changed');
  if(options.mode==='remove-all-copy')need(!text.length,'Remove-all-copy has text');
  const plans=text.map(t=>InterTextFoundation.layout(t,policy,F.copyText));
  plans.forEach(p=>need(p.box.x>=0&&p.box.y>=0&&p.box.x+p.box.width<=bg.width+.001&&p.box.y+p.box.height<=bg.height+.001,'Output outside canvas'));
  const canvas=document.createElement('canvas');canvas.width=bg.width;canvas.height=bg.height;const ctx=canvas.getContext('2d');ctx.drawImage(bg,0,0);plans.forEach(p=>InterTextFoundation.draw(ctx,p));source.close();bg.close();
  const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/png'));need(blob,'PNG export failed');
  const manifest={state:'candidate-pending-review',visualAcceptance:'not-evaluated',sourceHash,backgroundHash,outputHash:await F.sha(blob),width:canvas.width,height:canvas.height,textPlans:plans,layoutRelations:relations,warnings,review:['whole-image meaning and hierarchy','source label position','background/product appearance unchanged from reused background'],newModelCalls:0,backgroundPixelsRescaled:false};
  return {blob,manifest};
 }
 return Object.freeze({compose});
})();
