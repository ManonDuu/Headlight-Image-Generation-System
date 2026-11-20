require_relative 'product-asset-provider'
step=Integer(ARGV.fetch(0));root=File.join(__dir__,'diagnostics/two-backgrounds-20261018');ledger=File.join(__dir__,'live-attempts/two-backgrounds-20261018-153414');p=JSON.parse(File.read(root+"/step#{step}-plan.json"));receipt=JSON.parse(File.read(ledger+"/step#{step}/receipt.json"));raise 'transport failed' unless receipt['curlExit']==0&&receipt['httpStatus']=='200'
begin
 parsed=GenerateContentAdapter.parse(200,File.read(ledger+"/step#{step}/response.raw.json"),expected_dimensions:[1856,2304],input_token_reserve:25600)
 f=step==1 ? p['frozen'] : p['productFrozen'];proposal=step==1 ? {'layout'=>p['layout']} : p['proposal']
 folder=File.join(__dir__,'product-asset-cache',f['binding']['requestHash']);raise 'existing cache protected' if File.exist?(folder);FileUtils.mkdir_p(folder)
 pack={'sourceHash'=>f['binding']['sourceHash'],'productHash'=>f['binding']['productHash'],'options'=>f['options'],'background'=>{'base64'=>Base64.strict_encode64(parsed['bytes']),'mime'=>parsed['outputMime']},'backgroundHash'=>parsed['outputHash'],'backgroundOrigin'=>'clean-background-only','proposal'=>proposal,'fixtureOnly'=>false,'visualAcceptance'=>'not-evaluated','authorizationID'=>'two-backgrounds-20261018-153414','backgroundRequestHash'=>p['binding']['requestHash']}
 File.write(folder+'/package.json',JSON.pretty_generate(pack));ProductAssetProvider.cache(f,File.join(__dir__,'product-asset-cache'))
 ext=parsed['outputMime']=='image/jpeg' ? 'jpg' : 'png';File.binwrite(root+"/step#{step}-background.#{ext}",parsed['bytes'])
 File.write(root+"/step#{step}-parsed.json",JSON.pretty_generate(parsed.reject{|k,_|k=='bytes'}.merge('cachePath'=>folder,'frozenHash'=>f['binding']['requestHash'])))
 puts JSON.generate({step:step,parsed:true,usage:parsed['usage'],backgroundPath:root+"/step#{step}-background.#{ext}",cachePath:folder})
rescue=>e
 File.write(ledger+'/STOP.json',JSON.pretty_generate({reason:e.message,step:step,remainingCancelled:true}));raise
end
