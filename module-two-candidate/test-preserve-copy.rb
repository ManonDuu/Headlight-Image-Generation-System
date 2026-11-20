require_relative 'product-asset-provider'
root=__dir__;out=root+'/diagnostics/preserve-copy';FileUtils.mkdir_p(out)
old=JSON.parse(File.read(root+'/diagnostics/listing-canbus-preflight/analysis-plan-UNAUTHORIZED.json'));raw=File.read(root+'/live-attempts/listing-Sentinel_9ce2af725860819189d6a06874e32720/analysis/response.raw.json')
f=old['productFrozen'];ref=Base64.strict_decode64(DirectImagePlan.image_part(f,'reference')['data']);prod=Base64.strict_decode64(DirectImagePlan.image_part(f,'product-appearance')['data'])
opts=DefaultProductFacts.apply(f['options'].merge('mode'=>'preserve-reference','businessSpec'=>DirectImagePlan::SPEC));fresh=DirectImagePlan.prepare(ref,prod,opts);a=ProductAssetProvider.prepare(fresh);p=ProductAssetProvider.parse_analysis(a,200,raw)
raise 'CANBUS not recovered' unless p['layout']['text'].map{|t|t['text']}==["CANBUS\nREADY"]
b=ProductAssetProvider.prepare(fresh,'background',p)
File.write(out+'/analysis-plan-OFFLINE-ONLY.json',JSON.pretty_generate(a));File.write(out+'/proposal.json',JSON.pretty_generate(p));File.write(out+'/background-plan-UNAUTHORIZED.json',JSON.pretty_generate(b))
puts JSON.generate({newModelCalls:0,copy:p['layout']['text'].map{|t|t['text']},warnings:p['warnings'],backgroundHash:b['binding']['requestHash']})
