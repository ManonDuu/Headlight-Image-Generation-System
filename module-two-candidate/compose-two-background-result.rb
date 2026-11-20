# Local composition and download verification only; every paid browser route blocked.
require_relative 'product-asset-provider'
eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
step=Integer(ARGV.fetch(0));out=ROOT+'/diagnostics/two-backgrounds-20261018';p=JSON.parse(File.read(out+"/step#{step}-plan.json"));f=step==1 ? p['frozen'] : p['productFrozen'];opts=f['options']
Dir.mktmpdir('approved-background-view-') do |dir|
 chrome=nil
 begin
  chrome=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9249',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9249,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1};raise 'local browser unavailable' unless pages
  c=CDP.new(pages.find{|p|p['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable');c.call('Network.setBlockedURLs',urls:['https://*','*/api/generate*','*/api/analyze*','*/api/analysis*','*/api/freeze','*/api/generic/*','*/api/experiment/*','*/api/direct/*','*/api/maintenance/*'])
  Dir.mkdir(dir+'/downloads');c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:dir+'/downloads');c.call('Page.navigate',url:'http://127.0.0.1:8773/');c.wait('!!session?.history');raise 'pause disabled' unless c.eval_js('session.paidRequestsPaused===true')
  c.eval_js("enterModule(#{JSON.generate(opts['module'])})")
  setfile=lambda{|selector,path|doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:selector)['nodeId'];c.call('DOM.setFileInputFiles',nodeId:node,files:[path])}
  setfile.call('#source',ROOT+(step==1 ? '/diagnostics/final-readiness/deer-road.png' : '/assets/listing-canbus-reference/reference.png'))
  setfile.call('#product',ROOT+'/diagnostics/final-readiness/9005-transparent.png') if step==2
  c.eval_js("$('mode').value=#{JSON.generate(opts['mode'])};$('layout').value='keep-reference';$('tone').value='keep-reference';$('ratio').value='4:5';")
  if step==2;c.eval_js("$('productName').value=#{JSON.generate(opts['productName'])};$('productScene').value=#{JSON.generate(opts['sceneMode'])};");end
  c.wait("!$('freeze').disabled")
  req=c.eval_js('businessRequest()');actualopts=req.reject{|k,_|%w[imageBase64 productImageBase64 sourceHash productHash budgetMicroUSD].include?(k)};af=DirectImagePlan.prepare(Base64.strict_decode64(req['imageBase64']),step==2 ? Base64.strict_decode64(req['productImageBase64']) : nil,DefaultProductFacts.apply(actualopts),mock:false)
  raise 'normal UI selection differs from frozen input' unless af['binding']['requestHash']==f['binding']['requestHash']
  c.eval_js("$('freeze').onclick()");status=c.eval_js("$('lpStatus').textContent");raise status unless status.include?('已自动合成')
  c.eval_js("$('lpDownload').download='result.png';$('lpDownload').click();$('lpRecord').click()")
  100.times{break if Dir[dir+'/downloads/*.png'].any?&&Dir[dir+'/downloads/*.json'].any?;sleep 0.1}
  image=Dir[dir+'/downloads/*.png'].first;manifest=JSON.parse(File.read(Dir[dir+'/downloads/*.json'].first));raise 'download mismatch' unless Digest::SHA256.file(image).hexdigest==manifest['outputHash']
  FileUtils.cp(image,out+"/step#{step}-composite.png");File.write(out+"/step#{step}-manifest.json",JSON.pretty_generate(manifest))
  c.call('Page.reload');c.wait('!!session?.history');c.eval_js("enterModule(#{JSON.generate(opts['module'])})")
  c.wait("$('lpHistory').querySelectorAll('button').length===1");c.eval_js("$('lpHistory').querySelector('button').click();$('lpDownload').download='restored.png';$('lpDownload').click()")
  100.times{break if File.file?(dir+'/downloads/restored.png');sleep 0.1};raise 'history download mismatch' unless Digest::SHA256.file(dir+'/downloads/restored.png').hexdigest==manifest['outputHash']
  result={step:step,real8773:true,normalUIFrozenInputsMatched:true,realBackground:true,keepReference:true,newModelCalls:0,downloadHashVerified:true,isolatedBrowserHistoryReload:true,outputHash:manifest['outputHash'],backgroundHash:manifest['backgroundHash'],paidPause:true};File.write(out+"/step#{step}-ui-verification.json",JSON.pretty_generate(result));puts JSON.generate(result)
 ensure
  Process.kill('TERM',chrome)rescue nil;Process.wait(chrome)rescue nil
 end
end
