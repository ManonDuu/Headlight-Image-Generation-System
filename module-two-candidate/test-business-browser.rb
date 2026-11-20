# Inspect actual served UI. Every write/model route is blocked in this browser.
eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
n=0;check=lambda{|v,label|raise label unless v;n+=1}
Dir.mktmpdir('business-browser-') do |dir|
 chrome=nil
 begin
  hashes=Dir[ROOT+'/live-attempts/**/*'].select{|p|File.file?(p)}.map{|p|[p,Digest::SHA256.file(p).hexdigest]}.to_h
  chrome=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9234',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','--no-default-browser-check','--disable-features=MediaRouter','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9234,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1}
  c=CDP.new(pages.find{|x|x['type']=='page'}['webSocketDebuggerUrl'])
  c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable')
  c.call('Network.setBlockedURLs',urls:['*/api/generate','*/api/experiment/*','*/api/analyze','*/api/generic/*','*/api/freeze','*/api/review','*/api/maintenance/*','*/api/analysis-*/*'])
  c.call('Emulation.setDeviceMetricsOverride',width:1440,height:1000,deviceScaleFactor:1,mobile:false)
  c.call('Page.navigate',url:'http://127.0.0.1:8773/')
  c.wait("typeof businessRequest==='function'&&typeof session!=='undefined'&&!!session?.history")
  check.call(c.eval_js("!$('home').hidden&&document.querySelectorAll('.module-card').length===3&&document.querySelectorAll('.module-card')[2].textContent.includes('整套亚马逊附图')"),'three exact module entries')
  c.eval_js("enterModule('reference-reconstruction')")
  check.call(c.eval_js("$('productField').hidden&&$('productSceneField').hidden&&!$('productMetadata').hidden&&$('brandName').getBoundingClientRect().width>0&&$('tone').getBoundingClientRect().width>0&&$('layout').getBoundingClientRect().width>0"),'reference fields visible, no product scene')
  check.call(c.eval_js("['follow-reference','1:1','12:15','4:5','custom'].every(v=>Array.from($('ratio').options).some(o=>o.value===v))"),'required and historical ratios')
  setfile=lambda do |selector,path|
   doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:selector)['nodeId'];c.call('DOM.setFileInputFiles',nodeId:node,files:[path])
  end
  setfile.call('#source',ROOT+'/assets/81gMZuoRq6L._AC_SL1500_.jpg');c.wait('!!ref')
  c.eval_js("$('mode').value='custom';$('copy').value='60W Exact CASE';$('brandName').value='OWN';$('productSpecs').value='60W';$('ratio').value='12:15';$('tone').value='adjust-color';$('color').value='#112233';$('layout').value='auto-layout';options()")
  req=c.eval_js("(()=>{const d=businessRequest();delete d.imageBase64;return d})()")
  check.call(req['customCopy']=='60W Exact CASE'&&req['brandName']=='OWN'&&req['productParameters']=='60W'&&req['color']=='#112233'&&req['layoutMode']=='auto-layout'&&!req.key?('layoutInstructions'),'all visible fields mapped')
  check.call(!req.key?('sceneMode')&&!req.key?('productHash')&&req['output']['aspectRatio']=='12:15','reference request isolation')
  c.eval_js("$('mode').value='remove-all-copy';options()")
  check.call(c.eval_js("(()=>{const d=businessRequest();return !('brandName' in d)&&!('productParameters' in d)&&!('customCopy' in d)&&$('brandName').value==='OWN'&&$('productSpecs').value==='60W'&&$('brandName').disabled})()"),'inactive values retained locally but excluded from request')
  c.eval_js("$('mode').value='custom';options()")
  check.call(c.eval_js("!$('brandName').disabled&&businessRequest().customCopy==='60W Exact CASE'"),'switch back restores fields')
  FileUtils.mkdir_p(ROOT+'/diagnostics/business-ui-20261018')
  capture=lambda{|name|r=c.call('Page.captureScreenshot',format:'png',captureBeyondViewport:true);File.binwrite(ROOT+'/diagnostics/business-ui-20261018/'+name+'.png',Base64.strict_decode64(r['data']))}
  check.call(c.eval_js("$('mode').options.length===3&&!document.body.textContent.includes('员工')&&!document.body.textContent.includes('输出质量')&&!$('layoutInstructions')"),'simplified controls only')
  capture.call('reference')
  c.eval_js("enterModule('product-replacement')")
  check.call(c.eval_js("!$('productField').hidden&&!$('productSceneField').hidden&&!$('brandName').disabled"),'product fields visible')
  check.call(c.eval_js("$('session').textContent.includes('$0.27')&&session.genericGC.generationModel==='gemini-3.1-flash-image'&&session.genericGC.automaticFallback===false"),'product budget and fixed model reflected')
  setfile.call('#source',ROOT+'/assets/81gMZuoRq6L._AC_SL1500_.jpg');setfile.call('#product',ROOT+'/fixtures/small-valid.jpg');c.wait('!!ref&&!!productRef')
  c.eval_js("$('productName').value='OFFLINE fixture';$('productScene').value='keep';options()")
  check.call(c.eval_js("businessRequest().sceneMode==='keep'&&!!businessRequest().productHash&&businessRequest().budgetMicroUSD===270000"),'product keep and two images mapped')
  capture.call('product')
  c.eval_js("enterModule('reference-reconstruction')");setfile.call('#source',ROOT+'/assets/81gMZuoRq6L._AC_SL1500_.jpg');c.wait('!!ref')
  check.call(c.eval_js("$('productSceneField').hidden&&!('sceneMode' in businessRequest())&&!('productHash' in businessRequest())"),'product keep cannot leak across modules')
  c.eval_js("restoreOptions({module:'product-replacement',ruleTrace:{mode:'custom',output:{aspectRatio:'4:5'},selectedOptions:{mode:'custom',requestedOutput:{aspectRatio:'12:15'},layoutTone:'adjust-color',color:'#445566',layoutMode:'adjust-layout',layoutInstructions:'标题置顶',brandName:'SAVED',productParameters:'80W',productName:'Saved lamp',customCopy:'80W Exact',sceneMode:'keep'}}})")
  check.call(c.eval_js("$('ratio').value==='12:15'&&$('layout').value==='adjust-layout'&&$('layout').selectedOptions[0].disabled&&$('tone').value==='adjust-color'&&$('color').value==='#445566'&&$('brandName').value==='SAVED'&&$('productSpecs').value==='80W'&&$('productScene').value==='keep'&&$('copy').value==='80W Exact'"),'new history fields restore in browser')
  c.eval_js("$('openHistory').click()");c.wait("!$('historyPanel').hidden&&$('recordList').children.length>0")
  c.eval_js("$('historySearch').value='9dce1ce10578330f6d472373';$('historySearch').dispatchEvent(new Event('input'))")
  check.call(c.eval_js("$('recordList').children.length===1&&$('recordList').textContent.includes('下载原图')"),'history search and download')
  c.eval_js("$('history').value='9dce1ce10578330f6d472373';$('load').click()");c.wait("job?.id==='9dce1ce10578330f6d472373'&&!$('output').hidden&&$('output').naturalWidth===1856")
  check.call(c.eval_js("$('ratio').value==='4:5'&&$('generate').disabled&&$('productSceneField').hidden"),'legacy options restored without quota')
  c.call('Emulation.setDeviceMetricsOverride',width:390,height:844,deviceScaleFactor:1,mobile:true)
  check.call(c.eval_js('document.documentElement.scrollWidth<=390'),'mobile no overflow')
  capture.call('mobile')
  check.call(hashes.all?{|p,h|Digest::SHA256.file(p).hexdigest==h},'live ledgers unchanged')
  result={checks:n,state:'passed',actualServedUI:true,modelAndWriteRoutesBlocked:true,newModelRequests:0,ledgerFilesUnchanged:hashes.size}
  File.write(ROOT+'/diagnostics/business-ui-20261018/result.json',JSON.pretty_generate(result));puts JSON.generate(result)
 ensure
  Process.kill('TERM',chrome) rescue nil;Process.wait(chrome) rescue nil
 end
end
