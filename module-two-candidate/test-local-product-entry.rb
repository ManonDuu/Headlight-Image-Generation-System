eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
out=ROOT+'/diagnostics/product-optional-editor-20261018';FileUtils.mkdir_p(out);checks=[]
ok=lambda{|v,m|raise m unless v;checks<<m}
Dir.mktmpdir('local-product-') do |dir|
 server=nil;chrome=nil
 begin
  server=Process.spawn({'GEMINI_API_KEY'=>nil},'/usr/bin/ruby',ROOT+'/bridge-server.rb','--mock','--port','8792','--data',dir+'/jobs',out:dir+'/server.log',err:dir+'/server.err')
  100.times{begin;break if Net::HTTP.new('127.0.0.1',8792,nil).get('/api/session').code=='200';rescue SystemCallError;end;sleep 0.1}
  chrome=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9249',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9249,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1}
  c=CDP.new(pages.find{|p|p['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable');c.call('Network.setBlockedURLs',urls:['https://*','*/api/generate*','*/api/analyze*','*/api/freeze','*/api/generic/*','*/api/internal/*','*/api/experiment/*'])
  Dir.mkdir(dir+'/downloads');c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:dir+'/downloads');c.call('Page.navigate',url:'http://127.0.0.1:8792/');c.wait('!!session?.history')
  c.eval_js("enterModule('product-replacement')")
  setfile=lambda{|selector,path|doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:selector)['nodeId'];c.call('DOM.setFileInputFiles',nodeId:node,files:[path])}
  setfile.call('#source',ROOT+'/assets/module-two-history/reference.jpg');setfile.call('#product',ROOT+'/assets/module-two-history/product.jpg');c.wait("!$('freeze').disabled")
  c.eval_js("$('productName').value='LED Bulb';$('productScene').value='change';$('freeze').onclick().then(()=>{$('lpAdjust').open=true})");c.wait("$('lpPreview').height>1000&&$('lpStatus').textContent.includes('位置预览')")
  ok.call(c.eval_js('!job'),'normal product entry did not freeze model job')
  c.eval_js("$('lpExport').click()");c.wait("$('lpStatus').textContent.includes('核对产品边缘')");ok.call(c.eval_js("$('lpDownload').hidden"),'unconfirmed white mask cannot export')
  c.eval_js("$('lpMaskOK').checked=true;$('lpExport').click()");c.wait("!$('lpDownload').hidden&&$('lpStatus').textContent.includes('已保存')")
  c.eval_js("$('lpDownload').click();$('lpRecord').click()")
  100.times{break if Dir[dir+'/downloads/*.png'].any?&&Dir[dir+'/downloads/*.json'].any?;sleep 0.1}
  png=Dir[dir+'/downloads/*.png'].first;manifest=Dir[dir+'/downloads/*.json'].first;raise 'download missing' unless png&&manifest
  m=JSON.parse(File.read(manifest));ok.call(m['sourcePixelsReused']&&m['modelCalls']==0&&m['sourceHash']=='9aa07d8850e99e2cf3326d62d060a63151d38ba4a7c5998d9d058f6cb1ffb6c5','actual product source hash reused; zero model calls')
  ok.call(Digest::SHA256.file(png).hexdigest==m['outputHash'],'download hash matches composition');FileUtils.cp(png,out+'/product-original-composite.png');FileUtils.cp(manifest,out+'/manifest.json')
  # White removal must never change retained RGB; brush restoration must use original alpha.
  raw=Base64.strict_encode64(File.binread(ROOT+'/assets/module-two-history/product.jpg'))
  stats=c.eval_js("(async()=>{const a=await LocalProductCompose.prepare(new Blob([Uint8Array.from(atob('#{raw}'),c=>c.charCodeAt(0))]));const p=a.preview().getContext('2d').getImageData(0,0,a.c.width,a.c.height).data;let mismatch=0,retained=0;for(let i=0;i<a.alpha.length;i++)if(a.alpha[i]===255){retained++;for(let k=0;k<3;k++)if(p[i*4+k]!==a.original.data[i*4+k])mismatch++;}a.brush(300,300,10,false);const erased=a.alpha[300*a.c.width+300];a.brush(300,300,10,true);return {mismatch,retained,removed:a.removed,erased,restored:a.alpha[300*a.c.width+300]};})()")
  ok.call(stats['mismatch']==0&&stats['retained']>100000&&stats['removed']>100000,'all retained source RGB pixels unchanged before uniform resampling');ok.call(stats['erased']==0&&stats['restored']==255,'erase and restore only affect mask alpha')
  c.eval_js("$('productScene').value='keep';$('lpExport').click()");c.wait("$('lpStatus').textContent.includes('干净背景')");ok.call(true,'keep-scene requires clean background; old product never silently reused')
  setfile.call('#lpBackground',ROOT+'/diagnostics/authorized-background-20261018/background.jpg');c.wait("!$('lpClean').checked");c.eval_js("$('lpClean').checked=true;$('lpClean').dispatchEvent(new Event('input'));$('lpExport').onclick()");c.wait("$('lpStatus').textContent.includes('已保存')");c.eval_js("$('lpDownload').download='existing-background.png';$('lpDownload').click()");100.times{break if Dir[dir+'/downloads/*.png'].size==2;sleep 0.1};bg_png=(Dir[dir+'/downloads/*.png']-[png]).first;raise 'background export missing' unless bg_png;FileUtils.cp(bg_png,out+'/product-existing-clean-background.png');ok.call(true,'existing clean background composites actual source with no model')
  extra=c.eval_js("(async()=>{const c=LocalProductCompose.canvas(20,20),x=c.getContext('2d');x.fillStyle='rgba(205,34,68,0.5)';x.fillRect(5,5,10,10);const b=await LocalProductCompose.png(c),a=await LocalProductCompose.prepare(b);const r=await LocalProductCompose.compose(a,{width:100,height:100,x:20,y:20,scale:2,backgroundConfirmedClean:true,maskConfirmed:true});let cropped=false;try{await LocalProductCompose.compose(a,{width:100,height:100,x:90,y:20,scale:2,backgroundConfirmedClean:true,maskConfirmed:true});}catch(e){cropped=e.message.includes('cropped');}const visibleAlpha=a.preview().getContext('2d').getImageData(6,6,1,1).data[3];return {alpha:a.origin,removed:a.removed,source:r.manifest.sourcePixelsReused,cropped,visibleAlpha};})()")
  ok.call(extra['alpha']=='original-alpha'&&extra['removed']==0&&extra['source']&&extra['visibleAlpha']==128,'transparent PNG original alpha preserved');ok.call(extra['cropped'],'product cannot be cropped by placement')
  c.call('Page.reload');c.wait('!!session?.history');c.eval_js("enterModule('product-replacement')");setfile.call('#source',ROOT+'/assets/module-two-history/reference.jpg');setfile.call('#product',ROOT+'/assets/module-two-history/product.jpg');c.wait("!$('freeze').disabled");c.eval_js("$('freeze').onclick().then(()=>{$('lpAdjust').open=true})");c.wait("$('lpHistory').children.length===2");c.eval_js("$('lpHistory').firstChild.click()");c.wait("!$('lpDownload').hidden");ok.call(true,'saved local composition restores after reload')
  c.eval_js("enterModule('reference-reconstruction')");ok.call(c.eval_js("$('localProductEditor').hidden&&$('moduleNote').textContent.includes('参考图重构')"),'module one route retained')
  ok.call(Dir[dir+'/jobs/*/state.json'].empty?,'no server generation jobs created')
  File.write(out+'/result.json',JSON.pretty_generate({checks:checks,sourcePixels:stats,newExternalCalls:0}));puts JSON.generate({checks:checks.size,sourcePixels:stats,newExternalCalls:0})
 ensure
  [chrome,server].compact.each{|pid|Process.kill('TERM',pid)rescue nil;Process.wait(pid)rescue nil}
 end
end
