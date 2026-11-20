require_relative 'product-asset-provider'
eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
out=ROOT+'/diagnostics/product-auto-20261018';FileUtils.mkdir_p(out);checks=[];ok=lambda{|v,m|raise m unless v;checks<<m}
real=JSON.parse(File.read(ROOT+'/diagnostics/today-real-input-readiness/product-replacement-live-plan.json'));a=ProductAssetProvider.prepare(real)
parts=JSON.parse(a['body'])['contents'][0]['parts'];ok.call(parts.count{|p|p['inlineData']}==1&&parts.last['inlineData']['data']==DirectImagePlan.image_part(real,'reference')['data'],'analysis sends reference only, never actual product')
ok.call(a['binding']['budgetMicroUSD']==20000&&a['binding']['retries']==0,'analysis one-call budget and no retries')
Dir.mktmpdir('product-auto-') do |dir|
 server=nil;chrome=nil;fixturepath=nil
 begin
  # Real cached same-source reference analysis/background + actual product; no new model output claimed.
  options=real['options'].merge('sceneMode'=>'change');ref=File.binread(ROOT+'/assets/amazon-example/reference.jpg');product=File.binread(ROOT+'/assets/module-two-history/product.jpg');frozen=DirectImagePlan.prepare(ref,product,options,mock:false)
  layout=JSON.parse(File.read(ROOT+'/diagnostics/preflight-wire-20261018/candidate-policy-replay.json'))['plan'];bg=File.binread(ROOT+'/diagnostics/authorized-background-20261018/background.jpg')
  package={'sourceHash'=>Digest::SHA256.hexdigest(ref),'productHash'=>Digest::SHA256.hexdigest(product),'options'=>options,'background'=>{'base64'=>Base64.strict_encode64(bg),'mime'=>'image/jpeg'},'backgroundHash'=>Digest::SHA256.hexdigest(bg),'backgroundOrigin'=>'clean-background-only','proposal'=>{'layout'=>layout},'fixtureOnly'=>true,'visualAcceptance'=>'not-evaluated'}
  fixturepath=ROOT+'/product-asset-cache/'+frozen['binding']['requestHash'];raise 'existing fixture cache protected' if File.exist?(fixturepath);FileUtils.mkdir_p(fixturepath);File.write(fixturepath+'/package.json',JSON.generate(package))
  begin;ProductAssetProvider.cache(frozen,ROOT+'/product-asset-cache');raise 'fixture accepted live';rescue RuntimeError=>e;raise unless e.message=='fixture cache forbidden';checks<<'fixture cache excluded from live';end
  server=Process.spawn({'GEMINI_API_KEY'=>nil},'/usr/bin/ruby',ROOT+'/bridge-server.rb','--mock','--port','8792','--data',dir+'/jobs',out:dir+'/server.log',err:dir+'/server.err')
  100.times{begin;break if Net::HTTP.new('127.0.0.1',8792,nil).get('/api/session').code=='200';rescue SystemCallError;end;sleep 0.1}
  chrome=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9249',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9249,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1}
  c=CDP.new(pages.find{|p|p['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable');c.call('Network.setBlockedURLs',urls:['https://*','*/api/generate*','*/api/analyze*','*/api/freeze','*/api/generic/*','*/api/experiment/*'])
  Dir.mkdir(dir+'/downloads');c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:dir+'/downloads');c.call('Page.navigate',url:'http://127.0.0.1:8792/');c.wait('!!session?.history');c.eval_js("enterModule('product-replacement')")
  setfile=lambda{|selector,path|doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:selector)['nodeId'];c.call('DOM.setFileInputFiles',nodeId:node,files:[path])}
  setfile.call('#source',ROOT+'/assets/amazon-example/reference.jpg');setfile.call('#product',ROOT+'/assets/module-two-history/product.jpg');c.wait("!$('freeze').disabled")
  c.eval_js("$('productName').value='Supplied silver LED bulb';$('productScene').value='change';$('freeze').onclick()")
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
