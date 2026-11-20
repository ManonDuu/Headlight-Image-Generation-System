require_relative 'product-asset-provider'
eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
out=ROOT+'/diagnostics/final-readiness';FileUtils.mkdir_p(out)
Dir.mktmpdir('final-readiness-') do |dir|
 pid=nil
 begin
  pid=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9249',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9249,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1}
  c=CDP.new(pages.find{|p|p['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable');c.call('Network.setBlockedURLs',urls:['https://*','*/api/generate*','*/api/analyze*','*/api/freeze','*/api/generic/*','*/api/experiment/*','*/api/direct/*'])
  c.call('Page.navigate',url:'http://127.0.0.1:8773/');c.wait("document.readyState==='complete'&&!!session?.history&&typeof ProductAutoCompose!=='undefined'")
  before=c.eval_js('({ids:session.history.map(x=>x.id).sort(),paused:session.paidRequestsPaused,mock:session.mock})');raise 'live pause not confirmed' unless before['paused']&&before['mock']==false
  c.eval_js("globalThis.rawFetch=fetch;globalThis.PREPARES=[];globalThis.fetch=async(...a)=>{const r=await rawFetch(...a);if(a[0]==='/api/product-assets/prepare')PREPARES.push(await r.clone().json());return r;}")
  setfile=lambda{|selector,path|doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:selector)['nodeId'];c.call('DOM.setFileInputFiles',nodeId:node,files:[path])}
  empty=c.eval_js("enterModule('reference-reconstruction');({disabled:$('freeze').disabled,preserveUnavailable:$('preserveCopyOption').hidden&&$('preserveCopyOption').disabled})")
  setfile.call('#source',out+'/deer-road.png');c.wait("!$('freeze').disabled")
  rows=[]
  ['reference-reconstruction','product-replacement'].each do |mod|
   c.eval_js("enterModule(#{JSON.generate(mod)})")
   if mod=='reference-reconstruction'
    setfile.call('#source',out+'/deer-road.png');c.wait("!$('freeze').disabled")
   end
   if mod=='product-replacement'
    empty['productMissingDisabled']=c.eval_js("$('freeze').disabled")
    setfile.call('#source',ROOT+'/assets/listing-canbus-reference/reference.png');setfile.call('#product',ROOT+'/diagnostics/h11-regression/H11.png');c.wait("!$('freeze').disabled")
   end
   c.eval_js("$('productName').value='Supplied silver LED bulb'")
   modes=mod=='product-replacement' ? %w[ai-rewrite custom remove-all-copy preserve-reference] : %w[ai-rewrite custom remove-all-copy]
   modes.each do |mode|
    r=c.eval_js("(async()=>{$('mode').value=#{JSON.generate(mode)};$('copy').value='CANBUS Ready';$('layout').value=#{JSON.generate(mode=='custom' ? 'auto-layout' : 'keep-reference')};$('tone').value=#{JSON.generate(mode=='custom' ? 'adjust-color' : 'keep-reference')};$('color').value='#00a6a6';$('ratio').value=#{JSON.generate(mode=='custom' ? '1:1' : '4:5')};options();await $('freeze').onclick();const p=PREPARES.at(-1);if(!p?.analysisPlan)return {error:p,status:$('lpStatus').textContent};return {module:$('module').value,mode:$('mode').value,options:p.options,state:p.state,liveEnabled:p.liveEnabled,maxRequests:p.maxRequests,budgetMicroUSD:p.budgetMicroUSD,retries:p.retries,status:$('lpStatus').textContent,productImages:p.analysisPlan.binding.productImageSent||false,analysisRequestHash:p.analysisPlan.binding.requestHash};})()")
    raise 'unexpected live asset or dispatch '+r.to_s unless r['state']=='awaiting-new-authorization'&&r['liveEnabled']==false&&r['retries']==0
    rows<<r
    if mode=='ai-rewrite';plan=c.eval_js('PREPARES.at(-1).analysisPlan');File.write(out+'/'+mod+'-analysis-UNAUTHORIZED.json',JSON.pretty_generate(plan));end
   end
  end
  duplicate=c.eval_js("(async()=>{const n=PREPARES.length;await Promise.all([$('freeze').onclick(),$('freeze').onclick()]);return {prepareCalls:PREPARES.length-n,status:$('lpStatus').textContent,modelCalls:0};})()")
  raise 'duplicate prepare not blocked' unless duplicate['prepareCalls']==1
  failure=c.eval_js("(async()=>{let attempts=0;const real=fetch;globalThis.fetch=(...a)=>{if(a[0]==='/api/product-assets/prepare'&&++attempts===1)return Promise.reject(Error('offline-test-failure'));return real(...a)};await $('freeze').onclick();const failed={status:$('lpStatus').textContent,disabled:$('freeze').disabled};await $('freeze').onclick();globalThis.fetch=real;return {attempts,failed,recovered:$('lpStatus').textContent.includes('未获新授权')};})()")
  raise 'failure blocked subsequent action' unless failure['attempts']==2&&failure['failed']['disabled']==false&&failure['recovered']
  font=c.eval_js("(async()=>{await InterTextFoundation.load({normal:await(await rawFetch('/fonts/InterVariable.ttf')).blob(),italic:await(await rawFetch('/fonts/InterVariable-Italic.ttf')).blob()});return {ready:InterTextFoundation.ready,family:InterTextFoundation.family};})()")
  served={};%w[business-ui.js product-local-ui.js product-auto-compose.js internal-product-canvas.js].each{|name|served[name]=c.eval_js("(async()=>ProductCanvasFoundation.sha(await(await rawFetch('/#{name}')).blob()))()")};served.each{|name,hash|raise 'served code stale '+name unless hash==Digest::SHA256.file(ROOT+'/'+name).hexdigest}
  c.call('Page.reload');c.wait('!!session?.history&&document.readyState==="complete"');reload=c.eval_js("({history:session.history.map(x=>x.id).sort(),paused:session.paidRequestsPaused,selectedReference:!!ref,selectedProduct:!!productRef})")
  raise 'history changed' unless reload['history']==before['ids']&&reload['paused']
  back=c.eval_js("(async()=>{let n=0;const orig=fetch;globalThis.fetch=(...a)=>{if(a[0]==='/api/product-assets/prepare')n++;return orig(...a)};enterModule('reference-reconstruction');enterModule('product-replacement');await newTask.onclick();return {prepareCalls:n,disabled:$('freeze').disabled};})()")
  result={actualPort:8773,mock:false,before:before,missingInputs:empty,options:rows,duplicateClick:duplicate,failureRecovery:failure,reload:reload,moduleReturn:back,font:font,servedSHA256:served,newModelCalls:0,paidRoutesBlockedInBrowser:true}
  File.write(out+'/actual-8773.json',JSON.pretty_generate(result));puts JSON.generate({options:rows.size,duplicateClick:duplicate,historyUnchanged:true,font:font,newModelCalls:0})
 ensure
  Process.kill('TERM',pid)rescue nil;Process.wait(pid)rescue nil
 end
end
