eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
require 'webrick'
out=File.join(ROOT,'diagnostics/deterministic-decoration');FileUtils.mkdir_p(out)
Dir.mktmpdir('decoration-test-') do |dir|
 server=WEBrick::HTTPServer.new(Port:8798,BindAddress:'127.0.0.1',DocumentRoot:ROOT,Logger:WEBrick::Log.new(File::NULL),AccessLog:[])
 t=Thread.new{server.start};chrome=nil
 begin
 chrome=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9258',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
 pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9258,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1}
 c=CDP.new(pages.find{|p|p['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Network.enable');c.call('Network.setBlockedURLs',urls:['https://*','*/api/*']);c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:out)
 c.call('Page.navigate',url:'http://127.0.0.1:8798/test-decoration.html');c.wait('!!globalThis.DeterministicDecoration')
 c.eval_js("globalThis.CANVAS_TEST_POLICY={forbiddenSource:'headlights?',modes:{custom:{},'ai-rewrite':{title:'Title Case',subtitle:'Sentence case',brand:'UPPERCASE'}}}")
 foundation=c.eval_js(File.read(ROOT+'/test-internal-product-canvas.js'));File.write(out+'/product-pixel-regression.json',JSON.pretty_generate(foundation))
 result=c.eval_js(File.read(ROOT+'/test-deterministic-decoration.js'));File.binwrite(out+'/render.png',Base64.strict_decode64(result.delete('data').split(',')[1]))
 c.call('Page.reload');c.wait('!!globalThis.DeterministicDecoration');restored=c.eval_js("(async()=>{const r=JSON.parse(localStorage.getItem('decoration-fixture'));return await ProductCanvasFoundation.sha(await(await fetch(r.data)).blob())===r.hash;})()")
 raise 'restore mismatch' unless restored;result['checks']<<'isolated persisted result restores byte-identically after reload'
 50.times{break if File.file?(out+'/offline-decoration.png');sleep 0.1};raise 'download mismatch' unless Digest::SHA256.file(out+'/offline-decoration.png').hexdigest==result['outputHash'];result['checks']<<'actual browser download byte-identical'
 File.write(out+'/test-results.json',JSON.pretty_generate(result));puts JSON.generate(result['checks'])
 ensure
 server.shutdown;t.join;if chrome;Process.kill('TERM',chrome)rescue nil;Process.wait(chrome)rescue nil;end
 end
end
