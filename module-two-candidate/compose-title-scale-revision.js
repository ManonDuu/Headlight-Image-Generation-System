(async()=>{
 const blob=new Blob([Uint8Array.from(atob(BACKGROUND_BYTES),c=>c.charCodeAt(0))],{type:'image/jpeg'}),F=ProductCanvasFoundation;
 const sourceHash=await F.sha(blob);if(sourceHash!=='586fb95763aeec3faf9f144db6920f3d067030e0114954bf59f403fb44612dbd')throw Error('Background changed');
 const bitmap=await createImageBitmap(blob),canvas=document.createElement('canvas');canvas.width=bitmap.width;canvas.height=bitmap.height;if(canvas.width!==1856||canvas.height!==2304)throw Error('Native dimensions changed');
 const ctx=canvas.getContext('2d');ctx.drawImage(bitmap,0,0);bitmap.close();const pixels=ctx.getImageData(0,0,canvas.width,canvas.height).data;
 const spans=(match)=>{const rows=[];for(let y=0;y<canvas.height;y++){if([.05,.5,.95].every(f=>{const i=(y*canvas.width+Math.floor(f*canvas.width))*4;return match(pixels[i],pixels[i+1],pixels[i+2]);}))rows.push(y);}const groups=[];for(const y of rows){const last=groups.at(-1);if(last&&y===last[1]+1)last[1]=y;else groups.push([y,y]);}return groups.filter(([a,b])=>b-a>80);};
 const blue=spans((r,g,b)=>r<55&&g>25&&b>170),gray=spans((r,g,b)=>r>65&&r<115&&Math.abs(r-g)<8&&Math.abs(g-b)<8);
 if(blue.length!==1||gray.length!==1)throw Error('Cannot confidently locate the two existing label bars; no guessed placement');
 const plan=structuredClone(ACTUAL_PLAN),changes=[];
 for(const [i,span] of [[2,blue[0]],[3,gray[0]]]){const t=plan.text[i],old={...t.box};t.box={x:80,y:span[0]+(span[1]-span[0]+1-t.box.height)/2,width:1696,height:t.box.height};changes.push({row:i,reason:'Place neutral label in its actual generated comparison bar; no pixel edit/rescale of background',before:old,after:t.box,detectedBar:span});}
 const typography=[];for(const [index,key] of [[0,'title'],[1,'subtitle']]){const fixed=ReferenceTypeScale.fit(plan.text[index],TYPE_AUDIT.source[key].inkBox,{sourceWidth:1200,sourceHeight:1500,width:1856,height:2304,policy:CANVAS_TEST_POLICY});plan.text[index]=fixed.text;typography.push(fixed.audit);}
 const measured=plan.text.map(t=>InterTextFoundation.layout(t,CANVAS_TEST_POLICY,F.copyText));
 for(const p of measured){const b=p.box;if(b.x<0||b.y<0||b.x+b.width>canvas.width||b.y+b.height>canvas.height)throw Error('Text outside output');InterTextFoundation.draw(ctx,p);}
 const output=await new Promise(r=>canvas.toBlob(r,'image/png')),outputHash=await F.sha(output);await F.download({blob:output,manifest:{outputHash}},'B0FBFPH2Y8-title-size-comparison-copy-pending.png');
 return {backgroundHash:sourceHash,outputHash,width:canvas.width,height:canvas.height,requestedRatio:'4:5',exactRatio:false,stretch:false,crop:false,backgroundPixelsUnscaled:true,originalLayout:ACTUAL_PLAN,compositionLayout:plan,changes,typography,textPlans:measured,copyStatus:'unchanged-for-size-comparison-only-not-final-marketing-copy',newModelCalls:0,analysisCalls:0,backgroundCallsDuringComposition:0,visualAcceptance:'pending'};
})()
