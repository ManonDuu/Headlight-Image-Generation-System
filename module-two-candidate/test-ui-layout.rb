# Read-only real-result preview. All model/analysis routes blocked in Chrome.
eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
n=0;check=lambda{|v,label|raise label unless v;n+=1}
Dir.mktmpdir('layout-browser-') do |dir|
 chrome=nil
 begin
  hashes=Dir[ROOT+'/live-attempts/**/*'].select{|p|File.file?(p)}.map{|p|[p,Digest::SHA256.file(p).hexdigest]}.to_h
  chrome=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9233',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','--no-default-browser-check','--disable-features=MediaRouter','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9233,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1}
  c=CDP.new(pages.find{|x|x['type']=='page'}['webSocketDebuggerUrl'])
  c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable')
  c.call('Network.setBlockedURLs',urls:['*/api/generate','*/api/experiment/*','*/api/analyze','*/api/generic/*','*/api/freeze','*/api/review','*/api/local-typography*','*/api/internal-reference*'])
  c.call('Emulation.setDeviceMetricsOverride',width:1440,height:1000,deviceScaleFactor:1,mobile:false)
  c.call('Page.navigate',url:'http://127.0.0.1:8773/')
  c.wait("typeof session!=='undefined'&&!!session?.history")
  c.eval_js("enterModule('reference-reconstruction')")
  check.call(c.eval_js("document.querySelector('aside').getBoundingClientRect().width===290"),'desktop panel width')
  check.call(c.eval_js("Array.from($('mode').options).map(o=>o.value).join('|')==='remove-all-copy|ai-rewrite|custom'&&Array.from($('ratio').options).map(o=>o.value).join('|')==='follow-reference|1:1|12:15|4:5|3:4|16:9|5:4|4:3|9:16|2:3|3:2|custom'"),'all modes/ratios retained')
  check.call(c.eval_js("Array.from(document.getElementById('module').options).map(x=>x.text).join('|')==='参考图全重构|产品替换'"),'module labels unchanged')
  c.eval_js("document.getElementById('history').value='9dce1ce10578330f6d472373';document.getElementById('load').click()")
  c.wait("job?.id==='9dce1ce10578330f6d472373'&&!document.getElementById('output').hidden&&document.getElementById('output').naturalWidth===1856")
  check.call(c.eval_js("document.getElementById('reference').naturalWidth===1200&&document.getElementById('output').naturalHeight===2304"),'actual original/reference preview')
  check.call(c.eval_js("!document.getElementById('sourceSelected').hidden&&document.getElementById('uploadBox').hidden"),'history reference thumbnail')
  check.call(c.eval_js("!document.querySelector('.details').open&&document.getElementById('generate').disabled"),'technical details collapsed and spend disabled')
  FileUtils.mkdir_p(ROOT+'/diagnostics/ui-20261018')
  capture=lambda{|name|result=c.call('Page.captureScreenshot',format:'png',captureBeyondViewport:true);File.binwrite(ROOT+'/diagnostics/ui-20261018/'+name+'.png',Base64.strict_decode64(result['data']))}
  capture.call('desktop')
  c.call('Emulation.setDeviceMetricsOverride',width:390,height:844,deviceScaleFactor:1,mobile:true)
  check.call(c.eval_js("document.documentElement.scrollWidth<=390"),'no horizontal overflow on mobile')
  c.eval_js("for(let p=$('reference').parentElement;p;p=p.parentElement)if(p.tagName==='DETAILS')p.open=true")
  check.call(c.eval_js("document.getElementById('reference').getBoundingClientRect().width>100&&document.getElementById('output').getBoundingClientRect().width>100"),'mobile original and result previews accessible')
  capture.call('mobile')
  c.eval_js("document.getElementById('newTask').onclick()")
  c.wait("job===null&&!document.getElementById('source').disabled")
  doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:'#source')['nodeId']
  c.call('DOM.setFileInputFiles',nodeId:node,files:[ROOT+'/assets/81gMZuoRq6L._AC_SL1500_.jpg'])
  c.wait("!!ref&&!document.getElementById('sourceSelected').hidden")
  c.eval_js("document.getElementById('mode').value='custom';document.getElementById('mode').dispatchEvent(new Event('change'))")
  check.call(c.eval_js("!document.getElementById('copyField').hidden"),'custom copy opens')
  c.eval_js("document.getElementById('mode').value='ai-rewrite';document.getElementById('mode').dispatchEvent(new Event('change'))")
  check.call(c.eval_js("document.getElementById('copyField').hidden&&!document.getElementById('freeze').disabled&&document.getElementById('optionNote').textContent.includes('未提供的参数不沿用参考图')"),'AI visible default enabled offline')
  c.eval_js("document.getElementById('ratio').value='custom';document.getElementById('ratio').dispatchEvent(new Event('change'))")
  check.call(c.eval_js("!document.getElementById('dimensions').hidden"),'custom dimensions opens')
  c.eval_js("document.getElementById('module').value='product-replacement';document.getElementById('module').dispatchEvent(new Event('change'))")
  check.call(c.eval_js("document.getElementById('freeze').disabled&&!document.getElementById('product').disabled&&!document.getElementById('productField').hidden&&!productRef&&document.getElementById('moduleNote').textContent.includes('两图')"),'product requires independent second image')
  c.eval_js("document.getElementById('removeSource').click()")
  check.call(c.eval_js("!ref&&document.getElementById('sourceSelected').hidden&&document.getElementById('freeze').disabled"),'remove reference')
  check.call(hashes.all?{|p,h|Digest::SHA256.file(p).hexdigest==h},'ledgers unchanged')
  result={checks:n,state:'passed',desktop:[1440,1000],mobile:[390,844],modelRoutesBlocked:true,newModelCalls:0,ledgerFilesUnchanged:hashes.size,screenshots:%w[desktop.png mobile.png]}
  File.write(ROOT+'/diagnostics/ui-20261018/acceptance.json',JSON.pretty_generate(result));puts JSON.generate(result)
 ensure
  Process.kill('TERM',chrome) rescue nil;Process.wait(chrome) rescue nil
 end
end
