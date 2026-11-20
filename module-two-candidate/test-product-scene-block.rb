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
 setfile=lambda{|selector,path|doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:selector)['nodeId'];c.call('DOM.setFileInputFiles',nodeId:node,files:[path])}
 c.eval_js("enterModule('product-replacement')");setfile.call('#source',ROOT+'/assets/listing-canbus-reference/reference.png');setfile.call('#product',ROOT+'/diagnostics/product-real-validation/product.png');c.wait("!$('freeze').disabled")
 c.eval_js("$('mode').value='preserve-reference';$('layout').value='keep-reference';$('ratio').value='4:5';$('productScene').value='change';$('productName').value='Supplied transparent red-ring six-emitter 9005 bulb';globalThis.prepareCalls=0;globalThis.originalAPI=api;api=async(path,req)=>{if(path==='/api/product-assets/prepare')prepareCalls++;return originalAPI(path,req);};void $('freeze').onclick();void $('freeze').onclick();")
 c.wait("!$('freeze').disabled");status=c.eval_js("$('lpStatus').textContent");raise status unless status.include?('selected scene action has not passed local review');raise 'invalid output exposed' unless c.eval_js("$('lpDownload').hidden&&$('lpHistory').children.length===0&&prepareCalls===1");raise 'mode silently changed' unless c.eval_js("$('productScene').value==='change'&&$('mode').value==='preserve-reference'&&$('layout').value==='keep-reference'");raise 'model job created' unless Dir[dir+'/jobs/*/state.json'].empty?
 File.write(ROOT+'/diagnostics/product-real-validation/normal-entry-block.json',JSON.pretty_generate({status:status,actualProduct:true,actualCanbusReference:true,prepareCalls:1,selectedOptionsPreserved:true,downloadHidden:true,historyCount:0,newModelJobs:0,compositionSucceeded:false}));puts status

 ensure
 [chrome,server].compact.each{|p|Process.kill('TERM',p)rescue nil;Process.wait(p)rescue nil}
 end
end
