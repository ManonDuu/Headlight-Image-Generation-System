require_relative 'product-replacement-plan'
require_relative 'business-rules'
n=0
check=lambda{|ok|raise 'assertion failed' unless ok;n+=1}
reject=lambda{|&b|begin;b.call;raise 'unexpected acceptance';rescue VisualAnalysis::Invalid,RulesCompiler::Invalid;n+=1;end}
r=File.binread(File.join(__dir__,'assets/81gMZuoRq6L._AC_SL1500_.jpg'))
p=File.binread(File.join(__dir__,'fixtures/small-valid.jpg'))
a=VisualAnalysis.mock_contract(Digest::SHA256.hexdigest(r),1200,1500);a['regions'][0]['role']='structure'
old={'mode'=>'no-copy','output'=>{'aspectRatio'=>'4:5','imageSize'=>'2K'},'layoutTone'=>'keep-reference','sceneMode'=>'keep','productName'=>'OFFLINE synthetic fixture','targetRegions'=>[a['regions'][0]['id']]}
legacy=ProductReplacementPlan.prepare(r,p,a,old,allow_mock:true)
check.call(Digest::SHA256.hexdigest(JSON.generate(legacy))=='ea1303514b026556aee8c3213e11167064d4f284918906643515d3dc19d9cc71')
base=old.merge('businessSpec'=>BusinessRules::VERSION,'sceneMode'=>'change','mode'=>'ai-rewrite')
plan=nil
%w[ai-rewrite custom remove-all-copy].product(%w[follow-reference 12:15 1:1],%w[keep-reference adjust-color],%w[keep change]).each do |mode,ratio,tone,scene|
 o=Marshal.load(Marshal.dump(base));o['sceneMode']=scene;o['mode']=mode;o['output']['aspectRatio']=ratio;o['layoutTone']=tone
 o['color']='#12AbEF' if tone=='adjust-color';o['customCopy']='Fresh Road Light' if mode=='custom'
 z=ProductReplacementPlan.prepare(r,p,a,o,allow_mock:true);body=JSON.parse(z['body']);text=body['contents'][0]['parts'][0]['text']
 check.call(ProductReplacementPlan.validate(z))
 check.call(z['binding']['sourceHash']==Digest::SHA256.hexdigest(r)&&z['binding']['productHash']==Digest::SHA256.hexdigest(p))
 check.call(Base64.strict_decode64(body['contents'][0]['parts'][1]['inlineData']['data'])==r&&Base64.strict_decode64(body['contents'][0]['parts'][2]['inlineData']['data'])==p)
 check.call(text.include?('never paste a flat cutout')&&text.include?('physical printed/engraved markings')&&text.include?('background and graphic elements'))
 check.call(z['preflight']['physicalText']=='preserve-and-review'&&z['preflight']['parameterAuthority']==(mode=='custom' ? 'custom-copy-and-optional-parameters' : 'none')&&z['preflight']['brandAction']=='remove')
 check.call(z['trace']['expectedDimensions']==(ratio=='1:1' ? [2048,2048] : [1856,2304]))
 check.call(z['preflight']['resolvedOutput']['requested']['aspectRatio']==ratio)
 check.call(z['preflight']['warnings'].any?{|w|w.include?('最接近')}) if ratio=='follow-reference'
 check.call(z['binding']['maxRequests']==1&&z['binding']['retries']==0&&z['binding']['liveEnabled']==false)
 check.call(z["trace"]["sceneMode"]==scene&&z["trace"]["selectedOptions"]["sceneMode"]==scene)
 if scene=="keep"
   check.call(!text.include?("Change concrete same-type scene details")&&!text.include?("Require BOTH structural")&&!text.include?("Reconstruct the background"))
   check.call((z["trace"]["appliedRuleIds"]&%w[scene-difference joint-acceptance role-boundary]).empty?)
   check.call(!text.include?("\"sceneChange\":")&&!text.include?("\"mutableScene\":"))
 else
   check.call(text.include?("Reconstruct the background")&&z["trace"]["appliedRuleIds"].include?("scene-difference"))
 end
 plan=z
