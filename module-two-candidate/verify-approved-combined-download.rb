eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
id='88f7292b78d72985d451aca0';out=ROOT+'/diagnostics/approved-combined-20261018'
Dir.mktmpdir('approved-view-') do |dir|
 pid=nil
 begin
  pid=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9249',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9249,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1}
  c=CDP.new(pages.find{|p|p['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable');c.call('Network.setBlockedURLs',urls:['https://*','*/api/generate*','*/api/analyze*','*/api/freeze','*/api/generic/*','*/api/experiment/*','*/api/product-assets/*'])
  Dir.mkdir(dir+'/downloads');c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:dir+'/downloads');c.call('Page.navigate',url:'http://127.0.0.1:8773/');c.wait('!!session?.history');c.eval_js("$('history').value='#{id}';$('load').onclick()");c.wait("job?.id==='#{id}'&&!$('output').hidden&&!$('saveImage').disabled&&$('output').naturalWidth===1856")
  c.eval_js("$('saveImage').click()");100.times{break if Dir[dir+'/downloads/*.jpg'].any?;sleep 0.1};file=Dir[dir+'/downloads/*.jpg'].first;raise 'download mismatch' unless file&&Digest::SHA256.file(file).hexdigest==Digest::SHA256.file(out+'/reference.jpg').hexdigest
  result={task:id,normalHistoryLoaded:true,displayed:true,downloaded:true,originalBytesPreserved:true,sha256:Digest::SHA256.file(file).hexdigest,newModelCalls:0};File.write(out+'/download-verification.json',JSON.pretty_generate(result));puts JSON.generate(result)
 ensure
  Process.kill('TERM',pid)rescue nil;Process.wait(pid)rescue nil
 end
end
