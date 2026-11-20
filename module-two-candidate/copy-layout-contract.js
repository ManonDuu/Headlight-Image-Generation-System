'use strict';
// Explicit element decisions and alpha-body sizing. No model, canvas, or paid API.
globalThis.CopyLayoutContract = (() => {
 function inventory(blocks, decisions, {draft=false}={}) {
  const ids=blocks.map(b=>b.id); if(new Set(ids).size!==ids.length)throw Error('Duplicate source element');
  if(decisions.length!==ids.length||decisions.some(d=>!ids.includes(d.id)))throw Error('Incomplete copy inventory');
  return blocks.map(b=>{
   const found=decisions.filter(d=>d.id===b.id);if(found.length!==1)throw Error('Duplicate or missing copy decision');const d=found[0];
   if(!['retain','replace','remove','pending'].includes(d.action)||!d.reason?.trim())throw Error('Unexplained copy decision');
   if(d.action==='remove'&&!d.authorization?.trim())throw Error('Removal needs explicit rule evidence');
   if(d.action==='pending'&&!draft)throw Error('Unresolved source copy blocks delivery');
   if(['retain','replace','pending'].includes(d.action)&&!d.text?.trim())throw Error('Required copy slot is empty');
   if(d.action==='replace'&&!d.authorization?.trim())throw Error('Replacement needs provenance');
   return {...b,...d};
  });
 }
 function centerGroup(elements, region) {
  if(!elements.length)throw Error('Empty heading group');
  const left=Math.min(...elements.map(t=>t.box.x)),right=Math.max(...elements.map(t=>t.box.x+t.box.width));
  if(right-left>region.width)throw Error('Heading group cannot fit without layout review');
  const dx=region.x+(region.width-(right-left))/2-left;
  return elements.map(t=>({...t,box:{...t.box,x:t.box.x+dx}}));
 }
 function labelCoverage(containers,text) {
  for(const c of containers){if(c.id==='header')continue;const slots=c.retainedTextIndices||[];
   if(!slots.length||slots.some(i=>!text[i]?.text?.trim()))throw Error('Empty label container: '+c.id);
  }return true;
 }
 function sourceOccupancy(visible, sourceBody, sourceCanvas, outputCanvas, anchor) {
  for(const n of [visible.width,visible.height,sourceBody.width,sourceBody.height,sourceCanvas.width,sourceCanvas.height,outputCanvas.width,outputCanvas.height])if(!Number.isFinite(n)||n<=0)throw Error('Missing measured body geometry');
  // Height occupancy preserves subject prominence despite different product silhouette.
  const height=sourceBody.height/sourceCanvas.height*outputCanvas.height,scale=height/visible.height,width=visible.width*scale;
  const left=anchor.centerX*outputCanvas.width-width/2,bottom=anchor.bottom*outputCanvas.height;
  if(left<0||left+width>outputCanvas.width||bottom-height<0||bottom>outputCanvas.height)throw Error('Body occupancy cannot fit: move background/layout; never shrink product');
  return {scale,x:left-visible.x*scale,y:bottom-(visible.y+visible.height)*scale,visibleOutput:{x:left,y:bottom-height,width,height},heightOccupancy:height/outputCanvas.height};
 }
 return {inventory,centerGroup,labelCoverage,sourceOccupancy};
})();
if(typeof module!=='undefined')module.exports=globalThis.CopyLayoutContract;
