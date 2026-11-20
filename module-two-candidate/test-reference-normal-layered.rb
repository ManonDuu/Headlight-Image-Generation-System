require_relative 'product-asset-provider'
eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
mode=ENV.fetch('COPY_MODE','ai-rewrite');out=ROOT+'/diagnostics/reference-normal-layered/'+mode;FileUtils.mkdir_p(out);checks=[];ok=lambda{|v,m|raise m unless v;checks<<m}
base=JSON.parse(File.read(ROOT+'/diagnostics/preflight-wire-20261018/analysis-plan.json'))['frozen'];checks=[]
Dir.mktmpdir('product-auto-') do |dir|
 server=nil;chrome=nil;fixturepath=nil
 begin
  # Real cached same-source reference analysis/background + actual product; no new model output claimed.
  options=DefaultProductFacts.apply(base['options'].merge('businessSpec'=>DirectImagePlan::SPEC,'mode'=>mode));if mode=='custom';options.merge!('layoutMode'=>'auto-layout','layoutTone'=>'adjust-color','color'=>'#00A6A6','customCopy'=>'CANBUS Ready');end;ref=File.binread(ROOT+'/assets/amazon-example/reference.jpg');frozen=DirectImagePlan.prepare(ref,nil,options,mock:false);options=frozen['options']
  layout=JSON.parse(File.read(ROOT+'/diagnostics/preflight-wire-20261018/candidate-policy-replay.json'))['plan'];bg=File.binread(ROOT+'/diagnostics/authorized-background-20261018/background.jpg')
  if mode=='remove-all-copy';layout['text']=[];elsif mode=='custom';layout['text']=layout['text'].first(1);layout['text'][0]['text']='CANBUS Ready';end;layout['text'].each{|t|t['mode']=mode};
  package={'sourceHash'=>Digest::SHA256.hexdigest(ref),'productHash'=>nil,'options'=>options,'background'=>{'base64'=>Base64.strict_encode64(bg),'mime'=>'image/jpeg'},'backgroundHash'=>Digest::SHA256.hexdigest(bg),'backgroundOrigin'=>'clean-background-only','proposal'=>{'layout'=>layout},'fixtureOnly'=>true,'backgroundTestSource'=>'existing-real-cache-offline-replay','visualAcceptance'=>'not-evaluated'}
  fixturepath=ROOT+'/product-asset-cache/'+frozen['binding']['requestHash'];raise 'existing fixture cache protected' if File.exist?(fixturepath);FileUtils.mkdir_p(fixturepath);File.write(fixturepath+'/package.json',JSON.generate(package))
  begin;ProductAssetProvider.cache(frozen,ROOT+'/product-asset-cache');raise 'fixture accepted live';rescue RuntimeError=>e;raise unless e.message=='fixture cache forbidden';checks<<'fixture cache excluded from live';end
  server=Process.spawn({'GEMINI_API_KEY'=>nil},'/usr/bin/ruby',ROOT+'/bridge-server.rb','--mock','--port','8792','--data',dir+'/jobs',out:dir+'/server.log',err:dir+'/server.err')
  100.times{begin;break if Net::HTTP.new('127.0.0.1',8792,nil).get('/api/session').code=='200';rescue SystemCallError;end;sleep 0.1}
  chrome=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9249',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9249,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1}
  c=CDP.new(pages.find{|p|p['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable');c.call('Network.setBlockedURLs',urls:['https://*','*/api/generate*','*/api/analyze*','*/api/freeze','*/api/generic/*','*/api/experiment/*'])
  Dir.mkdir(dir+'/downloads');c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:dir+'/downloads');c.call('Page.navigate',url:'http://127.0.0.1:8792/');c.wait('!!session?.history');c.eval_js("enterModule('reference-reconstruction')")
  setfile=lambda{|selector,path|doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:selector)['nodeId'];c.call('DOM.setFileInputFiles',nodeId:node,files:[path])}
  setfile.call('#source',ROOT+'/assets/amazon-example/reference.jpg');c.wait("!$('freeze').disabled")
  c.eval_js("$('mode').value=#{JSON.generate(mode)};$('copy').value='CANBUS Ready';$('layout').value=#{JSON.generate(options['layoutMode'])};$('tone').value=#{JSON.generate(options['layoutTone'])};$('color').value='#00A6A6';")
  actual=c.eval_js('businessRequest()');actual_opts=actual.reject{|k,_|%w[imageBase64 productImageBase64 sourceHash productHash budgetMicroUSD].include?(k)};actual_frozen=DirectImagePlan.prepare(ref,nil,DefaultProductFacts.apply(actual_opts),mock:false);FileUtils.rm_rf(fixturepath);fixturepath=ROOT+'/product-asset-cache/'+actual_frozen['binding']['requestHash'];raise 'existing cache protected' if File.exist?(fixturepath);package['options']=actual_frozen['options'];FileUtils.mkdir_p(fixturepath);File.write(fixturepath+'/package.json',JSON.generate(package));c.eval_js("$('freeze').onclick()")
  status=c.eval_js("$('lpStatus').textContent");raise status unless status.include?('已自动合成')
  ok.call(c.eval_js("!$('lpAdjust').open&&!$('lpDownload').hidden"),'normal entry auto-composes with optional editor collapsed, no mask checkbox')
  c.eval_js("$('lpDownload').download='automatic-product.png';$('lpDownload').click();$('lpRecord').click()")
  100.times{break if Dir[dir+'/downloads/*.png'].any?&&Dir[dir+'/downloads/*.json'].any?;sleep 0.1}
  png=Dir[dir+'/downloads/*.png'].first;m=JSON.parse(File.read(Dir[dir+'/downloads/*.json'].first));ok.call(m['interReady']&&m['newModelCalls']==0&&m['workflow']=='automatic-reference-local-text','actual product reused, alpha-only contour improvement, no new model calls');ok.call(Digest::SHA256.file(png).hexdigest==m['outputHash'],'automatic output download hash')
  FileUtils.cp(png,out+'/automatic-product-cached-scene.png');File.write(out+'/automatic-manifest.json',JSON.pretty_generate(m))
  c.eval_js("$('ratio').value='1:1';$('freeze').onclick()");ok.call(c.eval_js("$('lpStatus').textContent.includes('未获新授权')&&!$('lpAdjust').open"),'missing matching cache: '+c.eval_js("$('lpStatus').textContent"))
  ok.call(Dir[dir+'/jobs/*/state.json'].empty?,'no direct-generation job created')
  File.write(out+'/result.json',JSON.pretty_generate({checks:checks,newExternalCalls:0,realCacheReused:true,fixtureProductLayout:true}));puts JSON.generate({checks:checks.size,newExternalCalls:0})
 ensure
  [chrome,server].compact.each{|pid|Process.kill('TERM',pid)rescue nil;Process.wait(pid)rescue nil};FileUtils.rm_rf(fixturepath) if fixturepath
 end
end