end
z=ProductReplacementPlan.prepare(r,p,a,base.merge('brandName'=>'ROAD','productParameters'=>'12V 40W'),allow_mock:true)
check.call(z['preflight']['parameterAuthority']=='supplied'&&z['preflight']['brandAction']=='replace')
reject.call{ProductReplacementPlan.prepare(r,p,a,base.merge('mode'=>'custom','customCopy'=>'60W','productParameters'=>'40W'),allow_mock:true)}
reject.call{ProductReplacementPlan.prepare(r,p,a,base.merge('sceneMode'=>'unsupported'),allow_mock:true)}
reject.call{ProductReplacementPlan.prepare(r,p,a,base.reject{|k,_|k=='targetRegions'},allow_mock:true)}
weather=Marshal.load(Marshal.dump(a));weather['regions'][0]['role']='weather-carrier'
reject.call{ProductReplacementPlan.prepare(r,p,weather,base,allow_mock:true)}
reject.call{ProductReplacementPlan.prepare(r,p,a,base.merge('mode'=>'no-copy'),allow_mock:true)}
reject.call{ProductReplacementPlan.prepare(r,p,a,base.merge('layoutTone'=>'adjust-color','color'=>'blue'),allow_mock:true)}
reject.call{ProductReplacementPlan.prepare(r,p,a,base)}
%w[body binding trace preflight options].each do |field|
 t=Marshal.load(Marshal.dump(plan));field=='body' ? t[field]+=' ' : t[field]['unexpected']='tamper';reject.call{ProductReplacementPlan.validate(t)}
end
keep=ProductReplacementPlan.prepare(r,p,a,base.merge("sceneMode"=>"keep"),allow_mock:true)
change=ProductReplacementPlan.prepare(r,p,a,base,allow_mock:true)
check.call(keep["binding"]["requestHash"]!=change["binding"]["requestHash"])
check.call(keep["trace"]["promptHash"]!=change["trace"]["promptHash"])
# Layout choice is independent of scene choice; dormant text fields cannot affect requests.
%w[keep change].each do |scene|
 opts=base.merge('sceneMode'=>scene,'layoutMode'=>'adjust-layout','layoutInstructions'=>'Move the heading above the image; keep product unchanged.')
 adjusted=ProductReplacementPlan.prepare(r,p,a,opts,allow_mock:true)
 check.call(ProductReplacementPlan.validate(adjusted))
 check.call(adjusted['trace']['selectedOptions']['layoutMode']=='adjust-layout')
 text=JSON.parse(adjusted['body'])['contents'][0]['parts'][0]['text']
 check.call(text.include?('Move the heading above the image; keep product unchanged.'))
 check.call(!text.include?('camera, composition and lighting conditions unchanged'))
 check.call(text.include?('independently selected layoutMode'))
 retained=ProductReplacementPlan.prepare(r,p,a,base.merge('sceneMode'=>scene,'layoutMode'=>'keep-reference'),allow_mock:true)
 check.call(retained['binding']['requestHash']!=adjusted['binding']['requestHash'])
end
plain=base.merge('mode'=>'remove-all-copy','layoutMode'=>'keep-reference')
dormant=plain.merge('brandName'=>'DORMANT_BRAND','productParameters'=>'987W','customCopy'=>'DORMANT_COPY 654V')
untouched=Marshal.load(Marshal.dump(dormant))
clean=ProductReplacementPlan.prepare(r,p,a,plain,allow_mock:true)
with_dormant=ProductReplacementPlan.prepare(r,p,a,dormant,allow_mock:true)
check.call(clean==with_dormant)
check.call(dormant==untouched)
check.call((with_dormant['options'].keys&%w[brandName productParameters customCopy]).empty?)
check.call(!with_dormant['body'].include?('DORMANT_')&&!with_dormant['body'].include?('987W'))
custom=ProductReplacementPlan.prepare(r,p,a,base.merge('mode'=>'custom','customCopy'=>'Power 60W','layoutMode'=>'keep-reference'),allow_mock:true)
check.call(ProductReplacementPlan.validate(custom))
check.call(JSON.parse(custom['body'])['contents'][0]['parts'][0]['text'].include?('Power 60W'))
reject.call{ProductReplacementPlan.prepare(r,p,a,base.merge('layoutMode'=>'adjust-layout'),allow_mock:true)}
puts "PASS #{n} product business checks; legacy whole-plan hash unchanged; zero requests"
