require_relative 'reference-provider'
require 'json';require 'digest';require 'tmpdir';require 'fileutils'
n=0;ok=lambda{|v,m|raise m unless v;n+=1}
d=File.join(__dir__,'diagnostics/rule-analysis-authorized-20261018')
raw_path=File.join(__dir__,'live-attempts/rule-analysis-Sentinel_e054f7f47f08819180f5dca59fd8ff5c/response.raw.json');before=Digest::SHA256.file(raw_path).hexdigest
p=JSON.parse(File.read(d+'/plan.json'));raw=File.read(raw_path)
r=ReferenceProvider.parse(p,200,raw);a=r.fetch('contractAudit')
ok.call(r['compositionAllowed']==false&&a['state']=='awaiting-contract-review','real cache replay cannot invent missing facts or coordinates')
ok.call(a['candidate']['text'].all?{|t|AnalysisOutputContract::ROLES.include?(t['role'])},'general role aliases recovered without semantic relabeling')
ok.call(a['changes'].count{|x|x['field']=='fact.origin'}==6,'source origin safely means untrusted reference')
ok.call(a['removed'].any?{|x|x['reasons'].include?('UNCONFIRMED_NUMERIC_TEXT')},'actual unconfirmed numeric claim suppressed')
ok.call(a['candidate']['text'].none?{|t|t['text'].match?(/novsight/i)},'actual unconfirmed brand block suppressed')
ok.call(a['candidate']['text'][0]['text']=='Obvious Upgraded Brightness','eligible title meaning not replaced by neutral labels')
ok.call(a['pending'].count{|x|x['code']=='SOURCE_BOX_OUTSIDE_IMAGE'}==5,'out-of-source boxes not cropped/scaled')
ok.call(!a['pending'].any?{|x|x['code']=='NATURAL_REWRITE_MISSING'},'safe omissions make the whole copy different; no per-title rewrite required')
ok.call(!a['coordinateEvidenceVerified'],'old missing coordinate units not invented')
# Other domains and values, no sample-specific blacklist.
%w[QuietFabric GardenCeramics].each do |brand|
 value={'text'=>[{'text'=>'Gentle Daily Comfort','role'=>'title'},{'text'=>brand,'role'=>'brand'},{'text'=>'240%','role'=>'badge'},{'text'=>'Details','role'=>'label'}],'sourceGeometry'=>{'width'=>800,'height'=>600,'coordinateSpace'=>'normalized-0-1'},'evidence'=>{'facts'=>[],'sourceBlocks'=>[{'id'=>'a','sourceText'=>'Everyday Comfort','sourceBox'=>{'x'=>0.1,'y'=>0.1,'width'=>0.5,'height'=>0.1}}],'rewrites'=>[]}}
 out=AnalysisOutputContract.process(value,{'mode'=>'ai-rewrite'},[800,600],[1600,1200]);ok.call(out['candidate']['evidence']['sourceBlocks'][0]['sourceBox']=={'x'=>80.0,'y'=>60.0,'width'=>400.0,'height'=>60.0},'explicit normalized units convert deterministically')
 ok.call(out['candidate']['text'].map{|t|t['text']}==['Gentle Daily Comfort','Details'],'generic brand/numeric filtering retains qualitative selling point and label')
 ok.call(value['text'].length==4,'input evidence never mutated')
 value['sourceGeometry'].delete('coordinateSpace');out=AnalysisOutputContract.process(value,{'mode'=>'ai-rewrite'},[800,600],[1600,1200]);ok.call(out['candidate']['evidence']['sourceBlocks'][0]['sourceBox']['x']==0.1&&!out['coordinateEvidenceVerified'],'no guessing normalized units')
 value['text'][0]['text']='HEADLIGHTS';out=AnalysisOutputContract.process(value,{'mode'=>'ai-rewrite'},[800,600],[1600,1200]);ok.call(out['candidate']['text'].none?{|t|t['text'].match?(/headlights?/i)},'forbidden wording cannot reach renderer')
