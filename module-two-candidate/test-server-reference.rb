require_relative 'shared-typography'
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
  server=start.call
  chrome=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9239',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9239,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1};raise 'browser unavailable' unless pages
  c=CDP.new(pages.find{|v|v['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable')
  c.call('Network.setBlockedURLs',urls:['https://*','*/api/generate','*/api/generic/*','*/api/analysis*','*/api/direct/*','*/api/experiment/*','*/api/analyze'])
  c.call('Page.navigate',url:'http://127.0.0.1:8774/');c.wait("typeof businessRequest==='function'&&!!session?.history")
  Dir.mkdir(dir+'/downloads');c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:dir+'/downloads')
  c.eval_js('globalThis.CANVAS_TEST_POLICY='+JSON.generate(policy))
  %w[internal-product-canvas.js internal-inter-text.js internal-reference-workflow.js internal-reference-server.js reference-ink-evidence.js reference-type-scale.js].each{|f|c.eval_js(File.read(ROOT+'/'+f))}
  fonts={'normal'=>Base64.strict_encode64(File.binread(ROOT+'/assets/fonts/inter-4.1/InterVariable.ttf')),'italic'=>Base64.strict_encode64(File.binread(ROOT+'/assets/fonts/inter-4.1/InterVariable-Italic.ttf'))}
  c.eval_js('globalThis.TEST_FONTS='+JSON.generate(fonts));c.eval_js("InterTextFoundation.load(Object.fromEntries(Object.entries(TEST_FONTS).map(([k,v])=>[k,new Blob([Uint8Array.from(atob(v),c=>c.charCodeAt(0))])])));")
  result=c.eval_js(File.read(ROOT+'/test-server-reference-browser.js'))
  path=File.join(dir,'downloads',result['downloadName']);50.times{break if File.file?(path);sleep 0.1};raise 'download hash mismatch' unless File.file?(path)&&Digest::SHA256.file(path).hexdigest==result['outputHash'];result['downloadHashVerified']=true
  before=Dir.glob(dir+'/jobs/*/*').select{|p|File.file?(p)}.map{|p|[p,Digest::SHA256.file(p).hexdigest]}.to_h
  Process.kill('TERM',server);Process.wait(server);server=nil;server=start.call
  recovery=c.eval_js("(async()=>{const session=await (await fetch('/api/session')).json();const store=new InternalReferenceServer.Store(session.token);const restored=await ReferenceWorkflow.Workflow.open({enabled:true,store,id:SERVER_INTERNAL_TEST.id,policy:CANVAS_TEST_POLICY});const interrupted=await store.read(SERVER_INTERNAL_TEST.interruptedId);return {state:restored.status.state,outputHash:restored.status.outputHash,interrupted:interrupted.state,history:(await store.list()).length,pendingTypography:(await store.read(SERVER_INTERNAL_TEST.inkReviewId)).state};})()")
  raise 'restart recovery failed' unless recovery['state']=='rejected'&&recovery['outputHash']==result['outputHash']&&recovery['interrupted']=='interrupted'&&recovery['pendingTypography']=='awaiting-typography-review'
  raise 'original task mutated' unless before.all?{|p,h|Digest::SHA256.file(p).hexdigest==h}
  raise 'unexpected attempt ledger' unless Dir.glob(dir+'/jobs/**/*').none?{|p|File.basename(p).match?(/ledger|one-use|attempt/)}
  Process.kill('TERM',server);Process.wait(server);server=nil;server=start.call(false)
  disabled=c.eval_js("(async()=>{const s=await (await fetch('/api/session')).json();let blocked=false;try{await new InternalReferenceServer.Store(s.token).list();}catch(e){blocked=true;}return !s.internalReference.enabled&&blocked;})()")
  raise 'default-off gate failed' unless disabled
  result.merge!('restartRecovery'=>recovery,'originalHistoryUnchanged'=>true,'checks'=>result['checks']+4,'modelRoutesBlocked'=>true,'historyAuthority'=>'server-files-only','defaultGateVerified'=>true)
  File.write(ROOT+'/diagnostics/server-reference-test.json',JSON.pretty_generate(result));puts JSON.pretty_generate(result)
 rescue =>e
  warn File.read(dir+'/server.err') if File.file?(dir+'/server.err');raise
 ensure
  [chrome,server].compact.each{|pid|Process.kill('TERM',pid) rescue nil;Process.wait(pid) rescue nil}
 end
end
