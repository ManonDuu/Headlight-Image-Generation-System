require_relative 'analysis-wire-candidate'
root=File.expand_path(__dir__);n=0;check=lambda{|v|raise 'assertion failed' unless v;n+=1}
old=JSON.parse(File.read(root+'/generic-analysis-validation-20261018/analysis-plan.json'))['request']
sha=Digest::SHA256.hexdigest(JSON.generate(old))
new_plan=AnalysisWireCandidate.prepare(old);body=new_plan['body']
check.call(Digest::SHA256.hexdigest(JSON.generate(old))==sha)
check.call(body.reject{|k,_|k=='response_format'}==old.reject{|k,_|k=='response_format'})
check.call(body['response_format'].reject{|k,_|k=='schema'}==old['response_format'].reject{|k,_|k=='schema'})
check.call(new_plan['requestHash']!=sha&&!new_plan['enabled']&&new_plan['authorization'].nil?)
check.call(!JSON.generate(body['response_format']['schema']).include?('minLength'))
check.call(JSON.generate(VisualAnalysis::SCHEMA).include?('minLength'))
source=old['input'][1]['data'];hash=Digest::SHA256.hexdigest(Base64.strict_decode64(source))
a=VisualAnalysis.mock_contract(hash,1200,1500)
['',('x'*501)].each do |invalid|
  bad=Marshal.load(Marshal.dump(a));bad['sceneChange']=invalid
  begin;VisualAnalysis.validate(bad,hash,1200,1500,allow_mock:true);raise 'length guard lost';rescue VisualAnalysis::Invalid;n+=1;end
end
bad=Marshal.load(Marshal.dump(a));bad['regions'][0]['box']=[0,0,1201,1500]
begin;VisualAnalysis.validate(bad,hash,1200,1500,allow_mock:true);raise 'coordinate guard lost';rescue VisualAnalysis::Invalid;n+=1;end
error=JSON.parse(File.read(root+'/live-attempts/generic-analysis-20261018-one-call/response.raw.json'))
%w[missing enum].each do |kind|
  bad=Marshal.load(Marshal.dump(a));kind=='missing' ? bad.delete('readingOrder') : bad['origin']='invented'
  begin;VisualAnalysis.validate(bad,hash,1200,1500,allow_mock:true);raise 'schema guard lost';rescue VisualAnalysis::Invalid;n+=1;end
end
# A business property named minLength is NOT a schema keyword at that position.
named={'type'=>'object','properties'=>{'minLength'=>{'type'=>'string','minLength'=>1,'maxLength'=>20}},'required'=>['minLength']}
projected=AnalysisWireCandidate.project(named)
check.call(projected=={'type'=>'object','properties'=>{'minLength'=>{'type'=>'string'}},'required'=>['minLength']})
removed=[];nodes=0
audit=lambda do |before,after,path|
  nodes+=1
  expected=before.dup
  if before['type']=='string'
    %w[minLength maxLength].each{|k|removed<<path+'.'+k if expected.delete(k)}
  end
  props=before['properties']||{}
  check.call((before.fetch('required',[])-props.keys).empty?) if before['type']=='object'
  check.call(before['items'].is_a?(Hash)) if before['type']=='array'
  check.call(before['enum'].all?{|x|x.is_a?(String)}) if before['enum']&&before['type']=='string'
  check.call(!before.key?('$ref')) # frozen contract has no references to resolve
  check.call(expected.reject{|k,_|%w[properties items].include?(k)}==after.reject{|k,_|%w[properties items].include?(k)})
  check.call(props.keys==after.fetch('properties',{}).keys)
  props.each{|k,v|audit.call(v,after['properties'][k],path+'.properties.'+k)}
  audit.call(before['items'],after['items'],path+'.items') if before['items']
end
audit.call(old['response_format']['schema'],body['response_format']['schema'],'$.response_format.schema')
exported=JSON.parse(File.read(root+'/generic-analysis-validation-20261018/request-audit-redacted.json'))
check.call(removed.sort==exported['schema']['unlistedStringConstraintPaths'].sort&&removed.size==32)
File.write(root+'/generic-analysis-validation-20261018/schema-projection-audit.json',JSON.pretty_generate({'removedPaths'=>removed,'schemaNodes'=>nodes,'wireBytes'=>JSON.generate(body['response_format']['schema']).bytesize,'onlyStringConstraintsRemoved'=>true,'localValidationUnchanged'=>true,'authorized'=>false}))
begin;VisualAnalysis.response(error,hash,1200,1500);raise 'HTTP error accepted as analysis';rescue VisualAnalysis::Invalid;n+=1;end
puts "PASS #{n} offline candidate/preserved local guards/recorded-error checks; zero model calls"
