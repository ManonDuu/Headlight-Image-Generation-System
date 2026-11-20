eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
out=ROOT+'/diagnostics/real-scenes';checks=[]
Dir.mktmpdir('real-scene-ui-') do |dir|
 server=nil;chrome=nil
 begin
 server=Process.spawn('/usr/bin/ruby',ROOT+'/bridge-server.rb','--mock','--port','8799','--data',dir+'/jobs',out:dir+'/server.log',err:dir+'/server.err')
 100.times{begin;break if Net::HTTP.new('127.0.0.1',8799,nil).get('/api/session').code=='200';rescue SystemCallError;end;sleep 0.1}
 chrome=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-port=9259',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
 pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9259,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1}
 c=CDP.new(pages.find{|p|p['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Network.enable');c.call('Network.setBlockedURLs',urls:['https://*','*/api/generate*','*/api/analyze*','*/api/direct/*','*/api/generic/*','*/api/experiment/*']);c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:dir)
 c.call('Page.navigate',url:'http://127.0.0.1:8799/');c.wait('!!session?.history');c.eval_js("enterModule('reference-reconstruction')")
 setfile=lambda{doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:'#source')['nodeId'];c.call('DOM.setFileInputFiles',nodeId:node,files:[ROOT+'/diagnostics/final-readiness/deer-road.png'])};setfile.call;c.wait("!$('freeze').disabled")
 c.eval_js("$('mode').value='preserve-reference';$('layout').value='keep-reference';$('ratio').value='4:5';globalThis.prepareCalls=0;globalThis.originalAPI=api;api=async(path,req)=>{if(path==='/api/product-assets/prepare')prepareCalls++;return originalAPI(path,req);};void $('freeze').onclick();void $('freeze').onclick();")
 150.times{break if c.eval_js("!$('freeze').disabled");sleep 0.1}
 status=c.eval_js("$('lpStatus').textContent");raise status unless c.eval_js("!$('lpDownload').hidden&&$('lpHistory').children.length===1");raise 'repeat dispatched' unless c.eval_js('prepareCalls===1');checks<<'real prepare/cache/renderer/anchors/geometry/text path succeeds without stubs';checks<<'duplicate click causes one prepare and one saved result'
 raise 'selection changed' unless c.eval_js("$('mode').value==='preserve-reference'&&$('layout').value==='keep-reference'");checks<<'preserve-reference and keep-reference selections retained'
 c.eval_js("$('lpDownload').click();$('lpRecord').click()")
 100.times{break if File.file?(dir+'/product-original-composite.png')&&File.file?(dir+'/product-composition.json');sleep 0.1}
 manifest=JSON.parse(File.read(dir+'/product-composition.json'));raise 'download mismatch' unless Digest::SHA256.file(dir+'/product-original-composite.png').hexdigest==manifest['outputHash'];raise 'copy changed' unless manifest['textPlans'].map{|t|t['text']}==['ULTRA BRIGHTNESS','OTHER'];raise 'wrong output' unless [manifest['width'],manifest['height']]==[1856,2304]
 FileUtils.cp(dir+'/product-original-composite.png',out+'/final-composite.png');FileUtils.cp(dir+'/product-composition.json',out+'/final-manifest.json');checks<<'actual PNG download matches output hash and exact retained case'
 c.call('Page.reload');c.wait("typeof $==='function'&&$('lpHistory')?.children.length===1");c.eval_js("$('lpHistory').firstChild.click()");c.wait("!$('lpDownload').hidden&&$('lpPreview').width===1856");restored=c.eval_js("(async()=>{const r=await new Promise((resolve,reject)=>{const q=indexedDB.open('picture-local-products',1);q.onsuccess=()=>{const d=q.result,v=d.transaction('results').objectStore('results').getAll();v.onsuccess=()=>{d.close();resolve(v.result[0]);};v.onerror=reject;};q.onerror=reject;});return await ProductCanvasFoundation.sha(r.blob);})()");raise 'restored bytes changed' unless restored==manifest['outputHash'];checks<<'real IndexedDB history restores byte-identical output after reload'
 Dir.mkdir(dir+'/restored');c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:dir+'/restored');c.eval_js("$('lpDownload').click()");100.times{break if Dir[dir+'/restored/*.png'].size==1;sleep 0.1};raise 'restored download mismatch' unless Dir[dir+'/restored/*.png'].size==1&&Dir[dir+'/restored/*.png'].all?{|p|Digest::SHA256.file(p).hexdigest==manifest['outputHash']};checks<<'restored result browser download byte-identical'
 # Delay only scheduling of the real compositor, not its data or output, to test interruption.
 c.eval_js("enterModule('reference-reconstruction')");setfile.call;c.wait("!$('freeze').disabled");c.eval_js("$('mode').value='preserve-reference';$('layout').value='keep-reference';$('ratio').value='4:5';globalThis.releaseReal=null;globalThis.realDone=false;globalThis.realCompose=ProductAutoCompose.compose;ProductAutoCompose.compose=async args=>{await new Promise(resolve=>releaseReal=resolve);try{return await realCompose(args);}finally{realDone=true;}};void $('freeze').onclick();")
 c.wait('!!releaseReal');c.eval_js('newTask.onclick()');c.eval_js('releaseReal()');c.wait('realDone');raise 'stale saved' unless c.eval_js("$('lpHistory').children.length===1&&$('lpDownload').hidden");checks<<'new task during real composition prevents stale save/display'
 raise 'paid jobs created' unless Dir[dir+'/jobs/*/state.json'].empty?;checks<<'no paid model jobs created'
 File.write(out+'/real-ui-results.json',JSON.pretty_generate({checks:checks,compositionStubbed:false,interruptionSchedulingDelayed:true,outputHash:manifest['outputHash'],status:status,modelCalls:0,serverPort:8799,live8773Touched:false}));puts checks
 ensure
 [chrome,server].compact.each{|p|Process.kill('TERM',p)rescue nil;Process.wait(p)rescue nil}
 end
end
