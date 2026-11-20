require 'tmpdir'
require_relative 'bridge-server'
require_relative 'reconstruction-policy'
results=[]
def check(results,name)
 yield
 results<<{'name'=>name,'passed'=>true}
rescue =>e
 results<<{'name'=>name,'passed'=>false,'error'=>e.message}
end
def assert(v);raise 'assertion failed' unless v;end
source=File.binread('/Users/manrongdu/Downloads/71efzt2fH8L._AC_SL1500_.jpg')
base={'businessSpec'=>DirectImagePlan::SPEC,'module'=>'reference-reconstruction','mode'=>'custom','layoutTone'=>'adjust-color','color'=>'#2864C8','layoutMode'=>'auto-layout','customCopy'=>"Brighter Road Visibility\nLED\nHalogen",'output'=>{'aspectRatio'=>'1:1','imageSize'=>'2K'}}
check(results,'new request keeps image, literal copy and independent options') do
 p=DirectImagePlan.prepare(source,nil,base,mock:true,input_origin:'user');assert(DirectImagePlan.validate(p));body=JSON.parse(p['body']);text=body['contents'][0]['parts'][0]['text'];assert(text.include?('Original partitions and alignment are not constraints'));assert(text.include?('#2864C8'));assert(p['binding']['version']=='car-light-direct-20261021.20');assert(body['generationConfig']['imageConfig']['aspectRatio']=='1:1');assert(DirectImagePlan.image_part(p,'reference')['data']==Base64.strict_encode64(source));assert(p['options']['customCopy']==base['customCopy']);assert(p['binding']['analysisCalls']==0)
 q=Marshal.load(Marshal.dump(p));q['options']['customCopy']='tampered';begin;DirectImagePlan.validate(q);raise 'tampered plan accepted';rescue StandardError=>e;assert(e.message.include?('changed'));end
end
check(results,'v10 frozen history still validates without reinterpretation') do
 o=base.merge('businessSpec'=>DirectImagePlanV10::SPEC);p=DirectImagePlanV10.prepare(source,nil,o,mock:true,input_origin:'user');assert(DirectImagePlan.validate(p));assert(p['trace']['policy']['layoutScope']=='geometry-only')
end
check(results,'prepare endpoint method saves and reloads source and input provenance') do
 Dir.mktmpdir('inspired-history-') do |dir|
  bridge=Bridge.new(mock:true,data:dir)
  input=base.merge('imageBase64'=>Base64.strict_encode64(source),'sourceHash'=>Digest::SHA256.hexdigest(source),'budgetMicroUSD'=>260000)
  s=bridge.freeze_direct(input);assert(s['state']=='frozen');assert(s['rawUserOptions']['customCopy']==base['customCopy']);assert(s['rawUserOptions']['businessSpec']==DirectImagePlan::SPEC)
  bridge2=Bridge.new(mock:true,data:dir);restored=bridge2.snapshot(s['id']);assert(restored['requestHash']==s['requestHash']);assert(restored['rawUserOptions']==s['rawUserOptions']);assert(File.binread(File.join(dir,s['id'],'reference.jpg'))==source)
 end
end
check(results,'preserve source conflict is blocked without silently removing words') do
 # Deterministic fixture replaces only OCR in this offline test, never production input.
 module LocalReferenceOCR
  class << self;alias_method :original_observe_for_test,:observe;end
  def self.observe(bytes,hash);{'lines'=>[{'text'=>'600% BRIGHTER','confidence'=>0.99}],'sourceHash'=>hash};end
 end
 begin
  o=base.merge('mode'=>'preserve-reference');o.delete('customCopy');begin;DirectImagePlan.prepare(source,nil,o,mock:true,input_origin:'test');raise 'unsupported claim accepted';rescue StandardError=>e;assert(e.message.include?('600%'));end
 ensure
  module LocalReferenceOCR;class << self;alias_method :observe,:original_observe_for_test;end;end
 end
end
check(results,'v11 candidate history remains bound to previous rules') do
 o=base.merge('businessSpec'=>DirectImagePlanV11::SPEC);p=DirectImagePlanV11.prepare(source,nil,o,mock:true,input_origin:'user');assert(DirectImagePlan.validate(p));assert(p['trace']['policy']['version']=='reference-inspired-20261021.1')
end
check(results,'matching preserve metadata does not cause an artificial conflict') do
 o=base.merge('mode'=>'preserve-reference','brandName'=>'MyBrand','productParameters'=>'20W');o.delete('customCopy')
 r=ReconstructionPolicy.compile(o,source_copy:['MyBrand','20W','Road Visibility']);assert(r['sendAllowed']);assert(r['sourceCopy']==['MyBrand','20W','Road Visibility'])
