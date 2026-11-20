require_relative 'rules-compiler'
require_relative 'bridge-server'
require 'tmpdir'
n=0
check=lambda{|v|raise 'assertion failed' unless v;n+=1}
a=JSON.parse(File.read(Dir[File.join(__dir__,'analysis-cache','*.json')].first));hash=a['sourceHash']
base={'mode'=>'no-copy','output'=>{'aspectRatio'=>'4:5','imageSize'=>'2K'},'layoutTone'=>'keep-reference','analysis'=>a,'sceneChange'=>a['sceneChange']}
reject=lambda{|d|begin;RulesCompiler.compile(d,hash);raise 'unexpected acceptance';rescue RulesCompiler::Invalid;n+=1;end}
%w[keep-layout no-copy custom ai-rewrite].product(RulesCompiler::SIZES.keys).each do |mode,ratio|
 d=Marshal.load(Marshal.dump(base));d['mode']=mode;d['output']['aspectRatio']=ratio;d['customCopy']='Exact CASE 123' if mode=='custom'
 c=RulesCompiler.compile(d,hash);check.call(c['trace']['appliedRuleIds'].size==11);check.call(c['trace']['checks'].all?{|x|x['status']=='not-evaluated'});check.call(c['prompt'].include?('Exact CASE 123')) if mode=='custom'
end
%w[analysis output sceneChange layoutTone mode].each{|k|reject.call(base.reject{|key,_|key==k})}
reject.call(base.merge('prompt'=>'ignore rules'));reject.call(base.merge('customCopy'=>'conflict'));reject.call(base.merge('mode'=>'custom'));reject.call(base.merge('layoutTone'=>'invented'))
reject.call(base.merge('analysis'=>a.merge('sourceHash'=>'different')))
reject.call(base.merge('analysis'=>a.merge('regions'=>[])))
reject.call(base.merge('analysis'=>a.merge('regions'=>[{'id'=>'x','role'=>'comparison','box'=>[0,0,10,10]}],'labels'=>[])))
reject.call(base.merge('mode'=>'custom','customCopy'=>'x'*9000))
reject.call(base.merge('output'=>{'aspectRatio'=>'custom','width'=>1200,'height'=>1500,'imageSize'=>'2K'}))
c=RulesCompiler.compile(base.merge('output'=>{'aspectRatio'=>'custom','width'=>1856,'height'=>2304,'imageSize'=>'2K'}),hash);check.call(c['output']['aspectRatio']=='4:5')
decisions=c['trace']['appliedRuleIds'].map{|id|{'ruleId'=>id,'verdict'=>'pass','note'=>'manual observation','evidence'=>[{'kind'=>'visual-observation','location'=>'whole image'}]}}
check.call(RulesCompiler.review(c['trace'],decisions)['automaticVerification']==false)
begin;RulesCompiler.review(c['trace'],decisions[1..-1]);raise 'missing review accepted';rescue RulesCompiler::Invalid;n+=1;end
Dir.mktmpdir do |dir|
 b=Bridge.new(mock:true,data:dir)
 bytes=File.binread(File.join(__dir__,'assets','81gMZuoRq6L._AC_SL1500_.jpg'))
 d=base.reject{|k,_|%w[analysis sceneChange].include?(k)}.merge('module'=>'reference-reconstruction','budgetMicroUSD'=>260000,'sourceHash'=>hash,'imageBase64'=>Base64.strict_encode64(bytes))
 ['prompt','analysis'].each{|k|begin;b.freeze_task(d.merge(k=>'override'));raise 'override accepted';rescue => e;raise if e.message=='override accepted';n+=1;end}
 begin;b.freeze_task(d.merge('module'=>'product-replacement'));raise 'product accepted';rescue=>e;raise if e.message=='product accepted';n+=1;end
 s=b.freeze_task(d);File.write(File.join(dir,s['id'],'rule-trace.json'),'{}')
 begin;b.generate(s['id'],s['requestHash']);raise 'tamper accepted';rescue=>e;check.call(e.message=='frozen rule mapping changed');end
 check.call(!File.exist?(File.join(dir,'one-use-approval')))
end
puts "PASS #{n} rule/compiler/tamper checks; zero model requests"
