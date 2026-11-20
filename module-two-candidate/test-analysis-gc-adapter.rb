require_relative 'analysis-gc-adapter'
require 'tmpdir'
n=0;check=lambda{|v,label|raise label unless v;n+=1}
reject=lambda{|&f|begin;f.call;raise 'unexpected acceptance';rescue VisualAnalysis::Invalid;n+=1;end}
original=JSON.parse(File.read(File.join(__dir__,'generic-analysis-validation-20261018/analysis-plan.json')))
plan=AnalysisGCAdapter.prepare(original);b=plan['binding'];body=JSON.parse(plan['body'])
check.call(AnalysisGCAdapter.validate(plan),'plan validates')
check.call(body.keys.sort==%w[contents generationConfig],'no Interactions top-level keys')
check.call(body['contents'][0]['parts'][0]['text']==original['request']['input'][0]['text'],'prompt unchanged')
check.call(body['contents'][0]['parts'][1]['inlineData']['data']==original['request']['input'][1]['data'],'exact original pixels')
g=body['generationConfig'];check.call(g.keys.sort==%w[candidateCount maxOutputTokens mediaResolution responseFormat thinkingConfig],'exact REST config keys')
check.call(g['responseFormat'].keys==['text']&&g['responseFormat']['text']['mimeType']=='application/json','current REST text format')
check.call(g['thinkingConfig']=={'thinkingLevel'=>'MINIMAL'}&&g['mediaResolution']=='MEDIA_RESOLUTION_HIGH','endpoint-specific enums')
check.call(g['responseFormat']['text']['schema']==AnalysisWireCandidate.project(VisualAnalysis::SCHEMA),'wire projection only')
check.call(b['generationCalls']==0&&b['retries']==0&&b['conservativeMicroUSD']<=20000,'budget purpose bounded')
%w[body binding original liveEnabled].each do |key|
 bad=Marshal.load(Marshal.dump(plan));bad[key]=key=='liveEnabled' ? true : key=='body' ? bad[key]+' ' : bad[key].merge('extra'=>'tamper')
 reject.call{AnalysisGCAdapter.validate(bad)}
end
a=VisualAnalysis.mock_contract(b['sourceHash'],b['width'],b['height'])
fixture={'modelVersion'=>AnalysisGCAdapter::MODEL,'candidates'=>[{'finishReason'=>'STOP','content'=>{'parts'=>[{'text'=>JSON.generate(a)}]}}],
 'usageMetadata'=>{'promptTokenCount'=>100,'candidatesTokenCount'=>200,'thoughtsTokenCount'=>0,'totalTokenCount'=>300}}
valid=JSON.generate(fixture);result=AnalysisGCAdapter.parse(200,valid,b,allow_mock:true)
check.call(result['state']=='analysis-ready'&&!result['automaticGeneration'],'strict valid mock')
reject.call{AnalysisGCAdapter.parse(200,valid,b)}
reject.call{AnalysisGCAdapter.parse(400,'{"error":{"message":"invalid"}}',b)}
reject.call{AnalysisGCAdapter.parse(200,'',b)}
%w[missing empty long enum coordinates blocking hash].each do |kind|
 bad=Marshal.load(Marshal.dump(a))
 case kind
 when 'missing';bad.delete('readingOrder')
 when 'empty';bad['sceneChange']=''
 when 'long';bad['sceneChange']='a'*501
 when 'enum';bad['origin']='invented'
 when 'coordinates';bad['regions'][0]['box']=[0,0,99999,1500]
 when 'blocking';bad['uncertainties'][0]['severity']='blocking'
 when 'hash';bad['sourceHash']='f'*64
 end
 r=Marshal.load(Marshal.dump(fixture));r['candidates'][0]['content']['parts'][0]['text']=JSON.generate(bad)
 reject.call{AnalysisGCAdapter.parse(200,JSON.generate(r),b,allow_mock:true)}
end
%w[model multiple finish image missingusage overinput overoutput totals unknownthought].each do |kind|
 r=Marshal.load(Marshal.dump(fixture))
 case kind
 when 'model';r['modelVersion']='gemini-3.1-flash-image'
 when 'multiple';r['candidates']<<r['candidates'][0]
 when 'finish';r['candidates'][0]['finishReason']='MAX_TOKENS'
 when 'image';r['candidates'][0]['content']['parts']<<{'inlineData'=>{'mimeType'=>'image/png','data'=>'bad'}}
 when 'missingusage';r.delete('usageMetadata')
 when 'overinput';r['usageMetadata']['promptTokenCount']=16385;r['usageMetadata']['totalTokenCount']=16585
 when 'overoutput';r['usageMetadata']['candidatesTokenCount']=4097;r['usageMetadata']['totalTokenCount']=4197
 when 'totals';r['usageMetadata']['totalTokenCount']=0
 when 'unknownthought';r['usageMetadata'].delete('thoughtsTokenCount');r['usageMetadata']['totalTokenCount']=301
 end
 reject.call{AnalysisGCAdapter.parse(200,JSON.generate(r),b,allow_mock:true)}
end
Dir.mktmpdir('analysis-gc-') do |dir|
 calls=0;transport=lambda{|endpoint,raw,options|calls+=1;raise unless endpoint==AnalysisGCAdapter::ENDPOINT&&raw==plan['body']&&options=={retries:0,timeoutSeconds:120};[200,valid]}
 reject.call{AnalysisGCAdapter.execute(plan,dir,approval:b,transport:transport)}
 check.call(calls==0&&Dir.children(dir).empty?,'no authority no reservation')
 r=AnalysisGCAdapter.execute(plan,dir,approval:b,transport:transport,mock:true);check.call(r['state']=='analysis-ready'&&calls==1,'one transport')
 reject.call{AnalysisGCAdapter.execute(plan,dir,approval:b,transport:transport,mock:true)}
 check.call(calls==1,'no replay')
 failed=File.join(dir,'failed');r=AnalysisGCAdapter.execute(plan,failed,approval:b,transport:lambda{|*_|[400,'{"error":{"message":"invalid"}}']},mock:true)
 check.call(r['state']=='stopped'&&r['generationCalls']==0,'failure terminal')
 reject.call{AnalysisGCAdapter.execute(plan,failed,approval:b,transport:transport,mock:true)}
end
out=File.join(__dir__,'analysis-gc-validation-20261018');FileUtils.mkdir_p(out)
File.write(File.join(out,'plan.json'),JSON.pretty_generate(plan))
redacted=Marshal.load(Marshal.dump(body));redacted['contents'][0]['parts'][1]['inlineData']['data']='[REMOVED: unchanged original JPEG]'
File.write(File.join(out,'request-redacted.json'),JSON.pretty_generate({'binding'=>b,'request'=>redacted,'liveEnabled'=>false,'tests'=>n}))
File.write(File.join(out,'response-mock.json'),JSON.pretty_generate(fixture))
puts JSON.generate({'checks'=>n,'state'=>'passed','requestHash'=>b['requestHash'],'budgetMicroUSD'=>b['budgetMicroUSD'],'newModelRequests'=>0})
