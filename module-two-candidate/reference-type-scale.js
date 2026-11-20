'use strict';
// Measured ink anchors, not inferred model fontSize/bbox height, control scale.
globalThis.ReferenceTypeScale={fitRoles(texts,evidence,dimensions){
 if(evidence.roles.length!==texts.length)throw Error('Reference role count mismatch');
 const fits=[],anchors=[];
 texts.forEach((t,i)=>{const role=evidence.roles[i],lines=ProductCanvasFoundation.copyText(t.text,t,dimensions.policy).split('\n');
  if(role.role!==t.role||lines.length!==role.lines.length)throw Error('Copy line structure differs from measured reference; review equivalent line allocation');
  lines.forEach((line,j)=>{const anchor=role.lines[j];anchors.push(anchor);fits.push(this.fit({...t,text:line,mode:'custom'},anchor,dimensions));});
 });
 return {fits,anchors};
},fit(text,anchor,{sourceWidth,sourceHeight,width,height,policy}){
 if(!(['verified-ink-mask','reviewed-visible-ink'].includes(anchor.measurementKind)||(anchor.measurementKind==='segmented-ink'&&anchor.confidence>=.9))||!anchor.sourceHash)throw Error('Verified visible ink measurement required; model font size or bbox is not ink height');
 if(![sourceWidth,sourceHeight,width,height,anchor.width,anchor.height].every(v=>Number.isFinite(v)&&v>0)||![anchor.x,anchor.y].every(v=>Number.isFinite(v)&&v>=0))throw Error('Invalid measured geometry');
 const engine=InterTextFoundation,F=ProductCanvasFoundation;
 const original=engine.layout(text,policy,F.copyText),targetHeight=anchor.height*height/sourceHeight,targetWidth=anchor.width*width/sourceWidth;
 if(original.lines.length!==1||(anchor.lineCount!==undefined&&anchor.lineCount!==1))throw Error('Multiline reference requires verified per-line ink anchors; no guessed line spacing');
 const byHeight=text.fontSize*targetHeight/original.height,byWidth=text.fontSize*targetWidth/original.metrics[0].width;
 // Match width only when actual glyph height remains within the measured 0.8–1.2 range.
 const fontSize=byWidth/byHeight>=.8&&byWidth/byHeight<=1.2?byWidth:byHeight;
 const t={...structuredClone(text),fontSize:Math.round(fontSize*1000)/1000,lineHeightPx:Math.round(fontSize*1.2*1000)/1000,box:{x:anchor.x*width/sourceWidth,y:anchor.y*height/sourceHeight,width:anchor.width*width/sourceWidth,height:targetHeight*1.2}};
 const measured=engine.layout(t,policy,F.copyText),ratio=measured.height/targetHeight;
 if(measured.lines.length!==1)throw Error('Reference line structure changed; equivalent copy or per-line anchors required');
 if(ratio<.8||ratio>1.2)throw Error('Visible glyph height deviates from measured reference; no silent shrink');
 return {text:t,audit:{targetInkHeight:targetHeight,targetInkWidth:targetWidth,actualInkHeight:measured.height,actualInkWidth:measured.metrics[0].width,heightRatio:ratio,fontSizePx:t.fontSize,unit:'output-pixels',source:'reviewed-reference-ink-measurement',widthCanDifferBecauseCopyLengthChanged:true}};
},measureMask(imageData,{sourceHash,verifiedTextOnly=false}={}){
 if(!verifiedTextOnly||!sourceHash)throw Error('Text-only mask must be independently verified; no automatic background/text classification');
 const xs=[],ys=[];for(let y=0;y<imageData.height;y++)for(let x=0;x<imageData.width;x++)if(imageData.data[(y*imageData.width+x)*4+3]>127){xs.push(x);ys.push(y);}
 if(!xs.length)throw Error('Empty text mask');const min=a=>a.reduce((x,y)=>Math.min(x,y),Infinity),max=a=>a.reduce((x,y)=>Math.max(x,y),-Infinity);
 return {x:min(xs),y:min(ys),width:max(xs)-min(xs)+1,height:max(ys)-min(ys)+1,measurementKind:'verified-ink-mask',sourceHash};
},validateGroup(texts,anchors,dimensions,policy){
 if(texts.length!==anchors.length||texts.length<1)throw Error('All reference text roles require measured anchors');
 if(![dimensions.height,dimensions.sourceHeight].every(v=>Number.isFinite(v)&&v>0)||!anchors.every(a=>[a.x,a.y,a.width,a.height].every(Number.isFinite)&&a.width>0&&a.height>0))throw Error('Invalid reference group measurements');
 const actual=texts.map(t=>InterTextFoundation.layout(t,policy,ProductCanvasFoundation.copyText).height),expected=anchors.map(a=>a.height*dimensions.height/dimensions.sourceHeight);
 actual.forEach((h,i)=>{if(!(['verified-ink-mask','reviewed-visible-ink'].includes(anchors[i].measurementKind)||(anchors[i].measurementKind==='segmented-ink'&&anchors[i].confidence>=.9))||!anchors[i].sourceHash||h/expected[i]<.8||h/expected[i]>1.2)throw Error('Reference ink scale not preserved');});
 for(let i=1;i<actual.length;i++){const ratio=(actual[0]/actual[i])/(expected[0]/expected[i]);if(ratio<.8||ratio>1.2)throw Error('Reference main/subtitle hierarchy drift');}
 const scale=dimensions.height/dimensions.sourceHeight,gaps=[];
 for(let i=1;i<texts.length;i++){
  const previous=anchors[i-1],current=anchors[i];
  // Only vertically adjacent roles; side-by-side regions have no vertical gap contract.
  if(current.y<previous.y+previous.height)continue;
  const expectedGap=(current.y-previous.y-previous.height)*scale;
  const actualGap=texts[i].box.y-texts[i-1].box.y-actual[i-1];
  const tolerance=Math.max(2,.2*expected[i-1]);
  if(Math.abs(actualGap-expectedGap)>tolerance)throw Error('Reference text group spacing drift');
  gaps.push({from:i-1,to:i,expectedGap,actualGap,tolerance});
 }
 return {passed:true,actual,expected,gaps,requiresSemanticReview:true};
}};
