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
  history=[ROOT+'/diagnostics/preserve-copy/proposal.json',ROOT+'/diagnostics/preflight-wire-20261018/candidate-policy-replay.json'].map{|path|v=JSON.parse(File.read(path));v['layout']||v['plan']}
  c.eval_js('globalThis.HISTORY_PLANS='+JSON.generate(history))
  regression=c.eval_js(<<~JS)
  (()=>{
   const A=ProductAutoCompose,F=ProductCanvasFoundation,P={forbiddenSource:'headlights?',modes:{'ai-rewrite':{title:'Title Case',subtitle:'Sentence case',brand:'UPPERCASE'},custom:{},'preserve-reference':{}}};let checks=[];
   const ok=(v,m)=>{if(!v)throw Error(m);checks.push(m)};
   const unchanged=JSON.stringify(REAL_PLAN);let kept=structuredClone(REAL_PLAN.text),audit;
   try{audit=A.prepareText(kept,{width:1856,height:2304,mode:'keep-reference',policy:P});ok(audit.reviewRequired&&!audit.sourceLocalizationVerified,'real keep-reference stays unverified even after font fitting')}catch(e){ok(/可读字号|布局/.test(e.message),'real keep-reference blocks unreadable fitting')}
   ok(kept.every((t,i)=>JSON.stringify(t.box)===JSON.stringify(REAL_PLAN.text[i].box)),'keep-reference never silently remaps wrong native boxes');
   for(const [i,plan] of [REAL_PLAN,...HISTORY_PLANS].entries()){
    const t=structuredClone(plan.text);for(const v of t)v.mode=v.mode||'ai-rewrite';
    const a=A.prepareText(t,{width:1856,height:2304,mode:'auto-layout',policy:P});
    ok(t.map(x=>x.text).join('')===plan.text.map(x=>x.text).join(''),'case '+i+' auto-layout keeps raw words');
    ok(a.sourceBoxesRequiredForRendering===false&&a.reviewRequired,'case '+i+' no precise OCR dependency or false acceptance');
    for(const v of t)InterTextFoundation.layout(v,P,F.copyText);
   }
   const test={layout:{text:[{...structuredClone(REAL_PLAN.text[0]),box:{x:10,y:20,width:100,height:50},fontSize:20,lineHeightPx:24}]},productSlot:{x:200,y:100,width:50,height:100}};
   A.mapLayout(test,[400,300],800,600);ok(test.layout.text[0].box.x===20&&test.layout.text[0].fontSize===40&&test.productSlot.height===200,'explicit canvas mapping scales boxes metrics slot once');
   const native=structuredClone(REAL_PLAN),before=JSON.stringify(native);A.mapLayout({layout:native},null,1856,2304);ok(JSON.stringify(native)===before,'sourceGeometry never guessed as render canvas');
   let rejected=false;try{A.mapLayout({layout:{text:[{box:{x:399,y:0,width:2,height:1}}]}},[400,300],800,600)}catch(e){rejected=true}ok(rejected,'declared canvas overflow rejected');
   const custom=[{...structuredClone(REAL_PLAN.text[0]),text:'mIxEd CANBUS',mode:'custom'}];A.prepareText(custom,{width:1000,height:1000,mode:'auto-layout',policy:P,productSlot:{x:500,y:100,width:450,height:850}});ok(custom[0].text==='mIxEd CANBUS'&&custom[0].box.x+custom[0].box.width<500,'custom exact copy and product exclusion');
   ok(A.prepareText([],{width:1000,height:1000,mode:'auto-layout',policy:P}).changes.length===0,'no-copy remains empty');
   ok(JSON.stringify(REAL_PLAN)===unchanged,'saved real response never mutated');return {checks,realKeepAudit:audit||null};
  })()
  JS
  FileUtils.mkdir_p(ROOT+'/diagnostics/layout-offline-repair')
  File.write(ROOT+'/diagnostics/layout-offline-repair/regression.json',JSON.pretty_generate({originalRealFontChecks:checks,regression:regression,modelCalls:0,sessionPaused:c.eval_js('session.paidRequestsPaused')}));puts JSON.generate({checks:regression['checks'].length,modelCalls:0})
 ensure
  Process.kill('TERM',pid)rescue nil;Process.wait(pid)rescue nil
 end
end
