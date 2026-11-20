# Offline only; prepares reviewable live-format requests, never dispatches or reads credentials.
require_relative 'direct-image-plan'
root=File.expand_path(__dir__);dir=root+'/diagnostics/today-real-input-readiness';summary=[]
%w[reference-reconstruction product-replacement].each do |mod|
 prior=JSON.parse(File.read(dir+'/'+mod+'-mock-plan.json'));o=prior['options']
 ref=File.binread(root+(mod=='product-replacement' ? '/assets/module-two-history/reference.jpg' : '/assets/amazon-example/reference.jpg'))
 product=mod=='product-replacement' ? File.binread(root+'/assets/module-two-history/product.jpg') : nil
 plan=DirectImagePlan.prepare(ref,product,o,mock:false);raise 'mock/live body mismatch' unless prior['body']==plan['body'];DirectImagePlan.validate(plan)
 raise 'request already attempted' if File.directory?(root+'/live-attempts/generic-gc-'+plan['binding']['requestHash'])
 File.write(dir+'/'+mod+'-live-plan.json',JSON.pretty_generate(plan));File.write(dir+'/'+mod+'-live-request.json',plan['body'])
 summary<<{module:mod,model:plan['binding']['model'],requestHash:plan['binding']['requestHash'],sourceHash:plan['binding']['sourceHash'],productHash:plan['binding']['productHash'],budgetMicroUSD:plan['binding']['budgetMicroUSD'],conservativeMicroUSD:plan['binding']['conservativeMicroUSD'],maxOutputTokens:4096,retries:0,analysisCalls:0,maxRequests:1,options:o,approvalState:'not-authorized',productPixelsReused:false}
end
out={modules:summary,maxRequests:2,analysisCalls:0,postGenerationModelCalls:0,maxTotalUSD:summary.sum{|s|s[:budgetMicroUSD]}/1000000.0,reserveUSD:summary.sum{|s|s[:conservativeMicroUSD]}/1000000.0,newModelCalls:0,globalPausePresent:File.exist?(root+'/LIVE-REQUESTS-PAUSED')}
File.write(dir+'/combined-validation-plan.json',JSON.pretty_generate(out));puts JSON.pretty_generate(out)
