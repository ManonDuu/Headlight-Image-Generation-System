'use strict';
// Candidate boxes locate pixels only. This is conservative segmentation, not OCR.
globalThis.ReferenceInkEvidence=(()=>{
 const need=(v,m)=>{if(!v)throw Error(m);};
 function segment(image,candidate,sourceHash,index){
  const {width:W,height:H,data}=image,b=candidate.box;
  need(b&&[b.x,b.y,b.width,b.height].every(Number.isFinite)&&b.width>0&&b.height>0&&b.x>=0&&b.y>=0&&b.x+b.width<=W&&b.y+b.height<=H,'Candidate outside reference');
  need(typeof candidate.sourceText==='string'&&candidate.sourceText.trim()&&['title','subtitle','body','brand'].includes(candidate.role),'Original line text and role required; rewritten copy is not source evidence');
  const x0=Math.floor(b.x),y0=Math.floor(b.y),w=Math.floor(b.width),h=Math.floor(b.height),rgb=(x,y)=>{const p=((y0+y)*W+x0+x)*4;return [data[p],data[p+1],data[p+2]];};
  const border=[];for(let x=0;x<w;x++){border.push(rgb(x,0),rgb(x,h-1));}for(let y=1;y<h-1;y++){border.push(rgb(0,y),rgb(w-1,y));}
  const median=a=>a.sort((a,b)=>a-b)[Math.floor(a.length/2)],background=[0,1,2].map(k=>median(border.map(v=>v[k]))),distance=v=>Math.sqrt(v.reduce((s,c,k)=>s+(c-background[k])**2,0));
  const noise=median(border.map(distance)),threshold=Math.max(45,noise*3),mask=new Uint8Array(w*h),seen=new Uint8Array(w*h),components=[];
  for(let y=0;y<h;y++)for(let x=0;x<w;x++)mask[y*w+x]=distance(rgb(x,y))>threshold?1:0;
  for(let start=0;start<mask.length;start++)if(mask[start]&&!seen[start]){
   const queue=[start],pixels=[];seen[start]=1;let xmin=w,ymin=h,xmax=0,ymax=0;
   for(let q=0;q<queue.length;q++){const p=queue[q],x=p%w,y=Math.floor(p/w);pixels.push(p);xmin=Math.min(xmin,x);xmax=Math.max(xmax,x);ymin=Math.min(ymin,y);ymax=Math.max(ymax,y);
    for(const [dx,dy] of [[-1,0],[1,0],[0,-1],[0,1]]){const xx=x+dx,yy=y+dy,n=yy*w+xx;if(xx>=0&&xx<w&&yy>=0&&yy<h&&mask[n]&&!seen[n]){seen[n]=1;queue.push(n);}}
   }
   if(pixels.length>=2)components.push({x:xmin,y:ymin,width:xmax-xmin+1,height:ymax-ymin+1,pixels});
  }
  const reasons=[];
  if(noise>15)reasons.push('Textured/uneven crop border');
  const shapes=components.filter(c=>c.height>=3&&c.width>=1),heights=shapes.map(c=>c.height),typical=heights.length?median(heights):0;
  const letters=shapes.filter(c=>c.height>=typical*.5&&c.height<=typical*1.6&&c.width/c.height<1.8&&c.pixels.length/(c.width*c.height)<.88&&c.x>0&&c.y>0&&c.x+c.width<w&&c.y+c.height<h);
  const retained=new Set(letters.flatMap(c=>c.pixels));const total=components.reduce((s,c)=>s+c.pixels.length,0),retainedFraction=retained.size/Math.max(1,total);
  if(retainedFraction<.78)reasons.push('Non-glyph highlight/shape contamination');
  const bands=[];for(const c of letters.sort((a,b)=>a.y-b.y)){let band=bands.find(v=>Math.min(v.bottom,c.y+c.height)-Math.max(v.top,c.y)>Math.min(v.bottom-v.top,c.height)*.35);if(!band){band={top:c.y,bottom:c.y+c.height,components:[]};bands.push(band);}band.components.push(c);band.top=Math.min(band.top,c.y);band.bottom=Math.max(band.bottom,c.y+c.height);}
  bands.sort((a,b)=>a.top-b.top);const strings=candidate.sourceText.split('\n');
  if(bands.length!==strings.length)reasons.push('Detected lines do not match source transcription');
  const lines=bands.map((band,lineIndex)=>{
   const cs=band.components,left=Math.min(...cs.map(c=>c.x)),right=Math.max(...cs.map(c=>c.x+c.width)),chars=(strings[lineIndex]||'').replace(/[^\p{L}\p{N}]/gu,'').length;
   if(!chars||cs.length<Math.max(2,chars*.5)||cs.length>chars*1.8)reasons.push('Component count inconsistent with candidate text');
   const bottomSpread=Math.max(...cs.map(c=>c.y+c.height))-Math.min(...cs.map(c=>c.y+c.height));if(bottomSpread>(band.bottom-band.top)*.45)reasons.push('Inconsistent glyph baseline');
   const points=cs.flatMap(c=>c.pixels).sort((a,b)=>a-b),inkRuns=[];for(const p of points){const y=Math.floor(p/w)+y0,x=p%w+x0,last=inkRuns[inkRuns.length-1];if(last&&last[0]===y&&last[1]+last[2]===x)last[2]++;else inkRuns.push([y,x,1]);}
   return {inkRuns,sourceHash,role:candidate.role,roleIndex:index,lineIndex,sourceText:strings[lineIndex]||'',x:x0+left,y:y0+band.top,width:right-left,height:band.bottom-band.top,lineCount:1,measurementKind:'segmented-ink',confidence:0};
  });
  // Quality score measures segmentation evidence only, never OCR/semantic correctness.
  const confidence=reasons.length?Math.min(.65,retainedFraction*.65):.9;
  lines.forEach(l=>l.confidence=confidence);
  return {role:candidate.role,roleIndex:index,sourceText:candidate.sourceText,candidateBox:{...b},lines,confidence,reasons:[...new Set(reasons)],state:reasons.length?'awaiting-typography-review':'measured',sourceTextVerified:false};
 }
 async function extract(reference,candidates){
  need(reference instanceof Blob&&Array.isArray(candidates)&&candidates.length>0,'Reference blob and candidate regions required');
  const sourceHash=await ProductCanvasFoundation.sha(reference),bitmap=await createImageBitmap(reference),canvas=document.createElement('canvas');canvas.width=bitmap.width;canvas.height=bitmap.height;const ctx=canvas.getContext('2d');ctx.drawImage(bitmap,0,0);bitmap.close();
  const image=ctx.getImageData(0,0,canvas.width,canvas.height),roles=candidates.map((c,i)=>segment(image,c,sourceHash,i));
  return {version:'reference-ink-evidence-1',sourceHash,sourceWidth:canvas.width,sourceHeight:canvas.height,roles,anchors:roles.flatMap(r=>r.lines),state:roles.every(r=>r.state==='measured')?'measured':'awaiting-typography-review',method:'border-contrast-connected-components',automaticOCR:false};
 }
 return Object.freeze({extract,segment});
})();
