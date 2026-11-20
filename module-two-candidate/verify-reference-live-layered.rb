require_relative 'product-asset-provider'
eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
out=ROOT+'/diagnostics/reference-live-layered';FileUtils.mkdir_p(out)
Dir.mktmpdir('product-readiness-') do |dir|
 pid=nil
 begin
  pid=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9249',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9249,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1}
  c=CDP.new(pages.find{|p|p['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable');c.call('Network.setBlockedURLs',urls:['https://*','*/api/generate*','*/api/analyze*','*/api/freeze','*/api/generic/*','*/api/experiment/*','*/api/direct/*'])
  c.call('Page.navigate',url:'http://127.0.0.1:8773/');c.wait("document.readyState==='complete'&&!!session?.history&&typeof ProductAutoCompose!=='undefined'&&String($('freeze').onclick).includes('/api/product-assets/prepare')");c.eval_js("enterModule('reference-reconstruction')");c.eval_js("globalThis.originalFetch=fetch;globalThis.fetch=async(...args)=>{const r=await originalFetch(...args);if(args[0]==='/api/product-assets/prepare'){globalThis.PREPARED=await r.clone().json();globalThis.SELECTED=JSON.parse(args[1].body);}return r;}")
  setfile=lambda{|selector,path|doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:selector)['nodeId'];c.call('DOM.setFileInputFiles',nodeId:node,files:[path])}
  setfile.call('#source',ROOT+'/assets/81gMZuoRq6L._AC_SL1500_.jpg');c.wait("!$('freeze').disabled")
  c.eval_js("$('productName').value='Supplied silver LED bulb';$('productScene').value='keep';$('mode').value='ai-rewrite';$('layout').value='keep-reference';$('tone').value='keep-reference';$('ratio').value='4:5';$('freeze').onclick()")
  prepared=c.eval_js('globalThis.PREPARED');raise c.eval_js("JSON.stringify({status:$('lpStatus')?.textContent,module:$('module').value,handler:String($('freeze').onclick).slice(0,180)})") unless prepared;selected=c.eval_js('SELECTED');raise prepared.to_s unless prepared['state']=='awaiting-new-authorization'&&prepared['liveEnabled']==false&&prepared['maxRequests']==2&&prepared['budgetMicroUSD']==280000
  actual=prepared.fetch('analysisPlan');File.write(out+'/prepared-UNAUTHORIZED.json',JSON.pretty_generate(prepared));File.write(out+'/analysis-plan-UNAUTHORIZED.json',JSON.pretty_generate(actual));raise 'body hash mismatch' unless Digest::SHA256.hexdigest(actual['body'])==actual['binding']['requestHash']
  roleimages=JSON.parse(actual['body'])['contents'][0]['parts'].filter{|p|p['inlineData']};raise 'product image would leave local host' unless roleimages.size==1&&Digest::SHA256.hexdigest(Base64.strict_decode64(roleimages[0]['inlineData']['data']))==selected['sourceHash']
  fonts=c.eval_js("(async()=>{await InterTextFoundation.load({normal:await(await originalFetch('/fonts/InterVariable.ttf')).blob(),italic:await(await originalFetch('/fonts/InterVariable-Italic.ttf')).blob()});return {ready:InterTextFoundation.ready,family:InterTextFoundation.family};})()")
  raise 'local pinned font unavailable' unless fonts['ready']&&fonts['family']=='PictureOpsInter41'
  result={normalEntry:true,state:prepared['state'],sourceHash:selected['sourceHash'],productHash:selected['productHash'],options:prepared['options'],analysisRequestHash:actual['binding']['requestHash'],referenceImagesSentInPreparedBody:1,productImagesSentInPreparedBody:0,font:fonts,optionalEditorOpen:c.eval_js("$('lpAdjust').open"),newModelCalls:0,oldBatchStopped:File.exist?(ROOT+'/live-attempts/combined-Sentinel_ca2472a9acc88191b1b3ae0beb8d149a/STOP.json')}
  File.write(out+'/actual-entry.json',JSON.pretty_generate(result));puts JSON.generate(result)
 ensure
  Process.kill('TERM',pid)rescue nil;Process.wait(pid)rescue nil
 end
end
