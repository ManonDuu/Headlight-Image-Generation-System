require_relative 'bridge-server'
n=0
check=lambda{|v,label|raise label unless v;n+=1}
reject=lambda do |label,&block|
 begin;block.call;raise 'unexpected success: '+label;rescue VisualAnalysis::Invalid,JSON::ParserError;n+=1;end
end
live_guard=Bridge.allocate;live_guard.instance_variable_set(:@mock,false)
begin;live_guard.run_analysis({},{});raise 'live guard missing';rescue => e;check.call(e.message.include?('paid execution disabled'),'live analysis stays hard locked');end
paused=Bridge.allocate;paused.instance_variable_set(:@mock,false)
begin;paused.generate('unused','unused');raise 'pause missing';rescue=>e;check.call(e.message.include?('live generation locked'),'live generation paused before any file/request');end
hash='a'*64;
a=VisualAnalysis.mock_contract(hash,320,240)
check.call(VisualAnalysis.validate(a,hash,320,240,allow_mock:true)==a,'valid schema')
mutations=[['extra',true],['readingOrder',[]],['rulesVersion','stale'],['sourceHash','b'*64],['width',321],['schemaVersion','old']]
mutations.each{|k,v|reject.call(k){VisualAnalysis.validate(a.merge(k=>v),hash,320,240,allow_mock:true)}}
reject.call('mock cannot enter live'){VisualAnalysis.validate(a,hash,320,240)}
reject.call('duplicate JSON keys'){VisualAnalysis.parse_json('{"x":1,"x":2}')}
bad=Marshal.load(Marshal.dump(a));bad['regions'][0]['box']=[319,0,2,240];reject.call('bounds'){VisualAnalysis.validate(bad,hash,320,240,allow_mock:true)}
bad=Marshal.load(Marshal.dump(a));bad['labels']=[{'text'=>'unclear','role'=>'functional','region'=>'scene','box'=>[0,0,20,20],'certainty'=>'ambiguous'}];reject.call('OCR uncertainty'){VisualAnalysis.validate(bad,hash,320,240,allow_mock:true)}
bad=Marshal.load(Marshal.dump(a));bad['uncertainties']<<{'field'=>'proof','reason'=>'unclear','severity'=>'blocking'};reject.call('uncertain evidence'){VisualAnalysis.validate(bad,hash,320,240,allow_mock:true)}
Dir.mktmpdir('analysis-tests-') do |dir|
 bytes=File.binread(File.join(__dir__,'assets','81gMZuoRq6L._AC_SL1500_.jpg'));h=Digest::SHA256.hexdigest(bytes)
 store=AnalysisStore.new(File.join(dir,'store'),mock:true);plan=store.prepare(bytes,1200,1500)
 check.call(plan['request']['model']=='gemini-3.5-flash-lite'&&plan['request']['store']==false,'fixed model/privacy')
 check.call(plan['request']['generation_config']['max_output_tokens']==4096&&!plan['request'].key?('tools'),'bounded/no tools')
 approval={'requestHash'=>plan['requestHash'],'budgetMicroUSD'=>20000};calls=0
 transport=lambda do |_|
   calls+=1;{'model'=>VisualAnalysis::MODEL,'status'=>'completed','steps'=>[{'type'=>'model_output','content'=>[{'type'=>'text','text'=>JSON.generate(VisualAnalysis.mock_contract(h,1200,1500))}]}],'usage'=>{'total_input_tokens'=>1120,'total_output_tokens'=>200,'total_thought_tokens'=>0,'total_tokens'=>1320}}
 end
 reject.call('old approval'){store.execute(plan,transport:transport,approval:{'requestHash'=>plan['requestHash'],'budgetMicroUSD'=>260000})}
 check.call(calls==0&&!File.exist?(store.paths(h)+'.attempt'),'no spend without approval')
 store.execute(plan,transport:transport,approval:approval);store.execute(plan,transport:transport,approval:approval)
 check.call(calls==1,'cache avoids repeated analysis')
 check.call(store.prepare(bytes,1200,1500)['state']=='analysis-cached','cache persists')
 newstore=AnalysisStore.new(File.join(dir,'store'),mock:true);check.call(newstore.fetch(h,1200,1500)['sourceHash']==h,'restart cache')
 doc=JSON.parse(File.read(store.paths(h)+'.json'));doc['analysis']['viewpoint']='changed';File.write(store.paths(h)+'.json',JSON.generate(doc));reject.call('tampered cache'){store.fetch(h,1200,1500)}
 failed=AnalysisStore.new(File.join(dir,'failure'),mock:true);p2=failed.prepare(bytes,1200,1500);badcalls=0
 twice=lambda{|_|badcalls+=1;raise VisualAnalysis::Invalid,'timeout'}
 2.times{reject.call('no retry after timeout'){failed.execute(p2,transport:twice,approval:approval)}}
 check.call(badcalls==1&&File.read(File.join(failed.paths(h)+'.attempt','status'))=='stopped','persistent timeout lock')
 response=transport.call(nil)
 [['status','incomplete'],['model','other'],['usage',{}]].each{|k,v|reject.call(k){VisualAnalysis.response(response.merge(k=>v),h,1200,1500,allow_mock:true)}}
 # Two independently generated test JPEGs; no known-reference lookup or copied geometry.
 [[320,240],[240,360]].each_with_index do |(w,hh),i|
  chunk=lambda{|type,data|[data.bytesize].pack('N')+type+data+[Zlib.crc32(type+data)].pack('N')}
  png="\x89PNG\r\n\x1a\n".b+chunk.call('IHDR',[w,hh,8,2,0,0,0].pack('NNCCCCC'))+chunk.call('IDAT',Zlib::Deflate.deflate(("\x00".b+([20+i*60,100,160].pack('CCC')*w))*hh))+chunk.call('IEND',''.b)
  path=File.join(dir,"new-#{i}.png");jpg=File.join(dir,"new-#{i}.jpg");File.binwrite(path,png);_,st=Open3.capture2(File.expand_path('../deploy/image_probe.py',__dir__),'-s','format','jpeg',path,'--out',jpg,err:File::NULL);raise 'fixture conversion failed' unless st.success?
  image=File.binread(jpg);sha=Digest::SHA256.hexdigest(image);b=Bridge.new(mock:true,data:File.join(dir,"bridge-#{i}"))
  d={'module'=>'reference-reconstruction','mode'=>i==0 ? 'no-copy' : 'custom','output'=>{'aspectRatio'=>'4:5','imageSize'=>'2K'},'layoutTone'=>'keep-reference','budgetMicroUSD'=>260000,'sourceHash'=>sha,'imageBase64'=>Base64.strict_encode64(image)};d['customCopy']='Keep EXACT case' if i==1
  s=b.freeze_task(d);check.call(s['state']=='frozen'&&s['ruleTrace']['analysis']['sourceHash']==sha,'unknown image auto-analysis pipeline')
  gc=JSON.parse(File.read(File.join(dir,"bridge-#{i}",s['id'],'generic-gc-plan.json')))
  check.call(GenericGCPlan.validate(gc)&&gc['binding']['sourceHash']==sha&&gc['binding']['liveEnabled']==false,'new image GC candidate frozen and locked')
  check.call(s['ruleTrace']['analysis']['regions'][0]['box']==[0,0,w,hh],'new dimensions, not sample geometry')
  b.generate(s['id'],s['requestHash']);100.times{sleep 0.05;break unless b.snapshot(s['id'])['state']=='running'}
  check.call(b.snapshot(s['id'])['state']=='mock-result','new image end-to-end')
 end
end
puts "PASS #{n} visual analysis/schema/cache/new-image end-to-end checks. No model requests."
