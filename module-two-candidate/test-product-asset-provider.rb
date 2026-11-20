require_relative 'product-asset-provider'
require 'tmpdir'
checks=[];ok=lambda{|v,m|raise m unless v;checks<<m}
f=JSON.parse(File.read(File.join(__dir__,'diagnostics/today-real-input-readiness/product-replacement-live-plan.json')))
a=ProductAssetProvider.prepare(f)
# A local schema fixture is deliberately distinct from any claimed real analysis.
l=JSON.parse(File.read(File.join(__dir__,'diagnostics/preflight-wire-20261018/candidate-policy-replay.json')))['plan'];l['text']=[]
no_copy=DirectImagePlan.prepare(Base64.strict_decode64(DirectImagePlan.image_part(f,'reference')['data']),Base64.strict_decode64(DirectImagePlan.image_part(f,'product-appearance')['data']),f['options'].merge('businessSpec'=>DirectImagePlan::SPEC,'mode'=>'remove-all-copy'),mock:false)
proposal={'layout'=>l,'productSlot'=>{'x'=>200,'y'=>400,'width'=>1000,'height'=>1700}}
b=ProductAssetProvider.prepare(no_copy,'background',proposal)
parts=JSON.parse(b['body'])['contents'][0]['parts'];ok.call(parts.size==2&&parts.last['inlineData']['data']==DirectImagePlan.image_part(f,'reference')['data'],'background request contains reference only');ok.call(parts[0]['text'].include?('Do not draw a replacement product')&&parts[0]['text'].include?('Remove every old target-product instance'),'background-only constraints explicitly remove old product')
ok.call(b['binding']['budgetMicroUSD']==260000&&b['binding']['retries']==0,'background budget single-call bound')
Dir.mktmpdir do |root|
 calls=0;approval={'id'=>'MOCK-local-failure-only','analysisRequestHash'=>a['binding']['requestHash'],'maxRequests'=>2,'budgetMicroUSD'=>280000}
 result=ProductAssetProvider.execute(f,root,approval:approval,transport:lambda{|*args|calls+=1;[400,'{"error":{"message":"fixture failure"}}']},mock:true)
 ok.call(calls==1&&result['state']=='stopped'&&result['newModelCalls']==1,'analysis failure stops before background')
 begin;ProductAssetProvider.execute(f,root,approval:approval,transport:lambda{|*args|calls+=1},mock:true);raise 'retry allowed';rescue RuntimeError=>e;raise unless e.message=='attempt exists; never retry';end
 ok.call(calls==1,'attempt ledger blocks repeated dispatch')
end
File.write(File.join(__dir__,'diagnostics/product-auto-20261018/provider-test.json'),JSON.pretty_generate({checks:checks,newExternalCalls:0}));puts JSON.generate({checks:checks.size,newExternalCalls:0})
