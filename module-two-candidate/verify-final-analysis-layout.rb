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
  c.eval_js("(async()=>{await InterTextFoundation.load({normal:await(await fetch('/fonts/InterVariable.ttf')).blob(),italic:await(await fetch('/fonts/InterVariable-Italic.ttf')).blob()});})()")
  plan=JSON.parse(File.read(ROOT+'/diagnostics/final-live-20261018/step1-parsed.json'))['plan']
  c.eval_js('globalThis.REAL_PLAN='+JSON.generate(plan))
  checks=c.eval_js("REAL_PLAN.text.map(t=>{try{const p=InterTextFoundation.layout(t,{forbiddenSource:'headlights?',modes:{'ai-rewrite':{title:'Title Case',subtitle:'Sentence case',brand:'UPPERCASE'}}},ProductCanvasFoundation.copyText);return {text:t.text,passed:true,box:t.box};}catch(e){return {text:t.text,passed:false,error:e.message,box:t.box,fontSize:t.fontSize,lineHeight:t.lineHeightPx}}})")
  File.write(ROOT+'/diagnostics/final-live-20261018/real-layout-local-check.json',JSON.pretty_generate({checks:checks,modelCalls:0,sessionPaused:c.eval_js('session.paidRequestsPaused')}));puts JSON.pretty_generate(checks)
 ensure
  Process.kill('TERM',pid)rescue nil;Process.wait(pid)rescue nil
 end
end
