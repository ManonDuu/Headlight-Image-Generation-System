require_relative 'product-asset-provider'
require 'time'
r=File.expand_path(__dir__);b=r+'/live-attempts/combined-Sentinel_ca2472a9acc88191b1b3ae0beb8d149a';w=r+'/diagnostics/approved-combined-20261018';stage=ARGV.fetch(0);folder=b+'/'+stage
raise 'already processed' if File.exist?(folder+'/completed.json')
receipt=JSON.parse(File.read(folder+'/receipt.json'));raise 'transport failed; stop batch' unless receipt['curlExit']==0&&receipt['httpStatus']=='200'
plan=JSON.parse(File.read(folder+'/plan.json'));raw=File.binread(folder+'/response.raw.json');result=nil
begin
 if stage=='analysis'
  result=ProductAssetProvider.parse_analysis(plan,200,raw);File.write(w+'/proposal.json',JSON.pretty_generate(result))
  frozen=JSON.parse(File.read(r+'/diagnostics/today-real-input-readiness/product-replacement-live-plan.json'))
  background=ProductAssetProvider.prepare(frozen,'background',result);raise 'background reserve exceeds authorization' unless background['binding']['conservativeMicroUSD']<=260000
  File.write(w+'/background-plan.json',JSON.pretty_generate(background))
  usage=JSON.parse(raw)['usageMetadata'];estimate=(usage['promptTokenCount']*0.3+((usage['candidatesTokenCount']||0)+(usage['thoughtsTokenCount']||0))*2.5)/1000000.0
 else
  dims=stage=='reference' ? plan['binding']['expectedDimensions'] : plan['productFrozen']['trace']['expectedDimensions']
  result=GenerateContentAdapter.parse(200,raw,expected_dimensions:dims);bytes=result.delete('bytes');name=stage+(result['outputMime']=='image/jpeg' ? '.jpg' : '.png');File.binwrite(w+'/'+name,bytes)
  usage=result['usage'];estimate=(usage['promptTokenCount']*0.5+((usage['candidatesTokenCount']||0)+(usage['thoughtsTokenCount']||0))*60)/1000000.0
  if stage=='reference'
   p=r+'/bridge-jobs/'+receipt.fetch('task');s=JSON.parse(File.read(p+'/state.json'));raise 'normal frozen request changed' unless s['requestHash']==receipt['requestHash']&&JSON.parse(File.read(p+'/generic-gc-plan.json'))==plan
   File.binwrite(p+'/generic-request.json',plan['body']);File.binwrite(p+'/generic-response.json',raw);File.binwrite(p+'/'+result['outputFilename'],bytes)
   s.merge!(result);s.merge!('httpStatus'=>200,'finishedAt'=>Time.now.utc.iso8601,'execution'=>'scoped-approved-identical-frozen-request','approval'=>'Sentinel_ca2472a9acc88191b1b3ae0beb8d149a');File.write(p+'/state.json',JSON.pretty_generate(s));result['task']=s['id']
  else
   frozen=plan['productFrozen'];package={'sourceHash'=>frozen['binding']['sourceHash'],'productHash'=>frozen['binding']['productHash'],'options'=>frozen['options'],'background'=>{'base64'=>Base64.strict_encode64(bytes),'mime'=>result['outputMime']},'backgroundHash'=>result['outputHash'],'backgroundOrigin'=>'clean-background-only','proposal'=>plan['proposal'],'fixtureOnly'=>false,'visualAcceptance'=>'not-evaluated'}
   dest=r+'/product-asset-cache/'+frozen['binding']['requestHash'];raise 'cache already exists; preserve it' if File.exist?(dest);FileUtils.mkdir_p(dest);File.write(dest+'/package.json',JSON.pretty_generate(package));File.write(w+'/product-package.json',JSON.pretty_generate(package))
  end
 end
 record={'stage'=>stage,'state'=>'completed','requestHash'=>receipt['requestHash'],'usage'=>usage,'estimatedUSD'=>estimate,'invoiceVerified'=>false,'result'=>result}
 File.write(folder+'/completed.json',JSON.pretty_generate(record));puts JSON.generate(record.reject{|k,_|k=='result'})
rescue=>e
 File.write(folder+'/processing-failed.json',JSON.pretty_generate({state:'stopped',error:e.message,retries:0}));puts JSON.generate({state:'stopped',error:e.message});exit 1
end
