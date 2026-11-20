'use strict';
// Project assets only; no network fetch, system installation or fallback font.
globalThis.InterTextFoundation=(()=>{
 const family='PictureOpsInter41';let ready=false;
 const hashes={normal:'4989b125924991b90d05b2d16e0e388c48f7d5bb8b30539bbf9c755278d0ccaf',italic:'d6f1f6a172d9e588438db9f986fd5cfad7b30f644374080a8a9d4d91e344586f'};
 const need=(v,m)=>{if(!v)throw Error(m);};
 const hash=async b=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await b.arrayBuffer()))).map(x=>x.toString(16).padStart(2,'0')).join('');
 async function load({normal,italic}){
  const faces=[];
  for(const [style,blob] of Object.entries({normal,italic})){
   need(blob instanceof Blob&&await hash(blob)===hashes[style],'Inter asset hash mismatch');
   const face=new FontFace(family,await blob.arrayBuffer(),{style,weight:'100 900'});await face.load();need(face.status==='loaded','Inter failed to load');faces.push(face);
  }
  faces.forEach(f=>document.fonts.add(f));ready=true;return {family,version:'4.1',hashes:{...hashes},oldBundleRecovered:false};
 }
 function context(t){
  need(ready,'Inter project fonts not loaded');
  need(Number.isFinite(t.fontSize)&&t.fontSize>0&&t.fontSize<=512,'explicit font size required');
  need(Number.isFinite(t.weight)&&t.weight>=100&&t.weight<=900,'explicit weight required');
  need(['normal','italic'].includes(t.style),'explicit normal/italic style required');
  need(Number.isFinite(t.lineHeightPx)&&t.lineHeightPx>0,'explicit line height required');
  need(['left','center','right'].includes(t.align),'explicit alignment required');
  need(t.box&&Object.values(t.box).every(Number.isFinite)&&t.box.width>0&&t.box.height>0,'explicit text box required');
  const c=document.createElement('canvas').getContext('2d');c.font=`${t.style} ${t.weight} ${t.fontSize}px ${family}`;c.textBaseline='alphabetic';
  need(!('scaleX'in t)&&!('maxWidth'in t),'horizontal compression forbidden');return c;
 }
 function layout(t,policy,format){
  const text=format(t.text,t,policy);if(!text)return {text,lines:[],box:t.box};
  // This foundation validates Latin-1 only; unsupported glyphs cannot silently fall back.
  need(Array.from(text).every(c=>c==='\n'||(c.charCodeAt(0)>=32&&c.charCodeAt(0)<=255)),'glyph coverage not verified for this text');
  const ctx=context(t),measure=s=>{const m=ctx.measureText(s);return {advance:m.width,left:m.actualBoundingBoxLeft,right:m.actualBoundingBoxRight,ascent:m.actualBoundingBoxAscent,descent:m.actualBoundingBoxDescent,width:Math.max(m.width,m.actualBoundingBoxLeft+m.actualBoundingBoxRight)};};
  const lines=[];
  for(const paragraph of text.split('\n')){
   let current='';
   for(const token of paragraph.match(/ +|[^ ]+/g)||[]){
    need(measure(token).width<=t.box.width,'unbreakable text exceeds box; original text unchanged');
    if(current&&measure(current+token).width>t.box.width){lines.push(current);current=token;}else current+=token;
   }
   lines.push(current);
  }
  const metrics=lines.map(measure),ascent=Math.max(...metrics.map(m=>m.ascent),0),descent=Math.max(...metrics.map(m=>m.descent),0);
  need(t.lineHeightPx>=ascent+descent,'line spacing would overlap glyphs');
  const height=ascent+descent+Math.max(0,lines.length-1)*t.lineHeightPx;
  need(height<=t.box.height,'text exceeds available height; no automatic shortening or resizing '+JSON.stringify({text,height,box:t.box,lines,font:ctx.font}));
  const positions=metrics.map((m,i)=>({x:t.box.x+(t.align==='left'?0:t.align==='center'?(t.box.width-m.width)/2:t.box.width-m.width)+Math.max(0,m.left),y:t.box.y+ascent+i*t.lineHeightPx}));
  if(t.linePlacement){if(lines.length!==1)throw Error('Grouped run wrapped unexpectedly');positions[0]={...t.linePlacement};}
  return {inlineFill:t.inlineFill,lineGroupId:t.lineGroupId,text,lines,metrics,positions,height,presentation:t.presentation||null,box:{...t.box},font:ctx.font,color:t.color||'#000000',family,version:'4.1',hashes:{...hashes},lineHeightPx:t.lineHeightPx,originalText:t.text};
 }
 function draw(ctx,plan){if(plan.presentation)return TextPresentation.draw(ctx,plan,draw);ctx.save();ctx.font=plan.font;ctx.textBaseline='alphabetic';ctx.textAlign='left';ctx.fillStyle=plan.color;if(plan.inlineFill){const b=plan.box,g=ctx.createLinearGradient(b.x,b.y,plan.inlineFill.direction==='horizontal'?b.x+b.width:b.x,plan.inlineFill.direction==='horizontal'?b.y:b.y+b.height);plan.inlineFill.stops.forEach(s=>g.addColorStop(s.at,s.color));ctx.fillStyle=g;}plan.lines.forEach((line,i)=>ctx.fillText(line,plan.positions[i].x,plan.positions[i].y));ctx.restore();}
 return Object.freeze({load,layout,draw,get ready(){return ready;},family});
})();
