require_relative 'bridge-server'
require 'tmpdir'
n=0;ck=lambda{|v,m|raise m unless v;n+=1};reject=lambda{|&f|begin;f.call;raise 'accepted invalid';rescue =>e;raise if e.message=='accepted invalid';n+=1;end}
r=File.binread(File.join(__dir__,'assets/81gMZuoRq6L._AC_SL1500_.jpg'));p=File.binread(File.join(__dir__,'fixtures/small-valid.jpg'))
base={'businessSpec'=>DirectImagePlan::SPEC,'module'=>'reference-reconstruction','mode'=>'ai-rewrite','layoutMode'=>'keep-reference','layoutTone'=>'keep-reference','output'=>{'aspectRatio'=>'12:15','imageSize'=>'2K'}}
%w[reference-reconstruction product-replacement].product(%w[remove-all-copy ai-rewrite custom],%w[keep-reference auto-layout],%w[keep-reference adjust-color]).each do |mod,mode,layout,tone|
 o=Marshal.load(Marshal.dump(base));o.merge!('module'=>mod,'mode'=>mode,'layoutMode'=>layout,'layoutTone'=>tone,'customCopy'=>'Exact Text','brandName'=>'Brand','productParameters'=>'60W');o['color']='#abcdef' if tone=='adjust-color'
 o.merge!('sceneMode'=>'keep','productName'=>'OFFLINE fixture') if mod=='product-replacement'
 z=DirectImagePlan.prepare(r,mod=='product-replacement' ? p : nil,o,mock:true);ck.call(DirectImagePlan.validate(z),'deterministic')
 b=JSON.parse(z['body']);text=b['contents'][0]['parts'][0]['text'];ck.call(z['binding']['analysisCalls']==0&&!z.key?('analysis')&&z['trace']['analysisOrigin']=='none-direct','no fabricated analysis')
 ck.call(z['binding']['model']=='gemini-3.1-flash-image'&&z['binding']['retries']==0,'fixed model and no retry')
 ck.call(z['trace']['ruleBindings'].all?{|x|text.include?(x['constraint'])},'trace exact request')
 ck.call(!text.include?('Exact Text')||mode=='custom','hidden copy excluded')
 ck.call(z['trace']['checks'].all?{|x|x['status']=='not-evaluated'},'no visual pass')
 ck.call(text.include?('Follow reference overall partitions')==(layout=='keep-reference'),'layout choice')
 ck.call(b['contents'][0]['parts'].size==(mod=='product-replacement' ? 5 : 3),'roles')
 if mod=='product-replacement'
  changed=DirectImagePlan.prepare(r,p,o.merge('sceneMode'=>'change'),mock:true);ck.call(changed['binding']['requestHash']!=z['binding']['requestHash'],'scene choice bound')
  bad=Marshal.load(Marshal.dump(z));ps=JSON.parse(bad['body']);ps['contents'][0]['parts'][2],ps['contents'][0]['parts'][4]=ps['contents'][0]['parts'][4],ps['contents'][0]['parts'][2];bad['body']=JSON.generate(ps);reject.call{DirectImagePlan.validate(bad)}
 end
end
RulesCompiler::SIZES.each_key{|ratio|z=DirectImagePlan.prepare(r,nil,base.merge('output'=>{'aspectRatio'=>ratio,'imageSize'=>'2K'}));ck.call(z['binding']['expectedDimensions']==RulesCompiler::SIZES[ratio],'native ratio')}
[{'layoutMode'=>'adjust-layout'},{'sceneMode'=>'keep'},{'mode'=>'no-copy'},{'layoutInstructions'=>'custom'},{'output'=>{'aspectRatio'=>'1:1','imageSize'=>'4K'}},{'mode'=>'custom','customCopy'=>'80W','productParameters'=>'60W'}].each{|bad|reject.call{DirectImagePlan.prepare(r,nil,base.merge(bad))}}
Dir.mktmpdir('direct-flow-') do |root|
 b=Bridge.new(mock:true,data:root,analysis_store:root+'/empty')
 def b.reference_analysis(*);raise 'must not analyze';end
 d=base.merge('imageBase64'=>Base64.strict_encode64(r),'sourceHash'=>Digest::SHA256.hexdigest(r),'budgetMicroUSD'=>260000)
 s=b.freeze_task(d);ck.call(s['state']=='frozen'&&s['workflow']=='direct-generation','freeze without analysis')
 req={'id'=>s['id'],'requestHash'=>s['genericGC']['requestHash']}
 b.generate_generic(req);100.times{break if b.snapshot(s['id'])['state']!='running';sleep 0.05};done=b.snapshot(s['id']);ck.call(done['state']=='mock-result','mock executes')
 ck.call(done['visualAcceptance']=='not-evaluated','HTTP not semantic acceptance');reject.call{b.generate_generic(req)}
 restarted=Bridge.new(mock:true,data:root);ck.call(restarted.snapshot(s['id'])['ruleTrace']==done['ruleTrace'],'restart restores trace');again=restarted.freeze_task(d);reject.call{restarted.generate_generic({'id'=>again['id'],'requestHash'=>again['genericGC']['requestHash']})}
 ck.call(Digest::SHA256.file(root+'/'+s['id']+'/output.jpg').hexdigest==done['outputHash'],'original download bytes')
 %w[empty error timeout over-budget multiple].each do |scenario|
  dir=root+'/'+scenario;runner=Bridge.new(mock:true,data:dir,analysis_store:dir+'/empty',scenario:scenario)
  dual=d.merge('module'=>'product-replacement','productImageBase64'=>Base64.strict_encode64(p),'productHash'=>Digest::SHA256.hexdigest(p),'productName'=>'OFFLINE fixture','sceneMode'=>'keep','budgetMicroUSD'=>270000)
  task=runner.freeze_task(dual);request={'id'=>task['id'],'requestHash'=>task['genericGC']['requestHash']}
  runner.generate_generic(request);100.times{break if runner.snapshot(task['id'])['state']!='running';sleep 0.05}
  ck.call(runner.snapshot(task['id'])['state']=='stopped','direct failure stops '+scenario)
  reject.call{runner.generate_generic(request)}
  after=Bridge.new(mock:true,data:dir);same=after.freeze_task(dual)
  reject.call{after.generate_generic({'id'=>same['id'],'requestHash'=>same['genericGC']['requestHash']})}
 end
 dir=root+'/interrupted';runner=Bridge.new(mock:true,data:dir);task=runner.freeze_task(d)
 ledger=runner.generic_ledger(task['genericGC']);Dir.mkdir(ledger);File.write(ledger+'/binding.json',JSON.generate(task['genericGC']))
 task['state']='running';File.write(dir+'/'+task['id']+'/state.json',JSON.generate(task))
 recovered=Bridge.new(mock:true,data:dir);ck.call(recovered.snapshot(task['id'])['error'].include?('remote outcome unknown'),'interrupted direct request remains unknown')
 reject.call{recovered.generate_generic({'id'=>task['id'],'requestHash'=>task['genericGC']['requestHash']})}
 another=recovered.freeze_task(d);reject.call{recovered.generate_generic({'id'=>another['id'],'requestHash'=>another['genericGC']['requestHash']})}
end
puts "PASS #{n} direct plans/roles/options/no-analysis/execution/restart checks; no external calls"