end
check(results,'AI rewrite removes unspecified competitor brands without adding new slots') do
 o=base.merge('mode'=>'ai-rewrite');o.delete('customCopy');p=DirectImagePlan.prepare(source,nil,o,mock:true,input_origin:'test');text=JSON.parse(p['body'])['contents'][0]['parts'][0]['text'];assert(text.include?('when brandName is empty, omit branding entirely'));assert(text.include?('first letter of EVERY ordinary English word'));assert(text.include?('Never output headlight or headlights'))
end
check(results,'v12 frozen requests retain their original policy and validate') do
 o=base.merge('businessSpec'=>DirectImagePlanV12::SPEC)
 p=DirectImagePlanV12.prepare(source,nil,o,mock:true,input_origin:'test')
 assert(DirectImagePlan.validate(p));assert(p['trace']['policy']['version']=='reference-inspired-20261021.2')
 assert(!JSON.parse(p['body'])['contents'][0]['parts'][0]['text'].include?('copy-density'))
end
check(results,'density defaults only affect AI rewriting across layout and palette choices') do
 ReconstructionPolicy::MODES.product(ReconstructionPolicy::LAYOUTS,ReconstructionPolicy::TONES).each do |mode,layout,tone|
  o=base.merge('mode'=>mode,'layoutMode'=>layout,'layoutTone'=>tone,'color'=>'#F5C400')
  r=ReconstructionPolicy.compile(o,source_copy:['Road Visibility'])
  density=r['rules'].find{|x|x['id']=='copy-density'}
  assert(!!density==(mode=='ai-rewrite'))
  assert(r['rules'].any?{|x|x['id']=='design-learning'})
  assert(r['rules'].any?{|x|x['id']=='visual-meaning'})
  scene=r['rules'].find{|x|x['id']=='scene'}['constraint']
  assert(scene.include?('multi-scene storytelling'))
  assert(r['rules'].find{|x|x['id']=='palette'}['constraint'].include?('#F5C400')) if tone=='adjust-color'
 end
end
check(results,'v13 recorded request still validates after claim-rule update') do
 p=JSON.parse(File.read(File.join(__dir__,'reference-041629-v13-plan.json')))
 assert(DirectImagePlan.validate(p));assert(p['trace']['policy']['version']=='reference-inspired-20261021.3')
end
check(results,'numeric-source deletion applies only to AI rewrite and respects supplied facts') do
 %w[custom preserve-reference remove-all-copy ai-rewrite].each do |mode|
  r=ReconstructionPolicy.compile(base.merge('mode'=>mode),source_copy:['Road Visibility'])
  rule=r['rules'].find{|x|x['id']=='rewrite-claims'}
  assert(!!rule==(mode=='ai-rewrite'))
  assert(rule['constraint'].include?('No target parameters supplied')) if rule
 end
 r=ReconstructionPolicy.compile(base.merge('mode'=>'ai-rewrite','productParameters'=>'20W'))
 assert(r['rules'].find{|x|x['id']=='rewrite-claims'}['constraint'].include?('explicitly supplied productParameters'))
end
check(results,'manual original transcript preserves words and conflict checks without OCR') do
 o=base.merge('mode'=>'preserve-reference','referenceCopy'=>"Brighter Road Visibility\nLED\nHalogen")
 o.delete('customCopy')
 p=DirectImagePlan.prepare(source,nil,o,mock:true,input_origin:'user')
 assert(DirectImagePlan.validate(p))
 text=JSON.parse(p['body'])['contents'][0]['parts'][0]['text']
 assert(text.include?('Brighter Road Visibility'))
 [['ai-rewrite','Road Visibility'],['preserve-reference','600% BRIGHTER']].each do |mode,copy|
  blocked=false
  begin;DirectImagePlan.prepare(source,nil,o.merge('mode'=>mode,'referenceCopy'=>copy),mock:true,input_origin:'user');rescue StandardError;blocked=true;end
  assert(blocked)
 end
end
report={'checks'=>results,'passed'=>results.count{|r|r['passed']},'failed'=>results.count{|r|!r['passed']},'networkCalls'=>0,'browserVerified'=>false,'productionModified'=>false}
File.write(File.join(__dir__,'integration-report.json'),JSON.pretty_generate(report));puts JSON.pretty_generate(report);exit(report['failed']==0 ? 0 : 1)
