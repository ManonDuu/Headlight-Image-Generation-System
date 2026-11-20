require_relative 'analysis-gc-enum-candidate'
root=File.join(__dir__,'analysis-gc-validation-20261018')
original=JSON.parse(File.read(File.join(__dir__,'generic-analysis-validation-20261018/analysis-plan.json')))
plan=AnalysisGCEnumCandidate.prepare(original);body=JSON.parse(plan['body']);n=1
old=JSON.parse(AnalysisGCAdapter.prepare(original)['body'])
undo=Marshal.load(Marshal.dump(body));undo['generationConfig']['responseFormat']['text']['mimeType']='application/json'
raise 'more than MIME value changed' unless undo==old;n+=1
cases=[
 [%w[generationConfig responseFormat text mimeType],'application/json'],
 [%w[generationConfig responseFormat text mimeType],'application_json'],
 [%w[generationConfig responseFormat text mimeType],'TEXT_PLAIN'],
 [%w[generationConfig thinkingConfig thinkingLevel],'minimal'],
 [%w[generationConfig mediaResolution],'high'],
 [%w[generationConfig mediaResolution],{'level'=>'MEDIA_RESOLUTION_HIGH'}],
 [%w[generationConfig candidateCount],'1'],
 [%w[generationConfig maxOutputTokens],4096.0],
 [%w[generationConfig responseFormat text schema],{'type'=>'OBJECT'}],
 [%w[generationConfig responseMimeType],'application/json']]
cases.each do |path,value|
 bad=Marshal.load(Marshal.dump(body));target=path[0...-1].inject(bad){|h,k|h[k]};target[path[-1]]=value
 begin;AnalysisGCEnumCandidate.contract(bad);raise 'accepted wrong type or enum';rescue VisualAnalysis::Invalid;n+=1;end
end
%w[store input response_format generation_config thinking_level background previous_interaction_id].each do |key|
 bad=Marshal.load(Marshal.dump(body));bad[key]=false
 begin;AnalysisGCEnumCandidate.contract(bad);raise 'accepted foreign top-level field';rescue VisualAnalysis::Invalid;n+=1;end
end
%w[IMAGE_JPEG APPLICATION_JSON].each do |v|
 bad=Marshal.load(Marshal.dump(body));bad['contents'][0]['parts'][1]['inlineData']['mimeType']=v
 begin;AnalysisGCEnumCandidate.contract(bad);raise 'accepted enum in Blob';rescue VisualAnalysis::Invalid;n+=1;end
end
redacted=Marshal.load(Marshal.dump(body));redacted['contents'][0]['parts'][1]['inlineData']['data']='[REMOVED: frozen original JPEG]'
File.write(File.join(root,'enum-candidate-request-redacted.json'),JSON.pretty_generate({'binding'=>plan['binding'],'request'=>redacted,'authorized'=>false,'liveEnabled'=>false,'checks'=>n}))
puts JSON.generate({checks:n,state:'passed',changedFields:1,requestHash:plan['binding']['requestHash'],modelCalls:0})
