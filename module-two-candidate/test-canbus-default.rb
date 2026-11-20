require_relative 'product-asset-provider'
root=__dir__;out=root+'/diagnostics/canbus-default';FileUtils.mkdir_p(out)
old=JSON.parse(File.read(root+'/diagnostics/listing-canbus-preflight/analysis-plan-UNAUTHORIZED.json'));raw=File.read(root+'/live-attempts/listing-Sentinel_9ce2af725860819189d6a06874e32720/analysis/response.raw.json')
f=old['productFrozen'];ref=Base64.strict_decode64(DirectImagePlan.image_part(f,'reference')['data']);prod=Base64.strict_decode64(DirectImagePlan.image_part(f,'product-appearance')['data'])
opts=DefaultProductFacts.apply(f['options'].merge('businessSpec'=>DirectImagePlan::SPEC));fresh=DirectImagePlan.prepare(ref,prod,opts);a=ProductAssetProvider.prepare(fresh);p=ProductAssetProvider.parse_analysis(a,200,raw)
raise 'CANBUS not recovered' unless p['layout']['text'].map{|t|t['text']}==['CANBUS Ready']
b=ProductAssetProvider.prepare(fresh,'background',p)
File.write(out+'/analysis-plan-OFFLINE-ONLY.json',JSON.pretty_generate(a));File.write(out+'/proposal.json',JSON.pretty_generate(p));File.write(out+'/background-plan-UNAUTHORIZED.json',JSON.pretty_generate(b))
%w[reference-reconstruction product-replacement].each{|mod|raise unless DefaultProductFacts.apply({'mode'=>'ai-rewrite','module'=>mod})['productParameters']=='CANBUS READY'}
['no CANBUS','不支持CANBUS','CANBUS disabled'].each{|negative|o=DefaultProductFacts.apply(opts.merge('productParameters'=>negative));raise if DefaultProductFacts.canbus_ready?(o);z=DirectImagePlan.prepare(ref,prod,o);q=ProductAssetProvider.parse_analysis(ProductAssetProvider.prepare(z),200,raw);raise unless q['layout']['text'].empty?}
custom=DefaultProductFacts.apply(opts.merge('mode'=>'custom','customCopy'=>'My exact text 99%'));raise unless custom['customCopy']=='My exact text 99%'
raise if DefaultProductFacts.apply({'mode'=>'remove-all-copy'}).key?('productParameters')
prompt=JSON.parse(b['body'])['contents'][0]['parts'][0]['text'];raise if prompt.match?(/99%|NEW GENERATION|Ensure Models Compatibility/)
puts JSON.generate({checks:9,newModelCalls:0,copy:p['layout']['text'].map{|t|t['text']},backgroundHash:b['binding']['requestHash']})
