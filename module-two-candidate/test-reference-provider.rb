require_relative 'bridge-server'
require 'tmpdir'
n=0;check=lambda{|v,m|raise m unless v;n+=1};reject=lambda{|&f|begin;f.call;raise 'unexpected success';rescue=>e;raise if e.message=='unexpected success';n+=1;end}
source=File.binread(File.join(__dir__,'fixtures/small-valid.jpg'))
options={'businessSpec'=>DirectImagePlan::SPEC,'module'=>'reference-reconstruction','mode'=>'custom','customCopy'=>'Exact LED H11','layoutMode'=>'auto-layout','layoutTone'=>'keep-reference','output'=>{'aspectRatio'=>'4:5','imageSize'=>'2K'}}
frozen=DirectImagePlan.prepare(source,nil,options,mock:true);p=ReferenceProvider.prepare(frozen,'layout-copy');b=p['binding'];body=JSON.parse(p['body'])
check.call(b['budgetMicroUSD']==20000&&b['maxRequests']==1&&b['retries']==0,'analysis budget/retry');check.call(body.dig('generationConfig','responseFormat','text','mimeType')=='APPLICATION_JSON','official REST enum shape')
check.call(body.dig('generationConfig','maxOutputTokens')==4096,'output limit');check.call(b['sourceHash']==Digest::SHA256.hexdigest(source),'source bound')
layout={'layoutVersion'=>ReferenceProvider::LAYOUT_VERSION,'text'=>[{'text'=>'Exact LED H11','role'=>'title','fontSize'=>30,'weight'=>600,'style'=>'normal','lineHeightPx'=>40,'align'=>'left','color'=>'#ffffff','box'=>{'x'=>50,'y'=>50,'width'=>900,'height'=>80}}]}
response={'modelVersion'=>ReferenceProvider::ANALYSIS_MODEL,'candidates'=>[{'finishReason'=>'STOP','content'=>{'parts'=>[{'text'=>JSON.generate(layout)}]}}],'usageMetadata'=>{'promptTokenCount'=>10,'candidatesTokenCount'=>10,'totalTokenCount'=>20}}
parsed=ReferenceProvider.parse(p,200,JSON.generate(response));check.call(parsed['plan']['text'][0]['mode']=='custom','mode adapted');second=ReferenceProvider.prepare(frozen,'background',parsed['plan']);check.call(second['binding']['budgetMicroUSD']==260000&&second['binding']['layoutHash']==ReferenceProvider.hash(parsed['plan']),'dependent background bound')
check.call(second['binding']['model']=='gemini-3.1-flash-image','fixed image model')
reject.call{ReferenceProvider.parse(p,400,'{"error":{"message":"User location is not supported for the API use."}}')}
reject.call{ReferenceProvider.parse(p,200,'invalid json')}
bad=Marshal.load(Marshal.dump(response));bad['candidates'][0]['finishReason']='MAX_TOKENS';reject.call{ReferenceProvider.parse(p,200,JSON.generate(bad))}
bad=Marshal.load(Marshal.dump(layout));bad['text'][0]['text']='Changed';reject.call{ReferenceProvider.layout(bad,frozen)}
bad=Marshal.load(Marshal.dump(layout));bad['text'][0]['box']['x']=99999;reject.call{ReferenceProvider.layout(bad,frozen)}
bad=Marshal.load(Marshal.dump(response));bad['usageMetadata']['promptTokenCount']=99999;reject.call{ReferenceProvider.parse(p,200,JSON.generate(bad))}
Dir.mktmpdir('provider-tests-') do |dir|
 calls=0;transport=lambda{|*args|calls+=1;[200,JSON.generate(response)]}
 reject.call{ReferenceProvider.execute(p,dir,approval:b.merge('budgetMicroUSD'=>1),transport:transport,mock:true)}
 reject.call{ReferenceProvider.execute(p,dir,approval:b,transport:transport,mock:false,authorized_once:true)}
 check.call(calls==0,'pause/approval rejected before dispatch')
 a=ReferenceProvider.execute(p,dir,approval:b,transport:transport,mock:true);cached=ReferenceProvider.execute(p,dir,approval:b,transport:transport,mock:true);check.call(a['state']=='provider-proposal'&&cached['cacheHit']&&calls==1,'successful cache no repeat')
 failure_calls=0;failroot=dir+'/failed';stop=ReferenceProvider.propose(frozen,failroot,approval_for:lambda{|v|v},transport_for:lambda{|stage|lambda{|*_|failure_calls+=1;[400,'{"error":"location unsupported"}']}},mock:true)
 check.call(stop['state']=='stopped'&&stop['failedStage']=='layout-copy'&&failure_calls==1,'400 stops before image generation')
 ReferenceProvider.propose(frozen,failroot,approval_for:lambda{|v|v},transport_for:lambda{|stage|lambda{|*_|failure_calls+=1;raise 'must not dispatch'}},mock:true);check.call(failure_calls==1,'failed attempt cached no retry')
 unfinished=dir+'/unfinished';FileUtils.mkdir_p(File.join(unfinished,'mock-reference-assets',b['requestHash']));reject.call{ReferenceProvider.execute(p,unfinished,approval:b,transport:transport,mock:true)}
 result=File.join(dir,'mock-reference-assets',b['requestHash'],'result.json');File.write(result,'{}');reject.call{ReferenceProvider.execute(p,dir,approval:b,transport:transport,mock:true)}
