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
  matches=JSON.parse(File.read(ROOT+'/diagnostics/local-anchor-audit/anchor-comparison.json')).find{|x|x['case']=='deer'}
  c.eval_js('globalThis.MATCHES='+JSON.generate(matches))
  c.eval_js('globalThis.SOURCE64='+JSON.generate(Base64.strict_encode64(File.binread(ROOT+'/diagnostics/final-readiness/deer-road.png'))))
  result=c.eval_js(<<~JS)
  (async()=>{
   const source=new Blob([Uint8Array.from(atob(SOURCE64),c=>c.charCodeAt(0))]);
   const candidates=REAL_PLAN.evidence.rewrites.filter(r=>r.action==='render').map(r=>{
    const a=MATCHES.anchors.find(a=>a.id===r.blockId),b=a.ocrBox,pad=Math.max(4,b.height*.08),x=Math.max(0,b.x-pad),y=Math.max(0,b.y-pad);
    return {sourceText:a.sourceText,role:REAL_PLAN.text[r.renderIndex].role,box:{x,y,width:Math.min(1122,b.x+b.width+pad)-x,height:Math.min(1402,b.y+b.height+pad)-y}};
   });
   const measured=await ReferenceInkEvidence.extract(source,candidates);return {...measured,roles:measured.roles.map(r=>({...r,lines:r.lines.map(({inkRuns,...l})=>l)})),anchors:measured.anchors.map(({inkRuns,...l})=>l)};
  })()
  JS
  FileUtils.mkdir_p(ROOT+'/diagnostics/keep-reference-gate')
  File.write(ROOT+'/diagnostics/keep-reference-gate/real-glyph-measurement.json',JSON.pretty_generate(result));puts JSON.pretty_generate(result)
 ensure
  Process.kill('TERM',pid)rescue nil;Process.wait(pid)rescue nil
 end
end
