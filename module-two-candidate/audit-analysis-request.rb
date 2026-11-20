# Offline evidence export. Never creates a transport or reads credentials.
require_relative 'analysis-wire-candidate'
root=File.join(__dir__,'generic-analysis-validation-20261018')
plan=JSON.parse(File.read(File.join(root,'analysis-plan.json')))
request=plan.fetch('request')
raise 'frozen request hash mismatch' unless Digest::SHA256.hexdigest(JSON.generate(request))==plan.fetch('requestHash')
image=request.fetch('input')[1];bytes=Base64.strict_decode64(image.fetch('data'))
raise 'source binding mismatch' unless Digest::SHA256.hexdigest(bytes)==plan.fetch('binding').fetch('sourceHash')
raise 'construction mismatch' unless request==VisualAnalysis.request(bytes,plan.fetch('width'),plan.fetch('height'))
redacted=Marshal.load(Marshal.dump(request));redacted['input'][1]['data']='[REMOVED: original JPEG bytes]'
paths=[];depth=0
walk=lambda do |s,path,level|
  depth=[depth,level].max
  %w[minLength maxLength].each{|k|paths<<path+'.'+k if s.key?(k)}
  s.fetch('properties',{}).each{|k,v|walk.call(v,path+'.properties.'+k,level+1)}
  walk.call(s['items'],path+'.items',level+1) if s['items']
end
walk.call(request['response_format']['schema'],'$.response_format.schema',1)
error=JSON.parse(File.read(File.join(__dir__,'live-attempts/generic-analysis-20261018-one-call/response.raw.json')))
evidence={'endpoint'=>'https://generativelanguage.googleapis.com/v1beta/interactions','method'=>'POST',
  'requestHash'=>plan['requestHash'],'request'=>redacted,'httpStatus'=>400,'response'=>error,
  'image'=>{'sha256'=>Digest::SHA256.hexdigest(bytes),'bytes'=>bytes.bytesize,'width'=>plan['width'],'height'=>plan['height']},
  'schema'=>{'bytes'=>JSON.generate(request['response_format']['schema']).bytesize,'nodeDepth'=>depth,'unlistedStringConstraintPaths'=>paths},
  'rootCauseConfirmed'=>false,'newModelRequests'=>0,
  'sources'=>['https://ai.google.dev/api/interactions-api','https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite','https://ai.google.dev/gemini-api/docs/thinking#controlling_thinking','https://ai.google.dev/gemini-api/docs/structured-output#json_schema_support']}
File.write(File.join(root,'request-audit-redacted.json'),JSON.pretty_generate(evidence))
# Fixture tests: audit export is reversible only with the locally held original
# image, preserves the error exactly, and never exports any encoded pixels.
n=0;check=lambda{|v|raise 'audit fixture failed' unless v;n+=1}
loaded=JSON.parse(File.read(File.join(root,'request-audit-redacted.json')))
check.call(!JSON.generate(loaded).include?(image['data']))
restored=Marshal.load(Marshal.dump(loaded['request']));restored['input'][1]['data']=image['data']
check.call(restored==request)
check.call(loaded['response']=={'error'=>{'message'=>'Request contains an invalid argument.','code'=>'invalid_request'}})
check.call(loaded['request'].keys.sort==%w[generation_config input model response_format store])
check.call(loaded['request']['generation_config']=={'max_output_tokens'=>4096,'thinking_level'=>'minimal'})
candidate=AnalysisWireCandidate.prepare(request)
check.call(candidate['enabled']==false&&candidate['authorization'].nil?)
check.call(candidate['body']['input']==request['input'])
check.call(candidate['body']['generation_config']==request['generation_config'])
check.call(!JSON.generate(candidate['body']['response_format']['schema']).match?(/minLength|maxLength/))
check.call(JSON.generate(VisualAnalysis::SCHEMA).include?('minLength'))
puts "PASS #{n} redacted recorded-request/error fixture checks; zero network requests"
puts JSON.generate(evidence['schema'].reject{|k,_|k=='unlistedStringConstraintPaths'}.merge('unlistedConstraintCount'=>paths.size,'imageBytes'=>bytes.bytesize))
