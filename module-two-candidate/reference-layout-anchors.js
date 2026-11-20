'use strict';
// Pixel-derived relationships, not image-specific coordinates or exact-match quality gates.
globalThis.ReferenceLayoutAnchors=(()=>{
 function pixels(bitmap){const c=document.createElement('canvas');c.width=bitmap.width;c.height=bitmap.height;const x=c.getContext('2d',{willReadFrequently:true});x.drawImage(bitmap,0,0);return x.getImageData(0,0,c.width,c.height);}
 function runs(rows,gap=0){const out=[];let start=null,last=null;rows.forEach((yes,y)=>{if(yes){if(start===null)start=y;last=y;}else if(start!==null&&y-last>gap){out.push({y:start,height:last-start+1});start=null;}});if(start!==null)out.push({y:start,height:last-start+1});return out;}
 function bands(bitmap){const {data,width:w,height:h}=pixels(bitmap),rows=[];
  for(let y=0;y<h;y++){let rough=0,lum=0,count=0,last=null;for(let x=0;x<w;x+=4){const i=(y*w+x)*4,v=[data[i],data[i+1],data[i+2]];lum+=(v[0]+v[1]+v[2])/3;if(last)rough+=Math.max(...v.map((a,k)=>Math.abs(a-last[k])));last=v;count++;}rows.push(lum/count>30&&rough/Math.max(1,count-1)<3.3);}
  return runs(rows,1).filter(b=>b.height>=h*.018&&b.height<h*.16).map(b=>({x:0,y:b.y,width:w,height:b.height,method:'full-width low-texture band pixels'}));
 }
 function headings(bitmap){const {data,width:w,height:h}=pixels(bitmap),limit=Math.ceil(h*.20),rows=[],bounds=[];
  for(let y=0;y<limit;y++){let count=0,min=w,max=0;for(let x=0;x<w;x++){const i=(y*w+x)*4,r=data[i],g=data[i+1],b=data[i+2];if((r>160&&g>160&&b>160)||(b>130&&b>r*1.5&&g>40)){count++;min=Math.min(min,x);max=Math.max(max,x);}}rows.push(count>w*.045);bounds.push({min,max,count});}
  return runs(rows,Math.max(2,Math.round(h*.004))).map(b=>{const bs=bounds.slice(b.y,b.y+b.height);const x=Math.min(...bs.filter(b=>b.count>w*.045).map(b=>b.min)),right=Math.max(...bs.filter(b=>b.count>w*.045).map(b=>b.max));return {...b,x,width:right-x+1,method:'source heading pixel row groups'};}).filter(b=>b.height>h*.008&&b.width>w*.35).slice(0,2);
 }
 function analyze(source,background){return {sourceHeadings:headings(source),sourceBands:bands(source),outputBands:bands(background)};}
 return Object.freeze({analyze,bands,headings});
})();
