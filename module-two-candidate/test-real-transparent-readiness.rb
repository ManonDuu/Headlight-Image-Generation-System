require_relative 'product-asset-provider'
eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
out=ROOT+'/diagnostics/final-readiness/transparent-output';FileUtils.mkdir_p(out);checks=[];ok=lambda{|v,m|raise m unless v;checks<<m}
real=JSON.parse(File.read(ROOT+'/diagnostics/preserve-copy/analysis-plan-OFFLINE-ONLY.json'))['productFrozen'];a=ProductAssetProvider.prepare(real)
parts=JSON.parse(a['body'])['contents'][0]['parts'];ok.call(parts.count{|p|p['inlineData']}==1&&parts.last['inlineData']['data']==DirectImagePlan.image_part(real,'reference')['data'],'analysis sends reference only, never actual product')
ok.call(a['binding']['budgetMicroUSD']==20000&&a['binding']['retries']==0,'analysis one-call budget and no retries')
Dir.mktmpdir('product-auto-') do |dir|
 server=nil;chrome=nil;fixturepath=nil
 begin
  # Real cached same-source reference analysis/background + actual product; no new model output claimed.
  options=real['options'].merge('sceneMode'=>'change');ref=File.binread(ROOT+'/assets/listing-canbus-reference/reference.png');product=File.binread(ROOT+'/diagnostics/final-readiness/9005-transparent.png');frozen=DirectImagePlan.prepare(ref,product,options,mock:false)
  layout=JSON.parse(File.read(ROOT+'/diagnostics/preserve-copy/proposal.json'))['layout'];bg=File.binread(ROOT+'/diagnostics/image-skill-composite/background.png')
  package={'sourceHash'=>Digest::SHA256.hexdigest(ref),'productHash'=>Digest::SHA256.hexdigest(product),'options'=>options,'background'=>{'base64'=>Base64.strict_encode64(bg),'mime'=>'image/png'},'backgroundHash'=>Digest::SHA256.hexdigest(bg),'backgroundOrigin'=>'clean-background-only','proposal'=>JSON.parse(File.read(ROOT+'/diagnostics/preserve-copy/proposal.json')),'layoutCanvasDimensions'=>real['trace']['expectedDimensions'],'backgroundTestSource'=>'image-skill-libfile_ea4f261250408191af8fff4db4a47f15','fixtureOnly'=>true,'visualAcceptance'=>'not-evaluated'}
  fixturepath=ROOT+'/product-asset-cache/'+frozen['binding']['requestHash'];raise 'existing fixture cache protected' if File.exist?(fixturepath);FileUtils.mkdir_p(fixturepath);File.write(fixturepath+'/package.json',JSON.generate(package))
  begin;ProductAssetProvider.cache(frozen,ROOT+'/product-asset-cache');raise 'fixture accepted live';rescue RuntimeError=>e;raise unless e.message=='fixture cache forbidden';checks<<'fixture cache excluded from live';end
  server=Process.spawn({'GEMINI_API_KEY'=>nil},'/usr/bin/ruby',ROOT+'/bridge-server.rb','--mock','--port','8792','--data',dir+'/jobs',out:dir+'/server.log',err:dir+'/server.err')
  100.times{begin;break if Net::HTTP.new('127.0.0.1',8792,nil).get('/api/session').code=='200';rescue SystemCallError;end;sleep 0.1}
  chrome=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9249',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9249,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1}
  c=CDP.new(pages.find{|p|p['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable');c.call('Network.setBlockedURLs',urls:['https://*','*/api/generate*','*/api/analyze*','*/api/freeze','*/api/generic/*','*/api/experiment/*'])
  Dir.mkdir(dir+'/downloads');c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:dir+'/downloads');c.call('Page.navigate',url:'http://127.0.0.1:8792/');c.wait('!!session?.history');c.eval_js("enterModule('product-replacement')")
  c.eval_js("globalThis.TEST_PREPARES=0;globalThis.TEST_FETCH=fetch;globalThis.fetch=(...a)=>{if(a[0]==='/api/product-assets/prepare')TEST_PREPARES++;return TEST_FETCH(...a)}")
  setfile=lambda{|selector,path|doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:selector)['nodeId'];c.call('DOM.setFileInputFiles',nodeId:node,files:[path])}
  setfile.call('#source',ROOT+'/assets/listing-canbus-reference/reference.png');setfile.call('#product',ROOT+'/diagnostics/final-readiness/9005-transparent.png');c.wait("!$('freeze').disabled")
  c.eval_js("$('productName').value='Supplied silver LED bulb';$('productScene').value='change';$('mode').value='preserve-reference';Promise.all([$('freeze').onclick(),$('freeze').onclick(),$('freeze').onclick()])")
  ok.call(c.eval_js('TEST_PREPARES')==1,'three repeated cached clicks start exactly one prepare/composition')
  alpha=c.eval_js("(async()=>{const L=LocalProductCompose,A=ProductAutoCompose;const raw=Uint8Array.from(atob(productRef.data.split(',')[1]),c=>c.charCodeAt(0));const real=await L.prepare(new Blob([raw]));const before=real.original.data.slice();A.soften(real);const originalAlpha=real.original.data.filter((v,i)=>i%4===3),actualAlpha=real.preview().getContext('2d').getImageData(0,0,real.c.width,real.c.height).data.filter((v,i)=>i%4===3);const alphaExact=originalAlpha.every((v,i)=>v===actualAlpha[i]);const unchanged=before.every((v,i)=>v===real.original.data[i]);const cv=L.canvas(32,48),cx=cv.getContext('2d');cx.fillStyle='rgba(80,120,160,.5)';cx.fillRect(8,12,12,20);const b=await L.png(cv),t=await L.prepare(b);const original=t.original.data;A.soften(t);const after=t.preview().getContext('2d').getImageData(0,0,32,48).data;return {realOriginalAlphaExact:alphaExact,realRGBUnchanged:unchanged,realOrigin:real.origin,realAlphaZero:originalAlpha.filter(v=>v===0).length,realAlphaPartial:originalAlpha.filter(v=>v>0&&v<255).length,transparentAlphaUnchanged:original.every((v,i)=>i%4!==3||v===after[i]),transparentOrigin:t.origin,unresolvedWhitePixels:real.unresolvedWhitePixels};})()")
  ok.call(alpha['realOriginalAlphaExact']&&alpha['realOrigin']=='original-alpha'&&alpha['realRGBUnchanged']&&alpha['transparentAlphaUnchanged']&&alpha['transparentOrigin']=='original-alpha','real original RGB untouched and transparent PNG original alpha retained')
  File.write(out+'/alpha-regression.json',JSON.pretty_generate(alpha))
  c.eval_js('globalThis.CLEARANCE_AUDIT='+JSON.generate(ReferenceAnchorReview.require!(package['sourceHash'],layout)))
  c.eval_js('globalThis.CLEARANCE_LAYOUT='+JSON.generate(layout))
  c.eval_js('globalThis.CLEARANCE_REF='+JSON.generate(Base64.strict_encode64(ref)))
  negatives=c.eval_js(<<~JS)
  (async()=>{
   const source=new Blob([Uint8Array.from(atob(CLEARANCE_REF),c=>c.charCodeAt(0))]),policy={forbiddenSource:'headlights?',modes:{'preserve-reference':{title:'Title Case'}}},result=[];
   const cases=[['retained OCR mismatch',a=>a.sourceBlocks.find(b=>b.id==='b2').matches=0],['retained duplicate',a=>a.sourceBlocks.find(b=>b.id==='b2').matches=2],['unreviewed clearance',a=>a.sourceBlocks.find(b=>b.id==='b3').clearanceReview='uncertain'],['omitted anchor reuse',a=>a.renderAnchors[0].blockId='b3'],['unreviewed multiline',a=>delete a.renderAnchors[0].lineMappingReview],['unreviewed textured glyphs',a=>delete a.renderAnchors[0].measurementReview],['changed measured glyph',a=>a.renderAnchors[0].measuredLines[1].y+=10]];
   for(const [name,change] of cases){const a=structuredClone(CLEARANCE_AUDIT);change(a);let failed=false;try{await ProductAutoCompose.applyTrustedAnchors({layout:structuredClone(CLEARANCE_LAYOUT)},CLEARANCE_LAYOUT,a,source,a.sourceHash,1122,1402,policy)}catch(e){failed=true}if(!failed)throw Error('Negative gate accepted: '+name);result.push(name)}return result;
  })()
  JS
  File.write(out+'/clearance-browser-negatives.json',JSON.pretty_generate(negatives));ok.call(negatives.size==7,'browser independently rejects retained OCR, clearance, multiline and glyph uncertainty')
  status=c.eval_js("$('lpStatus').textContent");raise status unless status.include?('已自动合成')
  ok.call(c.eval_js("!$('lpAdjust').open&&!$('lpDownload').hidden"),'normal entry auto-composes with optional editor collapsed, no mask checkbox')
  c.eval_js("$('lpDownload').download='automatic-product.png';$('lpDownload').click();$('lpRecord').click()")
  100.times{break if Dir[dir+'/downloads/*.png'].any?&&Dir[dir+'/downloads/*.json'].any?;sleep 0.1}
  png=Dir[dir+'/downloads/*.png'].first;m=JSON.parse(File.read(Dir[dir+'/downloads/*.json'].first));ok.call(m['sourcePixelsReused']&&m['newModelCalls']==0&&m['alphaOnlyContourPixels']==0&&m['automaticMask']=='original-alpha','actual product reused, alpha-only contour improvement, no new model calls');ok.call(Digest::SHA256.file(png).hexdigest==m['outputHash'],'automatic output download hash')
  FileUtils.cp(png,out+'/automatic-product-cached-scene.png');File.write(out+'/automatic-manifest.json',JSON.pretty_generate(m))
  ok.call(m.dig('selectedOptions','layoutMode')=='keep-reference'&&m.dig('preparedLayout','text').map{|t|t['text']}==["CANBUS\nREADY"],'keep-reference and CANBUS only; no percentage or compatibility copy')
  ac=m['anchorAudit']['changes'][0];ok.call(ac['lineCount']==2&&(m['preparedLayout']['text'][0]['lineHeightPx']-ac['sourceLineGap']*m['anchorAudit']['scale']).abs<0.001,'reviewed multiline source spacing survives bounded font fit')
  ok.call((m['contactShadow']['bounds']['cy']-m['productSlot']['y']-m['productSlot']['height']).abs<1e-7,'real transparent bottom/shadow aligned to test slot')
  c.eval_js("$('productScene').value='keep';$('freeze').onclick()");ok.call(c.eval_js("$('lpStatus').textContent.includes('未获新授权')&&!$('lpAdjust').open"),'missing matching cache prepares one bounded plan without editor or paid dispatch')
  ok.call(Dir[dir+'/jobs/*/state.json'].empty?,'no direct-generation job created')
  c.eval_js("(async()=>{const d=await new Promise(r=>{const q=indexedDB.open('picture-local-products',1);q.onsuccess=()=>r(q.result)});const records=await new Promise(r=>{const q=d.transaction('results').objectStore('results').getAll();q.onsuccess=()=>r(q.result)});await new Promise(r=>{const t=d.transaction('results','readwrite');const old={...records[0],id:'legacy-fixture-old-record',manifest:{...records[0].manifest}};delete old.manifest.selectedOptions;t.objectStore('results').put(old);t.oncomplete=r});d.close()})()")
  c.call('Page.reload');c.wait('!!session?.history&&document.readyState==="complete"');c.eval_js("enterModule('product-replacement')")
  setfile.call('#source',ROOT+'/assets/listing-canbus-reference/reference.png');setfile.call('#product',ROOT+'/diagnostics/final-readiness/9005-transparent.png');c.wait("!$('freeze').disabled")
  history_probe=c.eval_js("(async()=>{const d=await new Promise((r,j)=>{const q=indexedDB.open('picture-local-products',1);q.onsuccess=()=>r(q.result);q.onerror=()=>j(q.error)});const saved=await new Promise(r=>{const q=d.transaction('results').objectStore('results').getAll();q.onsuccess=()=>r(q.result)});d.close();$('ratio').value='1:1';await $('freeze').onclick();return {storedCount:saved.length,storedHashes:saved.map(x=>x.manifest.outputHash),historyButtons:$('lpHistory').querySelectorAll('button').length,historyPanelHidden:$('localProductEditor').hidden};})()")
  ok.call(history_probe['historyButtons']==2&&!history_probe['historyPanelHidden'],'cached-missing reload displays both current and legacy history')
  restored=c.eval_js("(async()=>{const old=Array.from($('lpHistory').querySelectorAll('button')).find(b=>b.textContent==='legacy-fixture-old-record');old.click();$('lpDownload').download='legacy-restored.png';$('lpDownload').click();await enterModule('reference-reconstruction');return {historyButtons:$('lpHistory').querySelectorAll('button').length,panelHidden:$('localProductEditor').hidden};})()")
  100.times{break if File.file?(dir+'/downloads/legacy-restored.png');sleep 0.1}
  ok.call(Digest::SHA256.file(dir+'/downloads/legacy-restored.png').hexdigest==m['outputHash']&&restored['historyButtons']==2&&!restored['panelHidden'],'legacy record restores download and module return keeps local history visible')
  ok.call(history_probe['storedCount']>0&&history_probe['storedHashes'].include?(m['outputHash']),'normal local result persists in IndexedDB after reload')
  File.write(out+'/reload-history.json',JSON.pretty_generate(history_probe))
  File.write(out+'/result.json',JSON.pretty_generate({checks:checks,newExternalCalls:0,realCacheReused:true,fixtureProductLayout:true}));puts JSON.generate({checks:checks.size,newExternalCalls:0})
 ensure
  [chrome,server].compact.each{|pid|Process.kill('TERM',pid)rescue nil;Process.wait(pid)rescue nil};FileUtils.rm_rf(fixturepath) if fixturepath
 end
end
