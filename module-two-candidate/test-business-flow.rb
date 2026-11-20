require_relative 'bridge-server'
require 'tmpdir'
n=0;check=lambda{|v,label|raise label unless v;n+=1}
reject=lambda{|&f|begin;f.call;raise 'unexpected acceptance';rescue RulesCompiler::Invalid,VisualAnalysis::Invalid,RuntimeError=>e;raise if e.message=='unexpected acceptance';n+=1;end}
bytes=File.binread(File.join(__dir__,'assets/81gMZuoRq6L._AC_SL1500_.jpg'));hash=Digest::SHA256.hexdigest(bytes)
a=VisualAnalysis.mock_contract(hash,1200,1500)
a['labels']=[{'text'=>'60W IP68','role'=>'functional','region'=>'scene','box'=>[0,0,100,100],'certainty'=>'certain'}]
base={'businessSpec'=>BusinessRules::VERSION,'mode'=>'ai-rewrite','output'=>{'aspectRatio'=>'12:15','imageSize'=>'2K'},'layoutTone'=>'keep-reference','brandName'=>'','productParameters'=>''}
plans=[]
%w[ai-rewrite custom remove-all-copy].product(%w[keep-reference adjust-color],%w[follow-reference 1:1 12:15]).each do |mode,tone,ratio|
  o=Marshal.load(Marshal.dump(base));o['mode']=mode;o['layoutTone']=tone;o['color']='#123abc' if tone=='adjust-color';o['output']['aspectRatio']=ratio;o['customCopy']='Safe exact CASE' if mode=='custom'
  p=GenericGCPlan.prepare(bytes,a,o,allow_mock:true);plans<<p
  check.call(GenericGCPlan.validate(p),'deterministic freeze')
  trace=p['trace'];prompt=JSON.parse(p['body'])['contents'][0]['parts'][0]['text']
  active=o.reject{|k,_|mode=='remove-all-copy'&&%w[brandName productParameters customCopy].include?(k)}
  check.call(trace['selectedOptions']==active.merge('requestedOutput'=>o['output']),'active controls retained')
  check.call(trace['preflight']['removedReferenceParameters']==%w[60W IP68],'unverified parameters disclosed')
  check.call(prompt.include?(tone=='adjust-color' ? '#123abc' : 'overall color palette'),'color mapped')
  check.call(prompt.include?('Never crop or overlap key content'),'safe area mapped')
  check.call(!prompt.include?('Preserve every functional label verbatim'),'old copy directive absent')
end
check.call(plans.map{|p|p['binding']['requestHash']}.uniq.size==12,'ratio aliases share request only when equivalent')
reject.call{GenericGCPlan.prepare(bytes,a,base.merge('sceneMode'=>'keep'),allow_mock:true)}
reject.call{GenericGCPlan.prepare(bytes,a,base.merge('layoutTone'=>'adjust-color','color'=>'red'),allow_mock:true)}
reject.call{GenericGCPlan.prepare(bytes,a,base.merge('mode'=>'custom','customCopy'=>'60W','productParameters'=>'80W'),allow_mock:true)}
reject.call{GenericGCPlan.prepare(bytes,a,base.merge('mode'=>'custom','customCopy'=>'Brand: OTHER','brandName'=>'OWN'),allow_mock:true)}
ok=GenericGCPlan.prepare(bytes,a,base.merge('mode'=>'custom','customCopy'=>'60W Exact CASE','productParameters'=>'60W','brandName'=>'OWN'),allow_mock:true)
check.call(JSON.parse(ok['body'])['contents'][0]['parts'][0]['text'].include?('60W Exact CASE'),'custom exact text')
custom_only=GenericGCPlan.prepare(bytes,a,base.merge('mode'=>'custom','customCopy'=>'60W Exact CASE'),allow_mock:true)
check.call(!custom_only['trace']['preflight']['removedReferenceParameters'].include?('60W'),'custom copy facts accepted without separate params')
layout=GenericGCPlan.prepare(bytes,a,base.merge('layoutMode'=>'adjust-layout','layoutInstructions'=>'标题置顶'),allow_mock:true)
check.call(layout['body'].include?('标题置顶')&&!layout['body'].include?('Preserve reference layout and overall'),'layout independently mapped')
reject.call{GenericGCPlan.prepare(bytes,a,base.merge('layoutMode'=>'adjust-layout','layoutInstructions'=>''),allow_mock:true)}
none=GenericGCPlan.prepare(bytes,a,base.merge('mode'=>'remove-all-copy'),allow_mock:true)
inactive=GenericGCPlan.prepare(bytes,a,base.merge('mode'=>'remove-all-copy','brandName'=>'IGNORED','productParameters'=>'999W'),allow_mock:true)
check.call(none['body']==inactive['body']&&none['binding']==inactive['binding'],'inactive metadata does not change sent request')
Dir.mktmpdir('business-flow-') do |root|
  b=Bridge.new(mock:true,data:root)
  d=base.merge('module'=>'reference-reconstruction','imageBase64'=>Base64.strict_encode64(bytes),'sourceHash'=>hash,'budgetMicroUSD'=>260000)
  reject.call{b.freeze_task(d.merge('sceneMode'=>'keep'))}
  reject.call{b.freeze_task(d.merge('sceneMode'=>'change'))}
  reject.call{b.freeze_task(d.merge('productHash'=>hash))}
  %w[model endpoint fallbackModel].each{|key|reject.call{b.freeze_task(d.merge(key=>'unapproved-model'))}}
  s=b.freeze_task(d)
  check.call(s.dig('genericGC','model')=='gemini-3.1-flash-image'&&s.dig('genericGC','retries')==0,'fixed image model and no retry')
  check.call(s['module']=='reference-reconstruction'&&s['preflight']['brandAction']=='remove','module and preflight persisted')
  check.call(!JSON.generate(s['ruleTrace']).include?('imageBase64'),'trace excludes image payload')
  req={'id'=>s['id'],'requestHash'=>s['genericGC']['requestHash']};b.generate_generic(req)
  done=nil;200.times{done=b.snapshot(s['id']);break if done['state']!='running';sleep 0.05}
  check.call(done['state']=='mock-result','new business route executes mock')
  reject.call{b.generate_generic(req)}
  check.call(b.snapshot(s['id'])['preflight']==s['preflight'],'preflight retained in history')
end
puts "PASS #{n} business controls/rules/conflicts/module-isolation/freeze/history checks; zero network requests"
