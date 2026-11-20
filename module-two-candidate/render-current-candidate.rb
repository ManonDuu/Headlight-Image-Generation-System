require_relative 'shared-typography'
eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
policy={'forbiddenSource'=>SharedTypography::FORBIDDEN.source,'modes'=>%w[ai-rewrite custom remove-all-copy].map{|m|[m,SharedTypography.contract({'mode'=>m,'brandName'=>''})]}.to_h}
Dir.mktmpdir('current-candidate-') do |dir|
 pid=nil
 begin
  pid=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9248',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9248,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1};raise 'browser unavailable' unless pages
  c=CDP.new(pages.find{|v|v['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable')
  c.call('Network.setBlockedURLs',urls:['*/api/*']);c.call('Page.navigate',url:'http://127.0.0.1:8773/');c.wait('document.readyState === "complete"')
  c.call('Network.setBlockedURLs',urls:['*']);Dir.mkdir(dir+'/downloads');c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:dir+'/downloads')
  c.eval_js('globalThis.CANVAS_TEST_POLICY='+JSON.generate(policy));c.eval_js(File.read(ROOT+'/internal-product-canvas.js'))
  c.eval_js(File.read(ROOT+'/internal-inter-text.js'))
  fonts={'normal'=>Base64.strict_encode64(File.binread(ROOT+'/assets/fonts/inter-4.1/InterVariable.ttf')),'italic'=>Base64.strict_encode64(File.binread(ROOT+'/assets/fonts/inter-4.1/InterVariable-Italic.ttf'))}
  c.eval_js('globalThis.TEST_FONTS='+JSON.generate(fonts))
  c.eval_js("InterTextFoundation.load(Object.fromEntries(Object.entries(TEST_FONTS).map(([k,v])=>[k,new Blob([Uint8Array.from(atob(v),c=>c.charCodeAt(0))])])));")
  c.eval_js(File.read(ROOT+'/reference-type-scale.js'))
  c.eval_js(File.read(ROOT+'/reference-ink-evidence.js'));c.eval_js(File.read(ROOT+'/internal-reference-workflow.js'));
  c.eval_js(File.read(ROOT+'/reference-layout-anchors.js'));c.eval_js(File.read(ROOT+'/reference-candidate.js'))
  c.eval_js('globalThis.SOURCE_DATA='+JSON.generate(Base64.strict_encode64(File.binread(ROOT+'/assets/amazon-example/reference.jpg'))))
  c.eval_js('globalThis.BACKGROUND_DATA='+JSON.generate(Base64.strict_encode64(File.binread(ROOT+'/diagnostics/authorized-background-20261018/background.jpg'))))
  parsed=JSON.parse(File.read(ROOT+'/diagnostics/preflight-wire-20261018/candidate-policy-replay.json'));frozen=JSON.parse(File.read(ROOT+'/diagnostics/preflight-wire-20261018/analysis-plan.json'))
  c.eval_js('globalThis.CANDIDATE_PLAN='+JSON.generate(parsed.fetch('plan')));c.eval_js('globalThis.CANDIDATE_OPTIONS='+JSON.generate(frozen['frozen']['options']))
  anchor_tests=c.eval_js(File.read(ROOT+'/test-layout-anchors-browser.js'))
  result=c.eval_js("(async()=>{const decode=v=>new Blob([Uint8Array.from(atob(v),c=>c.charCodeAt(0))]);const result=await ReferenceCandidate.compose({reference:decode(SOURCE_DATA),background:decode(BACKGROUND_DATA),plan:CANDIDATE_PLAN,options:CANDIDATE_OPTIONS,policy:CANVAS_TEST_POLICY});const ps=result.manifest.textPlans,bs=result.manifest.layoutRelations.outputBands;if(ps[0].align||ps[0].box.x+ps[0].box.width/2!==result.manifest.width/2||ps[1].box.x+ps[1].box.width/2!==result.manifest.width/2)throw Error('Heading group axis mismatch');for(let i=0;i<bs.length;i++){const t=ps[i+2],b=bs[i];if(!(t.box.y>=b.y&&t.box.y+t.height<=b.y+b.height))throw Error('Label outside container');}result.manifest.relationalChecks=4;await ProductCanvasFoundation.download(result,'reference-layout-repaired.png');return result.manifest;})()")
  100.times{break if File.file?(dir+'/downloads/reference-layout-repaired.png');sleep 0.1}
  destination=ROOT+'/diagnostics/layout-repaired-candidate-20261018';FileUtils.mkdir_p(destination)
  FileUtils.cp(dir+'/downloads/reference-layout-repaired.png',destination+'/reference-layout-repaired.png');result['anchorTests']=anchor_tests;File.write(destination+'/manifest.json',JSON.pretty_generate(result));puts JSON.pretty_generate(result)

 ensure
  Process.kill('TERM',pid) rescue nil;Process.wait(pid) rescue nil
 end
end
