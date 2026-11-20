require_relative 'bridge-server'
c=JSON.parse(File.read(File.join(__dir__,'contracts/image-api-reviewed.json')))
n=0
check=lambda{|v,msg|raise msg unless v;n+=1}
Dir.mktmpdir('jpeg-contract-') do |dir|
 bytes=File.binread(File.join(__dir__,'assets/81gMZuoRq6L._AC_SL1500_.jpg'))
 b=Bridge.new(mock:true,data:dir)
 s=b.freeze_task({'module'=>'reference-reconstruction','mode'=>'no-copy','layoutTone'=>'keep-reference','output'=>{'aspectRatio'=>'4:5','imageSize'=>'2K'},'imageBase64'=>Base64.strict_encode64(bytes),'sourceHash'=>Digest::SHA256.hexdigest(bytes),'budgetMicroUSD'=>260000})
 req=JSON.parse(File.read(File.join(dir,s['id'],'request.json')))
 validate=lambda do |r|
  raise 'unexpected top-level fields' unless r.keys.sort==c['requestKeys'].sort
  raise 'model/privacy mismatch' unless r['model']==c['model']&&r['store']==false
  raise 'format mismatch' unless r['response_format']==c['responseFormat']
  raise 'generation config mismatch' unless r['generation_config']==c['generationConfig']
  raise 'input shape' unless r['input'].size==2&&r['input'][0].keys.sort==%w[text type]&&r['input'][0]['type']=='text'&&r['input'][1].keys.sort==c['inputImageKeys'].sort
  raise 'input mime; unsupported resolution absent' unless r['input'][1]['mime_type']==c['inputMime']&&!r['input'][1].key?('resolution')
 end
 validate.call(req);n+=1
 invalid_resolution=Marshal.load(Marshal.dump(req));invalid_resolution['input'][1]['resolution']='high'
 begin;validate.call(invalid_resolution);raise 'resolution regression';rescue=>e;check.call(e.message=='input shape','rejected model-specific field cannot return');end
 check.call(req['input'][1]['data']==Base64.strict_encode64(bytes),'original input bytes unchanged')
 check.call(req['input'][0]['text'].include?('JPEG')&&!req['input'][0]['text'].include?('PNG'),'prompt consistent with output contract')
 check.call(s['ruleTrace']['checks'].size==11&&s['ruleTrace']['inputAccounting']['conservativeMicroUSD']<=260000,'rules/budget intact')
 invalid=Marshal.load(Marshal.dump(req));invalid['response_format']['mime_type']='image/png'
 begin;validate.call(invalid);raise 'old bug not caught';rescue =>e;check.call(e.message=='format mismatch','old PNG request rejected by contract');end
 invalid=Marshal.load(Marshal.dump(req));invalid['response_format']['delivery']='uri'
 begin;validate.call(invalid);raise 'URI not caught';rescue=>e;check.call(e.message=='format mismatch','URI rejected');end
 summary={'state'=>'independent-review-applied-no-live-request','rulesVersion'=>s['ruleTrace']['version'],'requestHash'=>s['requestHash'],'promptHash'=>s['ruleTrace']['promptHash'],'sourceHash'=>s['sourceHash'],'format'=>req['response_format'],'generation_config'=>req['generation_config'],'conservativeMicroUSD'=>258560,'budgetMicroUSD'=>260000,'analysisCalls'=>0,'generationCalls'=>0,'existingLedgerPreserved'=>true}
 File.write(File.join(__dir__,'MODEL-AUDIT-CANDIDATE.json'),JSON.pretty_generate(summary))
end
puts "PASS #{n} offline request-shape checks; independent minimal-field review applied; no network."