end
# Omission is expressible without demanding preservation of an unsupported claim.
e={'facts'=>[],'sourceBlocks'=>[{'id'=>'a','sourceText'=>'Soft Comfort','coreIntent'=>'comfort','marketingFunction'=>'title','meaningUnitIds'=>['comfort']},{'id'=>'b','sourceText'=>'240%','coreIntent'=>'numeric claim','marketingFunction'=>'badge','meaningUnitIds'=>['number']}],'rewrites'=>[{'blockId'=>'a','action'=>'render','renderIndex'=>0,'coreIntent'=>'comfort','marketingFunction'=>'title','preservedMeaningUnitIds'=>['comfort'],'usedFactIds'=>[],'omittedFactIds'=>[]},{'blockId'=>'b','action'=>'omit','renderIndex'=>-1,'omissionReason'=>'unconfirmed numeric claim','usedFactIds'=>[]}]}
ok.call(CopyEvidencePolicy.audit(e,{'mode'=>'ai-rewrite'},[{'text'=>'Gentle Comfort'}])['state']=='candidate-with-warnings','unsupported claim can be omitted while eligible intent remains reviewed')
reject=lambda{|&block|begin;block.call;raise 'unexpected pass';rescue=>error;raise if error.message=='unexpected pass';n+=1;end}
reject.call{AnalysisOutputContract.validate_render!([{'text'=>'Unapproved Brand','role'=>'brand'}],{'mode'=>'ai-rewrite','brandName'=>'Allowed Brand'})}
reject.call{AnalysisOutputContract.validate_render!([{'text'=>'240%','role'=>'body'}],{'mode'=>'ai-rewrite'})}
ok.call(AnalysisOutputContract.validate_render!([{'text'=>'240%','role'=>'body'}],{'mode'=>'ai-rewrite','productParameters'=>'240%'}),'confirmed numeric text permitted')
ok.call(AnalysisOutputContract.validate_render!([{'text'=>'MiXeD 240%','role'=>'title'}],{'mode'=>'custom'}),'custom explicit text remains unchanged')
new_plan=ReferenceProvider.prepare(p['frozen'],'layout-copy');body=JSON.parse(new_plan['body']);prompt=body['contents'][0]['parts'][0]['text'];schema=body['generationConfig']['responseFormat']['text']['schema']
ok.call(prompt.include?('SOURCE IMAGE: 1200x1500')&&prompt.include?('OUTPUT CANVAS: 1856x2304'),'actual two spaces explicitly bound in request')
ok.call(schema['properties']['text']['items']['properties']['role']['enum']==%w[title subtitle body brand],'role enum matches runtime')
ok.call(schema['properties']['evidence']['properties']['facts']['items']['properties']['origin']['enum']==%w[reference user],'origin enum matches runtime')
ok.call(prompt.include?('FINAL eligible copy')&&prompt.include?('action render or omit'),'source evidence/final copy and omissions distinguished')
ok.call(Digest::SHA256.file(raw_path).hexdigest==before,'real failure immutable')
replay=nil;stages=[]
Dir.mktmpdir('cached-analysis-replay-') do |dir|
 replay=ReferenceProvider.propose(p['frozen'],dir,approval_for:lambda{|b|b},transport_for:lambda{|stage|stages<<stage;lambda{|*_|[200,raw]}},mock:true)
 ok.call(replay['state']=='awaiting-contract-review'&&replay['backgroundCalls']==0&&stages==['layout-copy'],'normal orchestration replays same cached response and never starts background')
end
report={'normalChainReplay'=>{'state'=>replay['state'],'stages'=>stages,'backgroundCalls'=>0,'cachedResponseOnly'=>true},'checks'=>n,'modelCalls'=>0,'actualCacheReplay'=>r,'newContractVersion'=>ReferenceProvider::VERSION,'realNewContractVerified'=>false}
File.write(File.join(__dir__,'diagnostics/analysis-output-contract-replay.json'),JSON.pretty_generate(report));puts JSON.generate(report.reject{|k,_|k=='actualCacheReplay'})

real=JSON.parse(File.read(File.join(__dir__,'live-attempts/final-Sentinel_85f1da0431d88191a37ee902531645d3/step1/response.raw.json')))
value=JSON.parse(real['candidates'][0]['content']['parts'].find{|p|p['text']&&!p['thought']}['text'])
f=JSON.parse(File.read(File.join(__dir__,'diagnostics/final-live-20261018/step1-plan.json')))
audit=AnalysisOutputContract.process(value,f['frozen']['options'],[1122,1402],[1856,2304])
raise 'false source localization acceptance' unless audit['coordinateUnitsAndBoundsVerified']&&!audit['coordinateEvidenceVerified']&&!audit['sourceLocalizationVerified']
puts 'PASS real response: bounds/unit validity is not source localization proof; no model calls'
