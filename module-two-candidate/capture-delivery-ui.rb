# Read-only UI screenshots; all write/model routes blocked.
eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
out=ROOT+'/diagnostics/delivery-ui-current';FileUtils.mkdir_p(out)
Dir.mktmpdir('delivery-browser-') do |dir|
 pid=nil
 begin
  pid=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9234',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','--no-default-browser-check','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9234,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1}
  c=CDP.new(pages.find{|x|x['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable')
  c.call('Network.setBlockedURLs',urls:['*/api/generate','*/api/experiment/*','*/api/analyze','*/api/generic/*','*/api/freeze','*/api/review','*/api/maintenance/*','*/api/analysis-*/*'])
  c.call('Emulation.setDeviceMetricsOverride',width:1440,height:1100,deviceScaleFactor:1,mobile:false)
  c.call('Page.navigate',url:'http://127.0.0.1:8773/');c.wait("typeof businessRequest==='function'&&!!session?.history")
  capture=lambda{|name|data=c.call('Page.captureScreenshot',format:'png',captureBeyondViewport:true);File.binwrite(out+'/'+name+'.png',Base64.strict_decode64(data['data']))}
  capture.call('homepage-current')
  results={}
  %w[reference-reconstruction product-replacement].each do |mod|
   c.eval_js("enterModule('#{mod}')");c.wait("$('module').value==='#{mod}'&&!$('moduleView').hidden")
   c.eval_js("$('mode').value='custom';$('tone').value='adjust-color';options()")
   if mod=='product-replacement'
    c.eval_js("$('productFileName').textContent='未提供真实产品图';$('productHint').textContent='素材缺失：不使用占位图进行真实验收';$('productName').placeholder='填写真实产品名称（当前未提供）'")
   end
   result=c.eval_js("({copy:Array.from($('mode').options).map(o=>o.textContent),layout:Array.from($('layout').options).map(o=>o.textContent),brand:!$('brandName').hidden,parameters:!$('productSpecs').hidden,ratio:!!$('ratio'),color:!$('colorField').hidden,customCopy:!$('copyField').hidden,noQuality:!document.body.textContent.includes('输出质量'),noFreeLayout:!$('layoutInstructions'),sceneVisible:!$('productSceneField').hidden,spec:session.genericGC.businessSpec})")
   raise 'loaded controls mismatch' unless result['copy']==['全部去掉','AI 改写','自己提供']&&result['layout']==['参考图排版','AI 自动排版']&&result.values_at('brand','parameters','ratio','color','customCopy','noQuality','noFreeLayout').all?&&result['sceneVisible']==(mod=='product-replacement')
   results[mod]=result;capture.call(mod+'-current')
  end
  File.write(out+'/verification.json',JSON.pretty_generate({screenshots:3,loadedControls:results,newModelCalls:0,writeRoutesBlocked:true,productMaterial:'missing; no placeholder image used'}));puts JSON.generate({output:out,screenshots:3,controls:'verified',modelCalls:0})
 ensure
  Process.kill('TERM',pid) rescue nil;Process.wait(pid) rescue nil
 end
end
