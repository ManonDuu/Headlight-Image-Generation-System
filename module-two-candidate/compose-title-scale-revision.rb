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
  c.eval_js(File.read(ROOT+'/internal-inter-text.js'))
  fonts={'normal'=>Base64.strict_encode64(File.binread(ROOT+'/assets/fonts/inter-4.1/InterVariable.ttf')),'italic'=>Base64.strict_encode64(File.binread(ROOT+'/assets/fonts/inter-4.1/InterVariable-Italic.ttf'))}
  c.eval_js('globalThis.TEST_FONTS='+JSON.generate(fonts))
  c.eval_js("InterTextFoundation.load(Object.fromEntries(Object.entries(TEST_FONTS).map(([k,v])=>[k,new Blob([Uint8Array.from(atob(v),c=>c.charCodeAt(0))])])));")
  actual=JSON.parse(File.read(ROOT+'/diagnostics/compact-analysis-authorized-20261018/migrated-font-validated.json'))
  c.eval_js('globalThis.ACTUAL_PLAN='+JSON.generate(actual['plan']))
  c.eval_js('globalThis.BACKGROUND_BYTES='+JSON.generate(Base64.strict_encode64(File.binread(ROOT+'/diagnostics/authorized-background-20261018/background.jpg'))))
  c.eval_js(File.read(ROOT+'/reference-type-scale.js'))
  c.eval_js('globalThis.TYPE_AUDIT='+File.read(ROOT+'/diagnostics/authorized-background-20261018/title-geometry-audit.json'))
  result=c.eval_js(File.read(ROOT+'/compose-title-scale-revision.js'))
  path=dir+'/downloads/B0FBFPH2Y8-title-size-comparison-copy-pending.png';50.times{break if File.file?(path);sleep 0.1}
  raise 'actual download hash mismatch' unless File.file?(path)&&Digest::SHA256.file(path).hexdigest==result['outputHash']
  FileUtils.cp(path,ROOT+'/diagnostics/authorized-background-20261018/B0FBFPH2Y8-title-size-comparison-copy-pending.png')
  result['downloadHashVerified']=true;File.write(ROOT+'/diagnostics/authorized-background-20261018/title-size-revision-manifest.json',JSON.pretty_generate(result));puts JSON.pretty_generate(result)

 ensure
  Process.kill('TERM',pid) rescue nil;Process.wait(pid) rescue nil
 end
end
