require_relative 'shared-typography'
eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
policy={'forbiddenSource'=>SharedTypography::FORBIDDEN.source,'modes'=>%w[ai-rewrite custom remove-all-copy].map{|m|[m,SharedTypography.contract({'mode'=>m,'brandName'=>'FixtureBrand'})]}.to_h}
Dir.mktmpdir('canvas-foundation-') do |dir|
 pid=nil
 begin
  pid=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9238',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9238,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1};raise 'browser unavailable' unless pages
  c=CDP.new(pages.find{|v|v['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable')
  c.call('Network.setBlockedURLs',urls:['*/api/*']);c.call('Page.navigate',url:'http://127.0.0.1:8773/');c.wait('document.readyState === "complete"')
  c.call('Network.setBlockedURLs',urls:['*']);Dir.mkdir(dir+'/downloads');c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:dir+'/downloads')
  c.eval_js('globalThis.CANVAS_TEST_POLICY='+JSON.generate(policy));c.eval_js(File.read(ROOT+'/internal-product-canvas.js'))
  result=c.eval_js(File.read(ROOT+'/test-internal-product-canvas.js'))
  path=dir+'/downloads/INTERNAL-fixture.png';50.times{break if File.file?(path);sleep 0.1}
  raise 'download absent/hash mismatch' unless File.file?(path)&&Digest::SHA256.file(path).hexdigest==result['manifest']['outputHash']
  result['downloadHashVerified']=true;File.write(ROOT+'/diagnostics/canvas-foundation-test.json',JSON.pretty_generate(result));puts JSON.pretty_generate(result)
  c.eval_js(File.read(ROOT+'/internal-inter-text.js'))
  fonts={'normal'=>Base64.strict_encode64(File.binread(ROOT+'/assets/fonts/inter-4.1/InterVariable.ttf')),'italic'=>Base64.strict_encode64(File.binread(ROOT+'/assets/fonts/inter-4.1/InterVariable-Italic.ttf'))}
  c.eval_js('globalThis.INTER_FONT_BYTES='+JSON.generate(fonts))
  typography=c.eval_js(File.read(ROOT+'/test-inter-text.js'));File.write(ROOT+'/diagnostics/inter-text-test.json',JSON.pretty_generate(typography));puts JSON.pretty_generate(typography)
  c.eval_js(File.read(ROOT+'/internal-product-pipeline.js'))
  pipeline=c.eval_js(File.read(ROOT+'/test-product-pipeline.js'))
  pipeline_path=dir+'/downloads/INTERNAL-pipeline-fixture.png';50.times{break if File.file?(pipeline_path);sleep 0.1}
  raise 'pipeline download absent/hash mismatch' unless File.file?(pipeline_path)&&Digest::SHA256.file(pipeline_path).hexdigest==pipeline['downloadHash']
  pipeline['downloadHashVerified']=true;File.write(ROOT+'/diagnostics/product-pipeline-test.json',JSON.pretty_generate(pipeline));puts JSON.pretty_generate(pipeline)
  require_relative 'bridge-server'
  reference_b64=c.eval_js("(async()=>{const c=document.createElement('canvas');c.width=20;c.height=20;c.getContext('2d').fillRect(2,2,10,10);globalThis.WORKFLOW_REFERENCE=await new Promise(r=>c.toBlob(r));return c.toDataURL().split(',')[1];})()")
  input=Base64.strict_decode64(reference_b64)
  opts={'businessSpec'=>DirectImagePlan::SPEC,'module'=>'reference-reconstruction','mode'=>'custom','customCopy'=>'mIxEd LED H11','layoutMode'=>'auto-layout','layoutTone'=>'keep-reference','output'=>{'aspectRatio'=>'4:5','imageSize'=>'2K'}}
  prepared=DirectImagePlan.prepare(input,nil,opts,mock:true);raise 'compiler validation failed' unless DirectImagePlan.validate(prepared)
  frozen={'id'=>'internal-compiler-fixture','module'=>'reference-reconstruction','state'=>'frozen','sourceHash'=>Digest::SHA256.hexdigest(input),'requestHash'=>prepared['binding']['requestHash'],'ruleTrace'=>prepared['trace'],'genericGC'=>prepared['binding']}
  c.eval_js('globalThis.WORKFLOW_FROZEN='+JSON.generate(frozen));c.eval_js(File.read(ROOT+'/internal-reference-workflow.js'))
  workflow=c.eval_js(File.read(ROOT+'/test-reference-workflow.js'))
  workflow_path=File.join(dir,'downloads',workflow['downloadName']);50.times{break if File.file?(workflow_path);sleep 0.1}
  raise 'workflow download absent/hash mismatch' unless File.file?(workflow_path)&&Digest::SHA256.file(workflow_path).hexdigest==workflow['downloadHash']
  workflow['downloadHashVerified']=true;File.write(ROOT+'/diagnostics/reference-workflow-test.json',JSON.pretty_generate(workflow));puts JSON.pretty_generate(workflow)
 ensure
  Process.kill('TERM',pid) rescue nil;Process.wait(pid) rescue nil
 end
end
