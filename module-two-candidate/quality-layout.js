'use strict';
// Reusable role-driven arrangement. Coordinates supplied by reviewed source geometry,
// never by reference identity or a fixed copy string.
globalThis.QualityLayout=(()=>{
 function projectStyle(t,{sourceHash,angle=-10,paletteRole='neutral',outline=false,preserveFontStyle=false}){
  const b=t.box,pad=outline?5:0,mc=document.createElement('canvas').getContext('2d');const fontStyle=preserveFontStyle?(t.style||'normal'):'italic';mc.font=`${fontStyle} ${t.weight||700} ${t.fontSize}px PictureOpsInter41`;
  const actual=globalThis.InterTextFoundation?.ready?InterTextFoundation.layout({...t,style:fontStyle,presentation:null},{},s=>s):null,ms=t.text.split('\n').map(x=>mc.measureText(x)),natural=(actual?actual.height:Math.max(...ms.map(m=>m.actualBoundingBoxAscent+m.actualBoundingBoxDescent))+(ms.length-1)*t.lineHeightPx)+(outline?16:8);
  const dy=Math.min(Math.max(0,b.height-natural-2*pad),Math.abs(Math.tan(angle*Math.PI/180))*b.width),inkH=Math.min(natural,b.height-dy-2*pad);
  const quad=angle<=0?[[b.x+pad,b.y+dy+pad],[b.x+b.width-pad,b.y+pad],[b.x+b.width-pad,b.y+inkH+pad],[b.x+pad,b.y+inkH+dy+pad]]:[[b.x+pad,b.y+pad],[b.x+b.width-pad,b.y+dy+pad],[b.x+b.width-pad,b.y+inkH+dy+pad],[b.x+pad,b.y+inkH+pad]];
  return {...t,style:fontStyle,presentation:{sourceHash,reviewState:'manual-pixel-reviewed',paletteRole,quad,fitTextureToGlyphs:true,...(outline?{stroke:{color:'#FFFFFF',width:8},fill:{stops:[{at:0,color:'#E3A64C'},{at:1,color:'#8F430E'}]}}:{stroke:{color:'#101010',width:4}})}};
 }
 function textSize(t,width,height,{max=480,min=24,inkSafe=false,actualInkHeight=false}={}){
  const c=document.createElement('canvas').getContext('2d');let chosen=min;
  for(let n=Math.min(512,max);n>=min;n-=2){c.font=`${t.style||'normal'} ${t.weight||700} ${n}px PictureOpsInter41`;const measure=s=>{const m=c.measureText(s);return inkSafe?Math.max(m.width,m.actualBoundingBoxLeft+m.actualBoundingBoxRight)+2:m.width;};const paragraphs=t.text.split('\n');let lines=0,good=true;for(const p of paragraphs){let line='';for(const token of p.split(/( +)/)){if(measure(token)>width){good=false;break}if(line&&measure(line+token)>width){lines++;line=token}else line+=token;}lines++;}const metrics=c.measureText(t.text.replace(/\n/g,' ')),inkHeight=metrics.actualBoundingBoxAscent+metrics.actualBoundingBoxDescent+(lines-1)*n*1.12;if(good&&(actualInkHeight?inkHeight:lines*n*1.12)<=height){chosen=n;break}}
  return {...t,fontSize:chosen,lineHeightPx:chosen*1.12,box:{...t.box,width,height}};
 }
 function custom(t,region){return textSize({...t,box:{...region},align:'left'},region.width,region.height,{max:Math.min(region.width*.27,region.height*.3),min:36})}
 function customGroup(t,region){
  const split=t.text.indexOf('\n');if(split<1||split===t.text.length-1)return [custom(t,region)];
  const head=custom({...t,text:t.text.slice(0,split+1),role:'title'},{...region,height:region.height*.58});
  const body=textSize({...t,text:t.text.slice(split+1),role:'body',box:{...region,y:region.y+region.height*.65,height:region.height*.32}},region.width,region.height*.32,{max:head.fontSize*.7,min:24});
  if(head.text+body.text!==t.text)throw Error('Custom copy changed');return [head,body];
 }
 function parallel(t,parts){if(parts.length!==3||parts.join(' · ')!==t.text)throw Error('Parallel structure must preserve exact copy');return {...t,presentation:{...(t.presentation||{}),kind:'parallel-columns',parts,paletteRole:'neutral'}}}
 function groupedProduct(texts,{sourceHash,region,inkSafe=false}){
  const r=region;if(texts.length!==4)return texts.map(t=>textSize(t,t.box.width,t.box.height,{max:t.fontSize,min:Math.min(24,t.fontSize)}));
  const [subtitle,heading,feature,explanation]=texts;
  const place=(t,x,y,w,h,max)=>textSize({...t,box:{x:r.x+x*r.width,y:r.y+y*r.height,width:w*r.width,height:h*r.height}},w*r.width,h*r.height,{max,min:32,inkSafe});
  const featurePlan=projectStyle(place(feature,0,.45,1,.36,r.width*(300/920)),{sourceHash,outline:true,paletteRole:'emphasis'});const end=Math.max(...featurePlan.presentation.quad.map(p=>p[1]));featurePlan.box.height=end-featurePlan.box.y+5;const body=place(explanation,0,.83,1,.15,r.width*(76/920));body.box.y=end+r.width*.02;return [place(subtitle,0,0,1,.09,r.width*(100/920)),place(heading,0,.13,1,.30,r.width*(205/920)),featurePlan,projectStyle(body,{sourceHash,paletteRole:'neutral'})];
 }
 function fromAnalyzedRoles(candidate,source,background){
  const measured=ReferenceLayoutAnchors.analyze(source,background),heads=candidate.text.filter(t=>['title','subtitle'].includes(t.role)),labels=candidate.text.filter(t=>!['title','subtitle'].includes(t.role));
  if(heads.length!==measured.sourceHeadings.length||labels.length!==measured.outputBands.length)throw Error('Measured regions do not match resolved semantic roles; manual review required');
  const scale=Math.min(background.width/source.width,background.height/source.height),w=background.width;
  const text=heads.map((t,i)=>{const a=measured.sourceHeadings[i],h=a.height*scale*1.4;return textSize({...t,mode:'ai-rewrite',align:'center',box:{x:w*.04,y:a.y*scale-a.height*scale*.15,width:w*.92,height:h}},w*.92,h,{max:a.height*scale*1.35,min:24});}).concat(labels.map((t,i)=>{const a=measured.outputBands[i];return textSize({...t,mode:'ai-rewrite',align:'center',box:{x:a.x+w*.04,y:a.y+a.height*.1,width:w*.92,height:a.height*.8}},w*.92,a.height*.8,{max:a.height*.66,min:24});}));
  return {text,measured,reviewState:'pending-independent-pixel-review',automaticOverlayAuthorized:false};
 }
 return {projectStyle,textSize,custom,customGroup,parallel,groupedProduct,fromAnalyzedRoles};
})();
