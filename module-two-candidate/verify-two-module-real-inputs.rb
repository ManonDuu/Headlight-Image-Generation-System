require_relative 'direct-image-plan'
eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
checks=[];ok=lambda{|v,m|raise m unless v;checks<<m};out=ROOT+'/diagnostics/today-real-input-readiness';FileUtils.mkdir_p(out)
Dir.mktmpdir('normal-entry-') do |dir|
 server=nil;chrome=nil
 begin
  server=Process.spawn({'GEMINI_API_KEY'=>nil},'/usr/bin/ruby',ROOT+'/bridge-server.rb','--mock','--port','8792','--data',dir+'/jobs',out:dir+'/server.log',err:dir+'/server.err')
  100.times{begin;break if Net::HTTP.new('127.0.0.1',8792,nil).get('/api/session').code=='200';rescue SystemCallError;end;sleep 0.1}
  chrome=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9249',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9249,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1}
  c=CDP.new(pages.find{|p|p['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable');c.call('Network.setBlockedURLs',urls:['https://*','*/api/analyze','*/api/generic/analyze','*/api/review','*/api/experiment/*','*/api/internal/*'])
  Dir.mkdir(dir+'/downloads');c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:dir+'/downloads');c.call('Page.navigate',url:'http://127.0.0.1:8792/');c.wait('!!session?.history')
  results=[]
  %w[reference-reconstruction product-replacement].each do |mod|
   c.eval_js("enterModule(#{JSON.generate(mod)})")
   setfile=lambda{|selector,path|doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:selector)['nodeId'];c.call('DOM.setFileInputFiles',nodeId:node,files:[path])}
   setfile.call('#source',mod=='product-replacement' ? ROOT+'/assets/module-two-history/reference.jpg' : ROOT+'/assets/amazon-example/reference.jpg')
   if mod=='product-replacement';setfile.call('#product',ROOT+'/assets/module-two-history/product.jpg');c.eval_js("$('productName').value='Supplied silver LED bulb';$('productScene').value='keep';$('productScene').dispatchEvent(new Event('change'))");end
   c.wait("!$('freeze').disabled");c.eval_js("$('freeze').onclick()");c.wait("job?.state==='frozen'");id=c.eval_js('job.id');folder=dir+'/jobs/'+id;plan=JSON.parse(File.read(folder+'/generic-gc-plan.json'))
   ok.call(plan['binding']['version']==DirectImagePlan::SPEC&&plan['binding']['analysisCalls']==0,mod+' current direct version, zero analysis')
   rules=plan['trace']['ruleBindings'];prompt=JSON.parse(plan['body'])['contents'][0]['parts'][0]['text']
   ok.call(rules.all?{|r|prompt.include?(r['constraint'])},mod+' actual wire contains all selected rules')
   ok.call(prompt.include?('including required removal of a reference brand')&&prompt.include?('not a pixel replica')&&!prompt.include?('Do not reflow'),mod+' whole image tolerance serialized')
   ok.call(prompt.include?('Never output headlight or headlights')&&prompt.include?('Remove reference overlay brand names')&&prompt.include?('Remove unsupported scales'),mod+' hard rules remain')
   ok.call(plan['trace']['policy']['postGenerationModelCalls']==0&&plan['trace']['policy']['delivery']=='show-and-download-immediately',mod+' no post-generation model stage')
   if mod=='product-replacement';ok.call(prompt.include?('Image 2 alone defines replacement appearance')&&plan['binding']['imageRoles'].size==2&&plan['options']['sceneMode']=='keep',mod+' exact second image identity and scene selection');end
   c.eval_js("$('generate').click();$('generate').click()");c.wait("job?.state==='mock-result'&&!$('output').hidden&&!$('saveImage').disabled&&$('output').naturalWidth===1856")
   done=c.eval_js('job');ok.call(done['visualAcceptance']=='not-evaluated',mod+' displayed before any review')
   ok.call(File.binread(folder+'/generic-request.json')==plan['body'].b,mod+' dispatched bytes equal frozen request')
   files=Dir[dir+'/downloads/*'];c.eval_js("$('saveImage').click()");download=nil;100.times{download=(Dir[dir+'/downloads/*.jpg']-files).first;break if download;sleep 0.1}
   ok.call(download&&Digest::SHA256.file(download).hexdigest==done['outputHash'],mod+' byte-identical original download')
   FileUtils.mv(download,dir+'/'+mod+'.jpg')
   c.call('Page.reload');c.wait('!!session?.history');c.eval_js("$('history').value=#{JSON.generate(id)};$('load').onclick()");c.wait("job?.id===#{JSON.generate(id)}&&!$('output').hidden&&!$('saveImage').disabled")
   ok.call(c.eval_js('job.outputHash')==done['outputHash'],mod+' persisted result loads without re-generation')
   File.write(out+'/'+mod+'-mock-plan.json',JSON.pretty_generate(plan));File.write(out+'/'+mod+'-request.json',plan['body']);File.write(out+'/'+mod+'-trace.json',JSON.pretty_generate(plan['trace']));results<<{module:mod,requestHash:plan['binding']['requestHash'],analysisCalls:0,imageCalls:1,mock:true,postGenerationModelCalls:0,downloadHash:done['outputHash']}
  end
  File.write(out+'/result.json',JSON.pretty_generate({checks:checks.size,details:checks,modules:results,newExternalModelCalls:0,reviewRoutesBlocked:true}));puts JSON.generate({checks:checks.size,modules:2,newExternalModelCalls:0})
 ensure
  [chrome,server].compact.each{|pid|Process.kill('TERM',pid) rescue nil;Process.wait(pid) rescue nil}
 end
end
