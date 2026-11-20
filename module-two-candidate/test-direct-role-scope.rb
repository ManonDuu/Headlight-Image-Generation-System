require_relative 'direct-image-plan'
root=File.join(__dir__,'assets/module-two-history');r=File.binread(root+'/reference.jpg');p=File.binread(root+'/product.jpg')
base=JSON.parse(File.read(root+'/candidate-v6-product-replacement-local.json'))['options'].merge('businessSpec'=>DirectImagePlan::SPEC)
n=0;ck=lambda{|v,m|raise m unless v;n+=1}
%w[reference-reconstruction product-replacement].product(%w[ai-rewrite custom remove-all-copy]).each do |mod,mode|
 o=base.merge('module'=>mod,'mode'=>mode);o=o.reject{|k,_|%w[productName sceneMode].include?(k)} if mod=='reference-reconstruction';o['customCopy']='mIxEd LED text' if mode=='custom'
 z=DirectImagePlan.prepare(r,mod=='product-replacement' ? p : nil,o);ck.call(DirectImagePlan.validate(z),'valid')
 parts=JSON.parse(z['body'])['contents'][0]['parts'];rules=z['trace']['ruleBindings'];t=parts[0]['text']
 z['binding']['imageRoles'].each do |role|
  blob=DirectImagePlan.image_part(z,role['role']);ck.call(Base64.strict_decode64(blob['data'])==(role['role']=='reference' ? r : p),'original bytes bound to role')
  ck.call(parts[role['part']-1]['text'].include?(role['sha256']),'adjacent label hash')
 end
 ck.call(t.include?('Reference font/style inheritance excludes letter case'),'case priority serialized')
 ck.call(t.include?('customCopy is the COMPLETE')==(mode=='custom'),'custom original case')
 if mod=='product-replacement'
  ck.call(parts[1]['text'].include?('exclude its original product appearance'),'reference excludes old product')
  ck.call(rules.find{|x|x['ruleId']=='proof'}['constraint'].include?('non-target'),'proof scope')
  ck.call(rules.find{|x|x['ruleId']=='palette'}['constraint'].include?('only from image 2'),'color source')
  bad=Marshal.load(Marshal.dump(z));b=JSON.parse(bad['body']);b['contents'][0]['parts'][2],b['contents'][0]['parts'][4]=b['contents'][0]['parts'][4],b['contents'][0]['parts'][2];bad['body']=JSON.generate(b)
  rejected=false;begin;DirectImagePlan.validate(bad);rescue;rejected=true;end;ck.call(rejected,'swapped bytes rejected')
 end
 bad=Marshal.load(Marshal.dump(z));b=JSON.parse(bad['body']);b['contents'][0]['parts'][1]['text']='REFERENCE: wrong hash';bad['body']=JSON.generate(b)
 rejected=false;begin;DirectImagePlan.validate(bad);rescue;rejected=true;end;ck.call(rejected,'tampered role label rejected')
end
old=JSON.parse(File.read(File.join(__dir__,'bridge-jobs/76cb6e8fb7d97ebf86d2f372/generic-gc-plan.json')));ck.call(DirectImagePlan.validate(old),'consumed v6 preserved')
puts "PASS #{n} module/mode/role/scope checks; zero external requests"
