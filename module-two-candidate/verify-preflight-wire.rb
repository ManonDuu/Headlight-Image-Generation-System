# Bounded offline capture: current browser -> HTTP freeze -> stored plan -> provider -> injected transport.
require_relative 'reference-provider'
eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
out=ROOT+'/diagnostics/preflight-wire-20261018';FileUtils.mkdir_p(out)
checks=[];check=lambda{|v,name|raise name unless v;checks<<name}
Dir.mktmpdir('wire-preflight-') do |dir|
 server=nil;chrome=nil
 begin
  server=Process.spawn({'GEMINI_API_KEY'=>nil},'/usr/bin/ruby',ROOT+'/bridge-server.rb','--mock','--internal-reference','--port','8791','--data',dir+'/jobs',out:dir+'/server.log',err:dir+'/server.err')
  100.times{begin;break if Net::HTTP.new('127.0.0.1',8791,nil).get('/api/session').code=='200';rescue SystemCallError;end;sleep 0.1}
  chrome=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9247',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9247,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1}
  c=CDP.new(pages.find{|p|p['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable')
  c.call('Network.setBlockedURLs',urls:['https://*','*/api/generate','*/api/generic/*','*/api/experiment/*','*/api/analyze'])
  c.call('Page.navigate',url:'http://127.0.0.1:8791/');c.wait("typeof businessRequest==='function'&&!!session?.history")
  c.eval_js("enterModule('reference-reconstruction')")
  check.call(c.eval_js("$('mode').value==='ai-rewrite'&&$('layout').value==='keep-reference'&&$('ratio').value==='4:5'&&$('brandName').value===''&&$('productSpecs').value===''") ,'current page defaults: AI rewrite, reference layout/color, 4:5, no supplied claims')
  doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:'#source')['nodeId'];c.call('DOM.setFileInputFiles',nodeId:node,files:[ROOT+'/assets/amazon-example/reference.jpg']);c.wait("!$('freeze').disabled")
  form=c.eval_js('businessRequest()');c.eval_js("$('freeze').onclick()");c.wait("job?.state==='frozen'");job=c.eval_js('job');frozen=JSON.parse(File.read(dir+'/jobs/'+job['id']+'/generic-gc-plan.json'))
  check.call(frozen['options']['mode']==form['mode']&&frozen['options']['layoutMode']==form['layoutMode']&&frozen['options']['layoutTone']==form['layoutTone'],'HTTP freeze retains actual page options')
  check.call(frozen['binding']['sourceHash']=='28399cad8a8e136d5cad8dbd88bb3d46763448e73755beb45a083a8f0b261814','correct immutable reference hash')
  plan=ReferenceProvider.prepare(frozen,'layout-copy')
  binding=c.eval_js("api('/api/internal/reference',{op:'provider-prepare',originalTaskId:job.id,stage:'layout-copy'})")
  check.call(binding.reject{|k,_|%w[liveEnabled protocolVerifiedLive].include?(k)}==plan['binding'],'actual HTTP provider-prepare uses current repaired plan')
  File.write(out+'/page-options.json',JSON.pretty_generate(form.reject{|k,_|k=='imageBase64'}));File.write(out+'/analysis-plan.json',JSON.pretty_generate(plan));File.write(out+'/analysis-request.json',plan['body']);File.write(out+'/direct-request.json',frozen['body']||JSON.generate(frozen['request']))
  request=JSON.parse(plan['body']);config=request['generationConfig'];prompt=request['contents'][0]['parts'][0]['text'];schema=config['responseFormat']['text']['schema']
  check.call(prompt.include?('SOURCE IMAGE: 1200x1500')&&prompt.include?('OUTPUT CANVAS: 1856x2304')&&schema['properties']['sourceGeometry']['properties']['coordinateSpace']['enum']==['source-pixels'],'explicit source/output spaces')
  check.call(schema['properties']['text']['items']['properties']['role']['enum']==AnalysisOutputContract::ROLES,'wire/parser role enum identical')
  check.call(prompt.include?('FINAL eligible copy')&&prompt.include?('action render or omit')&&prompt.include?('sourceText'),'separate OCR evidence and final rendering')
  check.call(prompt.include?('single natural wording change suffices')&&prompt.include?('Preserve source core intent')&&prompt.include?('Case/wrapping/punctuation alone do not count'),'whole-image rewrite and meaning constraints')
  check.call(config['maxOutputTokens']==4096&&config['candidateCount']==1&&!config.key?('imageConfig')&&!config.key?('responseModalities'),'single text analysis, capped output, no image generation')
  raw=File.read(ROOT+'/live-attempts/rule-analysis-Sentinel_e054f7f47f08819180f5dca59fd8ff5c/response.raw.json');calls=[]
  result=ReferenceProvider.execute(plan,dir+'/capture',approval:plan['binding'],mock:true,transport:lambda{|endpoint,body,options|calls<<{endpoint:endpoint,requestHash:Digest::SHA256.hexdigest(body),options:options};check.call(body==File.read(out+'/analysis-request.json'),'dispatch bytes exactly match captured request');[200,raw]})
  check.call(calls.size==1&&calls[0][:options]=={retries:0,timeoutSeconds:120},'actual dispatch zero retry and 120s timeout')
  audit=result.dig('payload','contractAudit');check.call(audit['state']=='awaiting-contract-review'&&!audit['coordinateEvidenceVerified'],'actual cached response rejected for untrusted source coordinates')
  check.call(audit['removed'].any?{|x|x['reasons'].include?('UNCONFIRMED_NUMERIC_TEXT')}&&audit['removed'].any?{|x|x['reasons'].include?('UNCONFIRMED_BRAND_ROLE')},'actual parser suppresses unconfirmed brand and numeric copy')
  check.call(audit['pending'].any?{|x|x['code']=='NATURAL_REWRITE_MISSING'},'unchanged copy not accepted as natural rewrite')
  rejected=false;begin;AnalysisOutputContract.validate_render!([{'role'=>'body','text'=>'HEADLIGHTS'}],frozen['options']);rescue;rejected=true;end;check.call(rejected,'final rendering gate rejects forbidden words')
  # Explicit synthetic positive response: never treated as recovered source geometry or a real candidate.
  synthetic={'layoutVersion'=>ReferenceProvider::LAYOUT_VERSION,'sourceGeometry'=>{'width'=>1200,'height'=>1500,'coordinateSpace'=>'source-pixels'},'text'=>[{'text'=>'Enjoy Everyday Comfort','role'=>'title','fontSize'=>60,'weight'=>600,'style'=>'normal','lineHeightPx'=>72,'align'=>'left','color'=>'#ffffff','box'=>{'x'=>50,'y'=>50,'width'=>1000,'height'=>100}}],'evidence'=>{'facts'=>[],'sourceBlocks'=>[{'id'=>'fixture','sourceText'=>'Discover Everyday Comfort','sourceBox'=>{'x'=>20,'y'=>20,'width'=>500,'height'=>80},'coreIntent'=>'comfort','marketingFunction'=>'title','meaningUnitIds'=>['comfort']}],'rewrites'=>[{'blockId'=>'fixture','coreIntent'=>'comfort','marketingFunction'=>'title','action'=>'render','renderIndex'=>0,'omissionReason'=>'','preservedMeaningUnitIds'=>['comfort'],'usedFactIds'=>[],'omittedFactIds'=>[]}]}}
  response={'modelVersion'=>ReferenceProvider::ANALYSIS_MODEL,'candidates'=>[{'finishReason'=>'STOP','content'=>{'parts'=>[{'text'=>JSON.generate(synthetic)}]}}],'usageMetadata'=>{'promptTokenCount'=>10,'candidatesTokenCount'=>10,'totalTokenCount'=>20}}
  stages=[];positive=ReferenceProvider.propose(frozen,dir+'/positive',approval_for:lambda{|b|b},transport_for:lambda{|stage|stages<<stage;lambda{|*_|[200,JSON.generate(response)]}},mock:true)
  check.call(positive['state']=='awaiting-meaning-review'&&positive['backgroundCalls']==0&&stages==['layout-copy'],'schema-complete synthetic response parses; semantic review stops background')
  call_count=0;bad=lambda{|*_|call_count+=1;[400,'{"error":{"message":"User location is not supported for the API use."}}']}
  2.times{ReferenceProvider.execute(plan,dir+'/failure',approval:plan['binding'],mock:true,transport:bad)}
  check.call(call_count==1,'HTTP400 consumes one local attempt; repeated invocation does not retry')
  check.call(prompt.downcase.include?('headlight')&&prompt.include?('No brand was supplied')&&prompt.include?('Title Case')&&prompt.include?('Sentence case'),'selected final rules actually serialized into analysis prompt')
  File.write(out+'/result.json',JSON.pretty_generate({'checks'=>checks,'passed'=>checks.size,'newModelCalls'=>0,'transport'=>'injected local cache only','binding'=>plan['binding'],'dispatch'=>calls,'parserState'=>audit['state'],'pageDefaultAction'=>'direct image generation, not analysis; not clicked','providerAnalysisPath'=>'existing gated provider-prepare; no live UI analysis authorization','liveVerified'=>false}))
  puts JSON.generate({'passed'=>checks.size,'requestHash'=>plan['binding']['requestHash'],'newModelCalls'=>0})
 ensure
  [chrome,server].compact.each{|pid|Process.kill('TERM',pid) rescue nil;Process.wait(pid) rescue nil}
 end
end
