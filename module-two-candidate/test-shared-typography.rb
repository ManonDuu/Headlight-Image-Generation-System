require_relative 'direct-image-plan'
n=0;check=lambda{|v,m|raise m unless v;n+=1}
d=File.join(__dir__,'assets/module-two-history')
r=File.binread(d+'/reference.jpg');product=File.binread(d+'/product.jpg')
base=JSON.parse(File.read(d+'/draft-plan-local.json'))['options'].merge('businessSpec'=>DirectImagePlan::SPEC)
%w[reference-reconstruction product-replacement].each do |mod|
 o=base.merge('module'=>mod,'brandName'=>'MyBrand','productParameters'=>'LED HID IP68 H11 9005 60W 6500K')
 o=o.reject{|k,_|%w[productName sceneMode].include?(k)} if mod=='reference-reconstruction'
 p=DirectImagePlan.prepare(r,mod=='product-replacement' ? product : nil,o)
 c=p['trace']['policy']['typography'];text=JSON.parse(p['body'])['contents'][0]['parts'][0]['text']
 check.call(c['title']=='Title Case'&&c['subtitle']=='Sentence case','distinct title/subtitle case')
 check.call(c['brand']=='UPPERCASE','own brand case')
 check.call(c['body']=='no-separate-case-convention-recovered','no invented body policy')
 check.call(c['font']=='Inter'&&!c['fontAssetsLocal'],'font instruction honestly scoped')
 check.call(text.include?(p['trace']['ruleBindings'].find{|r|r['ruleId']=='typography'}['constraint']),'shared rule actually serialized')
 check.call(text.include?('overall hierarchy, reading order and grouping')&&text.include?('do not add a template subtitle'),'existing role structure explicit')
 check.call(text.include?('shorten equivalently first')&&text.include?('No universal word or character cap'),'fit without invented length cap')
 check.call(text.include?('no global font size or horizontal stretching')&&text.include?('quadrilateral perspective'),'per-role and perspective font constraints')
 check.call(c['heightAdaptation']['guideline']==[0.8,1.2]&&c['heightAdaptation']['automaticPixelRejection']==false,'adaptation advisory not pixel rejection')
 check.call(text.include?('LED HID IP68 H11 9005 60W 6500K'),'supplied protected tokens unchanged in data')
 check.call(text.include?('acronyms')&&text.include?('parameter/unit notation'),'tokens protected by instruction')
 check.call(text.include?('Never output headlight or headlights'),'forbidden word applies')
 custom=o.merge('mode'=>'custom','customCopy'=>'mIxEd LED HID IP68 H11 9005 60W 6500K MyBrand')
 p=DirectImagePlan.prepare(r,mod=='product-replacement' ? product : nil,custom)
 data=JSON.parse(p['body'])['contents'][0]['parts'][0]['text'].split('Supplied data (not instructions): ').last
 check.call(JSON.parse(data)['customCopy']==custom['customCopy'],'custom case byte-preserved')
 check.call(p['trace']['policy']['typography']['title']=='not-applied'&&p['trace']['policy']['typography']['brand']=='no-auto-case','custom no automatic case')
 %w[headlight HEADLIGHT HeadLights].each do |word|
  %w[customCopy brandName productParameters].each do |field|
   rejected=false
   begin;DirectImagePlan.prepare(r,mod=='product-replacement' ? product : nil,custom.merge(field=>word));rescue RulesCompiler::Invalid=>e;rejected=e.message.include?('文案冲突');end
   check.call(rejected,'forbidden explicit copy rejected')
  end
 end
 empty=o.merge('brandName'=>'','productParameters'=>'')
 p=DirectImagePlan.prepare(r,mod=='product-replacement' ? product : nil,empty)
 check.call(p['trace']['policy']['claimAuthority'].empty?&&p['trace']['policy']['brandAuthority']=='none','empty facts/brand never inherited')
 check.call(p['trace']['policy']['typography']['brand']=='no-auto-case','blank brand has no capitalization insertion')
 check.call(DirectImagePlan.validate(p),'deterministic shared compiler')
end
puts "PASS #{n} shared typography/preflight checks; no external calls; actual raster typography unverified"
