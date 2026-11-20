eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
out=ROOT+'/diagnostics/background-geometry';fixtures=JSON.parse(File.read(out+'/fixtures.json'))
Dir.mktmpdir('geometry-review-browser-') do |dir|
 pid=nil
 begin
  pid=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9249',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9249,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1}
  c=CDP.new(pages.find{|p|p['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable');c.call('Network.setBlockedURLs',urls:['https://*','*/api/generate*','*/api/analyze*','*/api/analysis*','*/api/freeze','*/api/generic/*','*/api/direct/*','*/api/experiment/*','*/api/maintenance/*'])
  c.call('Page.navigate',url:'http://127.0.0.1:8773/');c.wait("typeof globalThis.ProductAutoCompose?.requireBackgroundGeometry==='function'")
  c.eval_js('globalThis.GFIX='+JSON.generate(fixtures))
  c.eval_js('globalThis.SOURCE64='+JSON.generate(Base64.strict_encode64(File.binread(ROOT+'/diagnostics/final-readiness/deer-road.png'))))
  c.eval_js('globalThis.FARM64='+JSON.generate(Base64.strict_encode64(File.binread(out+'/farm-background.png'))))
  result=c.eval_js(<<~JS)
  (async()=>{
   const checks=[],run=async(a,l=GFIX.layout,rendered=l)=>{const p={proposal:{layout:l},backgroundHash:a.backgroundHash,geometryAudit:a};return ProductAutoCompose.requireBackgroundGeometry(p,a.sourceHash,1122,1402,rendered)},reject=async(name,a,l=GFIX.layout,rendered=l)=>{let failed=false;try{await run(a,l,rendered)}catch(e){failed=true}if(!failed)throw Error('Accepted invalid '+name);checks.push(name)};
   await run(GFIX.original);checks.push('same original geometry accepted only as fixture');await reject('farm rejected',GFIX.shifted);
   let a=structuredClone(GFIX.shifted);a.verdict='pass';await reject('farm displacement rejects false pass flag',a);
   await run(GFIX.unframed);checks.push('reviewed unframed accepted');a=structuredClone(GFIX.unframed);delete a.unframedClearanceReviewed;await reject('unframed not automatic bypass',a);
   for(const [k,v] of [['reviewMethod','low-texture-bands'],['verdict','uncertain'],['layoutHash','0'.repeat(64)],['outputSize',[1122,1401]]]){a=structuredClone(GFIX.original);a[k]=v;await reject(k+' mutation blocked',a)}
   let rendered=structuredClone(GFIX.layout);rendered.text[2].box.y=800;await reject('post-placement label outside owned container blocked',GFIX.original,GFIX.layout,rendered);
   const measure=async(encoded)=>{const blob=new Blob([Uint8Array.from(atob(encoded),c=>c.charCodeAt(0))]),im=await createImageBitmap(blob),cv=document.createElement('canvas');cv.width=im.width;cv.height=im.height;const ctx=cv.getContext('2d');ctx.drawImage(im,0,0);im.close();const data=ctx.getImageData(0,0,cv.width,cv.height).data;const ranges=[];for(const [kind,lo,hi] of [['yellow-top',170,215],['yellow-bottom',760,810],['gray-top',785,835],['gray-bottom',1335,1370]]){let rows=[];for(let y=lo;y<=hi;y++){const i=(y*cv.width+500)*4,[r,g,b]=data.slice(i,i+3);const yes=kind.startsWith('yellow')?r>170&&g>130&&b<100:Math.max(r,g,b)-Math.min(r,g,b)<12&&r>65&&r<180;if(yes)rows.push(y)}ranges.push({kind,rows})}return {sha256:await ProductCanvasFoundation.sha(blob),size:[cv.width,cv.height],ranges}};
   return {checks,source:await measure(SOURCE64),farm:await measure(FARM64),modelCalls:0,heuristicScanIsCandidateOnly:true};
  })()
  JS
  File.write(out+'/browser-regression.json',JSON.pretty_generate(result));puts JSON.pretty_generate(result)
 ensure
  Process.kill('TERM',pid)rescue nil;Process.wait(pid)rescue nil
 end
end
