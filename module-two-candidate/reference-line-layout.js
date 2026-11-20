// One source line owns geometry; style runs own only paint and font weight/style.
globalThis.ReferenceLineLayout=(()=>{
 const version='reference-line-layout-2',norm=s=>s.toLowerCase().replace(/[^a-z0-9]/g,'');
 function ink(p,b){const pts=[];for(let y=Math.max(0,Math.floor(b.y));y<Math.min(p.h,Math.ceil(b.y+b.height));y++)for(let x=Math.max(0,Math.floor(b.x));x<Math.min(p.w,Math.ceil(b.x+b.width));x++){const i=(y*p.w+x)*4;if(Math.max(p.data[i],p.data[i+1],p.data[i+2])>115)pts.push([x,y]);}if(!pts.length)return {...b,method:'source-box-fallback'};let l=Infinity,r=-Infinity,t=Infinity,z=-Infinity;for(const [x,y]of pts){l=Math.min(l,x);r=Math.max(r,x+1);t=Math.min(t,y);z=Math.max(z,y+1);}return {x:l,y:t,width:r-l,height:z-t,method:'source-ink'};}
 function apply(text,{blocks,ocr,pixels,scale,outputWidth}){
  const candidates=text.filter(t=>t.role==='title'&&t.sourceGroup?.placement==='header'&&!t.text.includes('\n'));
  const rows=[];for(const t of candidates.sort((a,b)=>a.sourceGroup.bounds.y-b.sourceGroup.bounds.y||a.sourceGroup.bounds.x-b.sourceGroup.bounds.x)){const b=t.sourceGroup.bounds;let row=rows.find(r=>{const q=r[0].sourceGroup.bounds;return Math.abs((b.y+b.height*.5)-(q.y+q.height*.5))<Math.min(b.height,q.height)*.3;});if(row)row.push(t);else rows.push([t]);}
  const audit=[];for(const row of rows){if(row.length<2)continue;row.sort((a,b)=>a.sourceGroup.bounds.x-b.sourceGroup.bounds.x);
   const ids=row.map(t=>t.sourceGroup.blockIds[0]),sources=ids.map(id=>blocks.find(b=>b.id===id));if(sources.some(b=>!b))throw Error('Missing title source identity');
   const line=(ocr?.lines||[]).find(l=>sources.every(b=>norm(l.text).includes(norm(b.sourceText))));
   // Geometric row fallback preserves group identity even when OCR words are missing.
   const boxes=sources.map(b=>ink(pixels,b.sourceBox));const gaps=boxes.slice(1).map((b,i)=>Math.max(0,b.x-boxes[i].x-boxes[i].width));
   const ctx=document.createElement('canvas').getContext('2d');let size=Math.min(...row.map((t,i)=>{ctx.font=`${t.style||'normal'} ${t.weight||700} 100px PictureOpsInter41`;const m=ctx.measureText(t.text);return boxes[i].height*scale*100/(m.actualBoundingBoxAscent+m.actualBoundingBoxDescent);}));
   const regionLeft=Math.min(...row.map(t=>t.box.x)),regionRight=Math.max(...row.map(t=>t.box.x+t.box.width)),width=regionRight-regionLeft;
   let measures;for(let tries=0;tries<20;tries++){measures=row.map(t=>{ctx.font=`${t.style||'normal'} ${t.weight||700} ${size}px PictureOpsInter41`;return ctx.measureText(t.text);});const total=measures.reduce((s,m)=>s+m.actualBoundingBoxLeft+m.actualBoundingBoxRight,0)+gaps.reduce((s,g)=>s+g*scale,0);if(total<=width+.01)break;size*=Math.min(.98,width/total);}
   const total=measures.reduce((s,m)=>s+m.actualBoundingBoxLeft+m.actualBoundingBoxRight,0)+gaps.reduce((s,g)=>s+g*scale,0);if(total>width+.01)throw Error('Title group cannot fit');
   let x=regionLeft+(width-total)/2;const baseline=Math.min(...row.map(t=>t.box.y))+Math.max(...measures.map(m=>m.actualBoundingBoxAscent));
   row.forEach((t,i)=>{const m=measures[i],iw=m.actualBoundingBoxLeft+m.actualBoundingBoxRight;t.fontSize=size;t.lineHeightPx=size*1.12;t.align='left';t.box={x:x-2,y:baseline-m.actualBoundingBoxAscent,width:Math.max(iw,m.width)+4,height:m.actualBoundingBoxAscent+m.actualBoundingBoxDescent+4};t.linePlacement={x:x+m.actualBoundingBoxLeft,y:baseline};t.inlineFill=t.sourceGroup.fillStops?.length?{stops:t.sourceGroup.fillStops,direction:t.sourceGroup.fillDirection||'horizontal'}:null;delete t.presentation;t.lineGroupId=ids.join('|');x+=iw+(gaps[i]||0)*scale;});
   audit.push({version,ids,sourceRelation:line?'ocr-line':'geometry-row-fallback',sourceInk:boxes,sourceGaps:gaps,outputGaps:gaps.map(g=>g*scale),fontSize:size,baseline,groupBounds:{x:regionLeft,width},expectedOrder:ids});
  }return audit;
 }
 return {version,apply};
})();
