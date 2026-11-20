require_relative 'shared-typography'
require_relative 'import-authorized-composite-history'
eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
policy={'forbiddenSource'=>SharedTypography::FORBIDDEN.source,'modes'=>%w[ai-rewrite custom remove-all-copy].map{|m|[m,SharedTypography.contract({'mode'=>m,'brandName'=>'FixtureBrand'})]}.to_h}
Dir.mktmpdir('server-reference-') do |dir|
 server=nil;chrome=nil
 start=lambda do |enabled=true|
  args=['--mock','--port','8774','--data',dir+'/jobs'];args<<'--internal-reference' if enabled
  pid=Process.spawn({'GEMINI_API_KEY'=>nil},'/usr/bin/ruby',ROOT+'/bridge-server.rb',*args,out:dir+'/server.log',err:dir+'/server.err')
  ready=false;100.times{begin;res=Net::HTTP.new('127.0.0.1',8774,nil).get('/api/session');ready=JSON.parse(res.body).dig('internalReference','enabled')==enabled;break if ready;rescue SystemCallError;end;sleep 0.1};raise 'isolated server not ready' unless ready;pid
 end
 begin
  AuthorizedCompositeHistory.import(dir+'/jobs')
  server=start.call
  chrome=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9239',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9239,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1};raise 'browser unavailable' unless pages
  c=CDP.new(pages.find{|v|v['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable')
  c.call('Network.setBlockedURLs',urls:['https://*','*/api/generate','*/api/generic/*','*/api/analysis*','*/api/direct/*','*/api/experiment/*','*/api/analyze'])
  c.call('Page.navigate',url:'http://127.0.0.1:8774/');c.wait("typeof businessRequest==='function'&&!!session?.history")
  Dir.mkdir(dir+'/downloads');c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:dir+'/downloads')
  result=c.eval_js("(async()=>{const id='19943cd47d3b42b02d8c8739';$('history').value=id;await $('load').onclick();const s=await api('/api/task/'+id);const bg=await blob('/api/task/'+id+'/background');const bgHash=await ProductHash(bg);return {id,state:job.state,label:$('outputLabel').textContent,copyMode:$('mode').value,layoutMode:$('layout').value,ratio:$('ratio').value,outputVisible:!$('output').hidden,generateDisabled:$('generate').disabled,backgroundHash:bgHash,expectedBackgroundHash:s.backgroundHash,outputHash:s.outputHash,detailVisible:!$('compositeAssets').hidden};async function ProductHash(b){return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await b.arrayBuffer()))).map(x=>x.toString(16).padStart(2,'0')).join('');}})()")
  raise 'history UI mismatch' unless result['state']=='composed-pending-review'&&result['outputVisible']&&result['generateDisabled']&&result['detailVisible']&&result['backgroundHash']==result['expectedBackgroundHash']&&result['copyMode']=='ai-rewrite'&&result['layoutMode']=='keep-reference'&&result['ratio']=='4:5'
  File.write(ROOT+'/diagnostics/composite-history-test.json',JSON.pretty_generate(result));puts JSON.pretty_generate(result)

 rescue =>e
  warn File.read(dir+'/server.err') if File.file?(dir+'/server.err');raise
 ensure
  [chrome,server].compact.each{|pid|Process.kill('TERM',pid) rescue nil;Process.wait(pid) rescue nil}
 end
end
