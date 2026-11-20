eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
out=ROOT+'/diagnostics/deterministic-decoration';checks=[]
Dir.mktmpdir('decoration-ui-') do |dir|
 server=nil;chrome=nil
 begin
 server=Process.spawn('/usr/bin/ruby',ROOT+'/bridge-server.rb','--mock','--port','8799','--data',dir+'/jobs',out:dir+'/server.log',err:dir+'/server.err')
 100.times{begin;break if Net::HTTP.new('127.0.0.1',8799,nil).get('/api/session').code=='200';rescue SystemCallError;end;sleep 0.1}
 chrome=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-port=9259',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
 pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9259,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1}
 c=CDP.new(pages.find{|p|p['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Network.enable');c.call('Network.setBlockedURLs',urls:['https://*','*/api/generate*','*/api/analyze*']);c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:dir)
 c.call('Page.navigate',url:'http://127.0.0.1:8799/');c.wait('!!session?.history');c.eval_js("enterModule('reference-reconstruction')")
 doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:'#source')['nodeId'];c.call('DOM.setFileInputFiles',nodeId:node,files:[ROOT+'/diagnostics/final-readiness/deer-road.png']);c.wait("!$('freeze').disabled")
 actual=c.eval_js("(async()=>{const req=businessRequest(),a=await api('/api/product-assets/prepare',req),b=await api('/api/product-assets/prepare',{...req,module:'product-replacement',productName:'LED bulb',sceneMode:'keep',productImageBase64:#{JSON.generate(Base64.strict_encode64(File.binread(ROOT+'/fixtures/small-valid.jpg')))},productHash:#{JSON.generate(Digest::SHA256.file(ROOT+'/fixtures/small-valid.jpg').hexdigest)}});return [a,b].every(p=>p.sceneInputContract.deliveryKind==='scene-candidate-only'&&p.sceneInputContract.localDecorationRequired&&p.liveEnabled===false&&!p.package)&&$('layout').value==='keep-reference';})()")
 raise 'ordinary prepare path not migrated' unless actual;checks<<'both ordinary prepare endpoints expose scene-only intake without changing selected layout or dispatching models'
 data='data:image/png;base64,'+Base64.strict_encode64(File.binread(out+'/render.png'))
 # Stub only asset preparation/composition to test the existing UI lifecycle without paid routes.
 c.eval_js("(async()=>{globalThis.testBlob=new Blob([Uint8Array.from(atob(#{JSON.generate(data.split(',')[1])}),c=>c.charCodeAt(0))],{type:'image/png'});globalThis.prepareCalls=0;globalThis.completeRender=null;globalThis.oldAPI=api;api=async(path,req)=>{if(path==='/api/product-assets/prepare'){prepareCalls++;return {package:{},options:{}};}return oldAPI(path,req);};ProductAutoCompose.compose=()=>new Promise(resolve=>{completeRender=()=>resolve({blob:testBlob,manifest:{warnings:[],fixtureOnly:true}});});})()")
 c.eval_js("$('freeze').onclick();$('freeze').onclick();");c.wait('!!completeRender');raise 'duplicate dispatched' unless c.eval_js('prepareCalls===1');checks<<'duplicate click dispatches one local composition'
 c.eval_js('completeRender()');c.wait("!$('lpDownload').hidden&&$('lpHistory').children.length===1");c.eval_js("$('lpDownload').click()")
 50.times{break if File.file?(dir+'/product-original-composite.png');sleep 0.1};raise 'download hash' unless Digest::SHA256.file(dir+'/product-original-composite.png').hexdigest==Digest::SHA256.file(out+'/render.png').hexdigest;checks<<'existing UI download exact render bytes'
 c.call('Page.reload');c.wait("typeof $==='function'&&$('lpHistory')?.children.length===1");c.eval_js("$('lpHistory').firstChild.click()");c.wait("!$('lpDownload').hidden");checks<<'existing IndexedDB history restored on fresh page'
 c.eval_js("enterModule('reference-reconstruction')");doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:'#source')['nodeId'];c.call('DOM.setFileInputFiles',nodeId:node,files:[ROOT+'/diagnostics/final-readiness/deer-road.png']);c.wait("!$('freeze').disabled")
 c.eval_js("globalThis.completeRender=null;globalThis.oldAPI=api;api=async(path,req)=>path==='/api/product-assets/prepare'?{package:{},options:{}}:oldAPI(path,req);ProductAutoCompose.compose=()=>new Promise(resolve=>{completeRender=()=>resolve({blob:new Blob(['stale']),manifest:{warnings:[]}});});void $('freeze').onclick();")
 c.wait('!!completeRender');c.eval_js('newTask.onclick()');c.eval_js('completeRender()');c.wait("$('lpHistory').children.length===1");raise 'stale result exposed' unless c.eval_js("$('lpDownload').hidden");checks<<'new task interruption discards pending completion without saving stale image'
 File.write(out+'/ui-results.json',JSON.pretty_generate({checks:checks,compositionStubbed:true,modelCalls:0}));puts checks
 ensure
 [chrome,server].compact.each{|p|Process.kill('TERM',p)rescue nil;Process.wait(p)rescue nil}
 end
end
