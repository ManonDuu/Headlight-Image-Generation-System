require_relative 'generic-gc-plan'
require_relative 'product-replacement-plan'
n=0;check=lambda{|v,msg|raise msg unless v;n+=1}
audit=[]
trace_check=lambda do |z,module_name,text|
 bindings=z['trace'].fetch('ruleBindings')
 check.call(bindings.map{|b|b['ruleId']}.sort==z['trace']['appliedRuleIds'].sort,'all and only applied rules traced')
 check.call(bindings.all?{|b|text.include?(b['constraint'])&&b['resultStatus']=='not-evaluated'&&!b['sourceOptions'].empty?},'trace must match serialized prompt without claiming visual pass')
 if z['trace']['selectedOptions']['layoutMode']=='auto-layout'
   check.call(!text.include?('Stop if a major layout change is needed')&&!text.include?('subjective label moves')&&!text.include?('Preserve vacated layout'),'no automatic-layout contradiction')
 else
   check.call(text.include?('Preserve relative region geometry')&&text.include?('partitions'),'reference geometry locked')
 end
 audit<<{'module'=>module_name,'requestHash'=>z['binding']['requestHash'],'model'=>z['binding']['model'],'ruleVersion'=>z['trace']['compilerRevision'],'selectedOptions'=>z['trace']['selectedOptions'],'serializedPrompt'=>text,'ruleBindings'=>bindings,'sent'=>false,'resultStatus'=>'not-evaluated'}
end
r=File.binread(File.join(__dir__,'assets/81gMZuoRq6L._AC_SL1500_.jpg'));p=File.binread(File.join(__dir__,'fixtures/small-valid.jpg'))
a=VisualAnalysis.mock_contract(Digest::SHA256.hexdigest(r),1200,1500)
base={'businessSpec'=>BusinessRules::CURRENT,'mode'=>'ai-rewrite','layoutMode'=>'keep-reference','layoutTone'=>'keep-reference','output'=>{'aspectRatio'=>'12:15','imageSize'=>'2K'}}
%w[ai-rewrite custom remove-all-copy].product(%w[keep-reference auto-layout],%w[keep-reference adjust-color]).each do |mode,layout,tone|
 o=base.merge('mode'=>mode,'layoutMode'=>layout,'layoutTone'=>tone,'customCopy'=>mode=='custom' ? 'Exact text' : 'HIDDEN OLD TEXT');o['color']='#de805b' if tone=='adjust-color'
 z=GenericGCPlan.prepare(r,a,o,allow_mock:true);text=JSON.parse(z['body'])['contents'][0]['parts'][0]['text']
 check.call(GenericGCPlan.validate(z),'reference deterministic');check.call(!text.include?('HIDDEN OLD TEXT'),'hidden copy leaked');check.call(text.include?('Never tint scene backgrounds'),'scene palette protected');check.call(!text.include?('to background and graphic accents'),'old palette directive');check.call(text.include?('Choose a clear, balanced layout automatically')==(layout=='auto-layout'),'layout mapping')
 trace_check.call(z,'reference-reconstruction',text)
 pa=Marshal.load(Marshal.dump(a));pa['regions'][0]['role']='structure'
 %w[keep change].each do |scene|
  po=o.merge('sceneMode'=>scene,'productName'=>'OFFLINE fixture','targetRegions'=>[pa['regions'][0]['id']]);z=ProductReplacementPlan.prepare(r,p,pa,po,allow_mock:true);text=JSON.parse(z['body'])['contents'][0]['parts'][0]['text']
  check.call(ProductReplacementPlan.validate(z),'product deterministic');check.call(!text.include?('HIDDEN OLD TEXT'),'product hidden copy');check.call(!text.include?('background and graphic elements')&&!text.include?('background/graphic color'),'product palette');check.call(z['trace']['businessSpec']==BusinessRules::CURRENT,'new spec traced')
  trace_check.call(z,'product-replacement',text)
 end
end
[{'mode'=>'keep-layout'},{'mode'=>'no-copy'},{'layoutMode'=>'adjust-layout','layoutInstructions'=>'old'},{'layoutMode'=>'auto-layout','layoutInstructions'=>'old'}].each do |bad|
 begin;GenericGCPlan.prepare(r,a,base.merge(bad),allow_mock:true);raise 'accepted retired option';rescue RulesCompiler::Invalid;n+=1;end
end
html=File.read(File.join(__dir__,'bridge.html'));check.call(!html.include?('员工')&&!html.include?('输出质量')&&!html.include?('layoutInstructions'),'retired UI removed')
File.write(File.join(__dir__,'RULE-REQUEST-TRACE-20261018.json'),JSON.pretty_generate({'kind'=>'offline-fixture-audit','newModelCalls'=>0,'cases'=>audit}))
puts "PASS #{n} simplified two-module checks; zero requests"