end
# Exercise the actual AI proposal orchestration using an in-memory transport only.
ai_options=options.merge('mode'=>'ai-rewrite');ai_options.delete('customCopy')
ai_frozen=DirectImagePlan.prepare(source,nil,ai_options,mock:true)
ai_layout=Marshal.load(Marshal.dump(layout));ai_layout['text'][0]['text']='Enjoy Everyday Comfort'
ai_layout['evidence']={'facts'=>[],'sourceBlocks'=>[{'id'=>'benefit','sourceText'=>'Discover Everyday Comfort','coreIntent'=>'comfort','marketingFunction'=>'benefit','meaningUnitIds'=>['comfort']}],'rewrites'=>[{'blockId'=>'benefit','coreIntent'=>'comfort','marketingFunction'=>'benefit','preservedMeaningUnitIds'=>['comfort'],'usedFactIds'=>[],'omittedFactIds'=>[]}]}
ai_layout['sourceGeometry']={'width'=>InputImage.inspect(source)['dimensions'][0],'height'=>InputImage.inspect(source)['dimensions'][1],'coordinateSpace'=>'source-pixels'}
ai_layout['evidence']['sourceBlocks'][0]['sourceBox']={'x'=>0,'y'=>0,'width'=>1,'height'=>1}
ai_response=Marshal.load(Marshal.dump(response));ai_response['candidates'][0]['content']['parts'][0]['text']=JSON.generate(ai_layout)
Dir.mktmpdir('ai-copy-review-') do |dir|
 stages=[]
 result=ReferenceProvider.propose(ai_frozen,dir,approval_for:lambda{|b|b},transport_for:lambda{|stage|stages<<stage;lambda{|*_|[200,JSON.generate(ai_response)]}},mock:true)
 check.call(result['state']=='awaiting-meaning-review'&&stages==['layout-copy']&&result['backgroundCalls']==0,'AI semantic uncertainty stops before background transport')
 prompt=JSON.parse(ReferenceProvider.prepare(ai_frozen,'layout-copy')['body'])['contents'][0]['parts'][0]['text']
 check.call(prompt.include?('required brand/parameter removal counts as whole-image difference')&&!prompt.include?('remove every overlay product specification and performance claim, numeric or qualitative'),'serialized prompt has no destructive legacy copy conflict')
end
out={checks:n,newModelCalls:0,livePauseVerified:true,old400Resolved:false,protocolVerifiedLive:false,analysisBudgetMicroUSD:20000,backgroundBudgetMicroUSD:260000,maxRequests:2,retries:0}
File.write(File.join(__dir__,'diagnostics/reference-provider-test.json'),JSON.pretty_generate(out));puts JSON.pretty_generate(out)
