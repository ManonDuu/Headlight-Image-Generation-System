require_relative 'product-asset-provider'
eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
out=ROOT+'/diagnostics/visible-fit/output';FileUtils.mkdir_p(out);checks=[];ok=lambda{|v,m|raise m unless v;checks<<m}
real=JSON.parse(File.read(ROOT+'/diagnostics/preserve-copy/analysis-plan-OFFLINE-ONLY.json'))['productFrozen'];a=ProductAssetProvider.prepare(real)
parts=JSON.parse(a['body'])['contents'][0]['parts'];ok.call(parts.count{|p|p['inlineData']}==1&&parts.last['inlineData']['data']==DirectImagePlan.image_part(real,'reference')['data'],'analysis sends reference only, never actual product')
ok.call(a['binding']['budgetMicroUSD']==20000&&a['binding']['retries']==0,'analysis one-call budget and no retries')
Dir.mktmpdir('product-auto-') do |dir|
 server=nil;chrome=nil;fixturepath=nil
 begin
  # Real cached same-source reference analysis/background + actual product; no new model output claimed.
  options=real['options'].merge('sceneMode'=>'change');ref=File.binread(ROOT+'/assets/listing-canbus-reference/reference.png');product=File.binread(ROOT+'/diagnostics/h11-regression/H11.png');frozen=DirectImagePlan.prepare(ref,product,options,mock:false)
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
  setfile=lambda{|selector,path|doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:selector)['nodeId'];c.call('DOM.setFileInputFiles',nodeId:node,files:[path])}
  setfile.call('#source',ROOT+'/assets/listing-canbus-reference/reference.png');setfile.call('#product',ROOT+'/diagnostics/h11-regression/H11.png');c.wait("!$('freeze').disabled")
  c.eval_js("$('productName').value='Supplied silver LED bulb';$('productScene').value='change';$('mode').value='preserve-reference';$('freeze').onclick()")
  alpha=c.eval_js("(async()=>{const L=LocalProductCompose,A=ProductAutoCompose;const raw=Uint8Array.from(atob(productRef.data.split(',')[1]),c=>c.charCodeAt(0));const real=await L.prepare(new Blob([raw]));const before=real.original.data.slice();A.soften(real);const unchanged=before.every((v,i)=>v===real.original.data[i]);const cv=L.canvas(32,48),cx=cv.getContext('2d');cx.fillStyle='rgba(80,120,160,.5)';cx.fillRect(8,12,12,20);const b=await L.png(cv),t=await L.prepare(b);const original=t.original.data;A.soften(t);const after=t.preview().getContext('2d').getImageData(0,0,32,48).data;return {realRGBUnchanged:unchanged,transparentAlphaUnchanged:original.every((v,i)=>i%4!==3||v===after[i]),transparentOrigin:t.origin,unresolvedWhitePixels:real.unresolvedWhitePixels};})()")
  ok.call(alpha['realRGBUnchanged']&&alpha['transparentAlphaUnchanged']&&alpha['transparentOrigin']=='original-alpha','real original RGB untouched and transparent PNG original alpha retained')
  File.write(out+'/alpha-regression.json',JSON.pretty_generate(alpha))
  geometry=c.eval_js(<<~JS)
  (async()=>{
    const L=LocalProductCompose,A=ProductAutoCompose,F=ProductCanvasFoundation,records=[];
    const slot={x:80,y:30,width:440,height:900};
    for(const [path,encoded] of #{JSON.generate(['assets/module-two-history/product.jpg','diagnostics/h11-regression/H11.png'].map{|p|[p,Base64.strict_encode64(File.binread(ROOT+'/'+p))]})}){
      const source=new Blob([Uint8Array.from(atob(encoded),c=>c.charCodeAt(0))]),raw=await L.prepare(source);A.soften(raw);
      const bounds=F.visibleBounds(raw.original,raw.alpha),cut=L.canvas(bounds.width,bounds.height);cut.getContext('2d').drawImage(raw.preview(),-bounds.x,-bounds.y);
      const expected={};
      for(const variant of ['transparent','padded-transparent','wide-transparent','tall-transparent','white','wide-white','tall-white']){
        const wide=variant.includes('wide'),tall=variant.includes('tall'),pad=variant==='transparent'?0:120;
        const cv=L.canvas(cut.width+pad*2+(wide?2400:0),cut.height+pad*2+(tall?2400:0)),cx=cv.getContext('2d');
        const dx=pad+(wide?1100:0),dy=pad+(tall?1100:0);
        if(variant.includes('white')){cx.fillStyle='white';cx.fillRect(0,0,cv.width,cv.height);}cx.drawImage(cut,dx,dy);
        const blob=await L.png(cv),a=await L.prepare(blob),before=a.original.data.slice();A.soften(a);
        if(!before.every((v,i)=>v===a.original.data[i]))throw Error('RGB changed');
        const b=F.visibleBounds(a.original,a.alpha),t=A.fitVisible(b,slot),bottom=t.y+(b.y+b.height)*t.scale;
        const shadow=A.contactShadow(a,600,1000,t.x,t.y,t.scale);
        if(Math.abs(bottom-930)>1e-7||Math.abs(shadow.bounds.cy-930)>1e-7)throw Error('bottom anchor failed');
        const kind=variant.includes('white')?'white':'transparent';if(expected[kind]!==undefined&&Math.abs(expected[kind]-t.scale)>1e-9)throw Error('padding changed scale');expected[kind]=t.scale;
        const mask=await L.png(a.mask),session=new F.Session({enabled:true,policy:{modes:{},forbiddenSource:'headlights?'}});
        await session.load(blob,{sourceHash:a.sourceHash,mask,maskHash:await F.sha(mask)});session.transform({...t,rotation:0});
        await session.layers({background:L.canvas(600,1000),shadow:shadow.layer,backgroundConfirmedClean:true});
        const result=await session.exportPNG({width:600,height:1000});
        records.push({path,variant,canvas:[cv.width,cv.height],visible:b,scale:t.scale,bottom,shadow:shadow.bounds,rgbUnchanged:true,exported:!!result.blob});
      }
    }
    return records;
  })()
  JS
  ok.call(geometry.size==14,'9005 and H11 transparent/white padding and extreme canvases preserve visible support anchor and RGB')
  File.write(out+'/geometry-regression.json',JSON.pretty_generate(geometry))
  status=c.eval_js("$('lpStatus').textContent");raise status unless status.include?('已自动合成')
  ok.call(c.eval_js("!$('lpAdjust').open&&!$('lpDownload').hidden"),'normal entry auto-composes with optional editor collapsed, no mask checkbox')
  c.eval_js("$('lpDownload').download='automatic-product.png';$('lpDownload').click();$('lpRecord').click()")
  100.times{break if Dir[dir+'/downloads/*.png'].any?&&Dir[dir+'/downloads/*.json'].any?;sleep 0.1}
  png=Dir[dir+'/downloads/*.png'].first;m=JSON.parse(File.read(Dir[dir+'/downloads/*.json'].first));ok.call(m['sourcePixelsReused']&&m['newModelCalls']==0&&m['alphaOnlyContourPixels']>0,'actual product reused, alpha-only contour improvement, no new model calls');ok.call(Digest::SHA256.file(png).hexdigest==m['outputHash'],'automatic output download hash')
  FileUtils.cp(png,out+'/automatic-product-cached-scene.png');File.write(out+'/automatic-manifest.json',JSON.pretty_generate(m))
  c.eval_js("$('productScene').value='keep';$('freeze').onclick()");ok.call(c.eval_js("$('lpStatus').textContent.includes('未获新授权')&&!$('lpAdjust').open"),'missing matching cache prepares one bounded plan without editor or paid dispatch')
  ok.call(Dir[dir+'/jobs/*/state.json'].empty?,'no direct-generation job created')
  File.write(out+'/result.json',JSON.pretty_generate({checks:checks,newExternalCalls:0,realCacheReused:true,fixtureProductLayout:true}));puts JSON.generate({checks:checks.size,newExternalCalls:0})
 ensure
  [chrome,server].compact.each{|pid|Process.kill('TERM',pid)rescue nil;Process.wait(pid)rescue nil};FileUtils.rm_rf(fixturepath) if fixturepath
 end
end
