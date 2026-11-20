(async()=>{
 const source=new Blob([Uint8Array.from(atob(REPLAY_SOURCE),c=>c.charCodeAt(0))],{type:'image/jpeg'}),bmp=await createImageBitmap(source),dimensions=[bmp.width,bmp.height];bmp.close();
 const candidates=REPLAY_PROPOSAL.evidence.sourceBlocks.map((b,i)=>({sourceText:b.sourceText,role:['title','subtitle','body','brand'].includes(REPLAY_PROPOSAL.text[i].role)?REPLAY_PROPOSAL.text[i].role:'body',box:b.sourceBox}));
 let originalFailure=null;try{await ReferenceInkEvidence.extract(source,candidates);}catch(e){originalFailure=e.message;}
 // A whole-image search is a diagnostic, not clipping/rescaling the invalid boxes.
 const whole=await ReferenceInkEvidence.extract(source,[{sourceText:candidates.map(c=>c.sourceText).join('\n'),role:'body',box:{x:0,y:0,width:dimensions[0],height:dimensions[1]}}]);
 return {sourceHash:await ProductCanvasFoundation.sha(source),sourceDimensions:dimensions,modelCandidatesError:originalFailure,wholeImageSearch:{state:whole.state,confidence:whole.roles[0].confidence,expectedLines:candidates.length,detectedLines:whole.anchors.length,reasons:whole.roles[0].reasons},reliableRoleAnchorsRecovered:false,reason:'Whole-image segmentation does not establish OCR-to-role correspondence or original coordinate units',manualCoordinatesInserted:false,modelCalls:0};
})()
