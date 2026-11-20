(async()=>{
 const E=ReferenceInkEvidence,F=ProductCanvasFoundation,R=ReferenceTypeScale,P=CANVAS_TEST_POLICY;let checks=0;const ok=(v,m)=>{if(!v)throw Error(m);checks++;};
 const results=[];
 for(const [background,color,lines,size] of [['#172230','#ffffff',['Everyday Comfort'],40],['#eeeeee','#202020',['Room To Create','Space For Ideas'],32],['#dddddd','#2040b0',['Simple Storage','Easy To Organize'],28]]){
  const c=document.createElement('canvas');c.width=640;c.height=240;const ctx=c.getContext('2d');ctx.fillStyle=background;ctx.fillRect(0,0,c.width,c.height);ctx.font=`700 ${size}px PictureOpsInter41`;ctx.fillStyle=color;lines.forEach((s,i)=>ctx.fillText(s,25,60+i*60));
  const blob=await new Promise(r=>c.toBlob(r)),candidate={sourceText:lines.join('\n'),role:'title',box:{x:10,y:10,width:620,height:lines.length*60+10}},e=await E.extract(blob,[candidate]);
  results.push(e);ok(e.state==='measured','clean text expected measured: '+JSON.stringify(e.roles[0].reasons));ok(e.anchors.length===lines.length,'actual multiline count');ok(e.sourceHash===await F.sha(blob)&&e.sourceWidth===640,'source binding');ok(e.anchors.every(a=>a.height<=size+1&&a.height<candidate.box.height*.9),'ink height is not candidate box height');ok(e.anchors.every((a,i)=>{const m=ctx.measureText(lines[i]);return Math.abs(a.height-m.actualBoundingBoxAscent-m.actualBoundingBoxDescent)<=2;}),'segmented height matches independently rendered glyph metrics');
  const text={text:lines.join('\n'),mode:'custom',role:'title',fontSize:12,weight:700,style:'normal',lineHeightPx:18,align:'left',color,box:{x:0,y:0,width:1280,height:480}};
  const dimensions={sourceWidth:640,sourceHeight:240,width:1280,height:480,policy:P},fitted=R.fitRoles([text],e,dimensions);ok(fitted.fits.length===lines.length&&R.validateGroup(fitted.fits.map(f=>f.text),fitted.anchors,dimensions,P).passed,'multiline measured and fitted');
  ctx.fillStyle=color;ctx.fillRect(320,25,250,50);const contaminated=await E.extract(await new Promise(r=>c.toBlob(r)),[candidate]);ok(contaminated.state==='awaiting-typography-review','highlight must not become verified glyphs');
 }
 // Durable review/recovery without a paid request or a new source image.
 const c=document.createElement('canvas');c.width=640;c.height=240;const ctx=c.getContext('2d');ctx.fillStyle='#111';ctx.fillRect(0,0,640,240);ctx.font='700 40px PictureOpsInter41';ctx.fillStyle='#fff';ctx.fillText('Everyday Comfort',25,60);
 const reference=await new Promise(r=>c.toBlob(r)),sourceHash=await F.sha(reference),frozen={id:'local-fixture',module:'reference-reconstruction',sourceHash,ruleTrace:{module:'reference-reconstruction',expectedDimensions:[640,240],selectedOptions:{mode:'custom',customCopy:'Everyday Comfort',layoutMode:'keep-reference'}}};
 const records=new Map(),store={async read(id){return structuredClone(records.get(id));},async write(r,revision){if((records.get(r.id)?.revision??-1)!==revision)throw Error('CAS');records.set(r.id,structuredClone({...r,revision:revision+1}));return revision+1;}};
 const task=await ReferenceWorkflow.Workflow.create({enabled:true,store,reference,frozen,policy:P,fixtureOnly:true});ctx.fillStyle='#333';ctx.fillRect(0,0,640,240);const background=await new Promise(r=>c.toBlob(r));
 const plan={text:[{text:'Everyday Comfort',mode:'custom',role:'title',fontSize:12,weight:700,style:'normal',lineHeightPx:18,align:'left',color:'#fff',box:{x:0,y:0,width:640,height:100}}]};
 await task.supply({background,plan,evidence:{sourceHash,backgroundHash:await F.sha(background),planHash:await ReferenceWorkflow.hashJSON(plan),reviewer:'fixture',note:'programmatic',sceneReconstructed:true,oldCopyAbsent:true,layoutReviewed:true,factsReviewed:true}});
 await task.compose();ok(task.status.state==='awaiting-typography-review','missing regions is recoverable');
 await task.measureTypography([{sourceText:'Everyday Comfort',role:'title',box:{x:0,y:130,width:620,height:80}}]);ok(task.status.state==='awaiting-typography-review','empty crop pending');
 const resumed=await ReferenceWorkflow.Workflow.open({enabled:true,store,id:task.status.id,policy:P});
 await resumed.measureTypography([{sourceText:'Everyday Comfort',role:'title',box:{x:10,y:10,width:620,height:70}}]);ok(resumed.status.state==='ready-to-compose','adjusted localization resumes');await resumed.compose();ok(resumed.status.state==='candidate','recovered workflow produces actual local output');
 return {checks,scenes:results.length,multilineScenes:2,externalRequests:0,sourceTextRecognizedLocally:false,evidence:results};
})()
