(()=>{
 const R=ReferenceTypeScale,F=ProductCanvasFoundation,P=CANVAS_TEST_POLICY;let checks=0;const ok=(v,m)=>{if(!v)throw Error(m);checks++;},reject=(fn,m)=>{let no=false;try{fn()}catch(e){no=true}ok(no,m);};
 const cases=[{w:700,h:500,out:[1400,1000],texts:['Everyday Comfort','Made for the moments that matter'],sizes:[44,24]}, {w:900,h:600,out:[1800,1200],texts:['Room To Create','A place for your next idea'],sizes:[56,28]}, {w:640,h:480,out:[1280,960],texts:['Keep Things Organized','Find what you need with ease'],sizes:[42,20]}];
 for(const fixture of cases){const anchors=[],texts=[];fixture.texts.forEach((s,i)=>{const c=document.createElement('canvas');c.width=fixture.w;c.height=fixture.h;const ctx=c.getContext('2d');ctx.font=`${i?400:700} ${fixture.sizes[i]}px PictureOpsInter41`;ctx.fillText(s,30,70+i*100);const anchor=R.measureMask(ctx.getImageData(0,0,c.width,c.height),{sourceHash:'synthetic-'+fixture.w,verifiedTextOnly:true});anchors.push(anchor);texts.push({text:s,mode:'ai-rewrite',role:i?'subtitle':'title',fontSize:12,weight:i?400:700,style:'normal',lineHeightPx:20,align:'left',color:'#fff',box:{x:0,y:0,width:fixture.out[0],height:100}});});
 const dimensions={sourceWidth:fixture.w,sourceHeight:fixture.h,width:fixture.out[0],height:fixture.out[1],policy:P};
 reject(()=>R.validateGroup(texts,anchors,dimensions,P),'small but nonoverflowing typography must fail inheritance');
 const fitted=texts.map((t,i)=>R.fit(t,anchors[i],dimensions));ok(R.validateGroup(fitted.map(x=>x.text),anchors,dimensions,P).passed,'reference proportions inherited');
 const shifted=structuredClone(fitted.map(x=>x.text));shifted[1].box.y+=fixture.out[1]/3;reject(()=>R.validateGroup(shifted,anchors,dimensions,P),'same sizes but wrong spacing rejected');
 fitted.forEach(x=>ok(x.audit.heightRatio>=.8&&x.audit.heightRatio<=1.2,'measured height range'));
 reject(()=>R.fit(texts[0],{...anchors[0],lineCount:2},dimensions),'multiline requires per-line evidence');
 reject(()=>R.validateGroup(texts,[{...anchors[0],height:NaN},anchors[1]],dimensions,P),'nonfinite evidence rejected');
 reject(()=>R.fit(texts[0],{...anchors[0],measurementKind:'model-bbox'},dimensions),'model bbox cannot claim visible ink');
 }
 reject(()=>R.measureMask(new ImageData(2,2),{sourceHash:'s'}),'unverified mask rejected');
 return {checks,cases:cases.length,modelCalls:0,fixtureOnly:true,automaticTextExtraction:false};
})()
