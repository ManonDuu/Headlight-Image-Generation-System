require_relative 'reference-provider'
require 'json'
n=0;ok=lambda{|v,m|raise m unless v;n+=1}
p=JSON.parse(File.read(__dir__+'/diagnostics/preflight-wire-20261018/analysis-plan.json'));v=JSON.parse(File.read(__dir__+'/diagnostics/preflight-wire-20261018/real-proposal-unaccepted.json'));o=p['frozen']['options'];run=lambda{|value|AnalysisOutputContract.process(value,o,[1200,1500],[1856,2304])}
a=run.call(v);t=a['candidate']['text'];ok.call(a['state']=='candidate-with-warnings','valid source geometry permits local candidate')
ok.call(t.map{|x|x['text']}==['Obvious Upgraded Brightness','Make a Huge Difference From Halogen','LED Light','Halogen Light'],'keep source meaning/labels while removing brand and number')
ok.call(!a['automaticSemanticAcceptance'],'candidate is not automatic acceptance')
ok.call(!a['pending'].any?{|x|x['code']=='NATURAL_REWRITE_MISSING'},'whole-image omission satisfies difference without per-title change')
%w[HEADLIGHTS 9999% OtherBrand].each do |word|
 bad=Marshal.load(Marshal.dump(v));bad['text'][0]['text']=word;bad['text'][0]['role']='brand' if word=='OtherBrand';out=run.call(bad)
 ok.call(out['candidate']['text'].none?{|x|x['text']==word},'hard copy rule excludes '+word)
end
bad=Marshal.load(Marshal.dump(v));bad['sourceGeometry'].delete('coordinateSpace');ok.call(run.call(bad)['state']=='awaiting-contract-review','unknown coordinates cannot be invented')
bad=Marshal.load(Marshal.dump(v));bad['evidence']['sourceBlocks'][0]['sourceBox']['x']=2000;ok.call(run.call(bad)['state']=='awaiting-contract-review','out of bounds remains hard blocker')
bad=Marshal.load(Marshal.dump(v));bad['text'][0]['text']='9999%';out=run.call(bad);ok.call(out['removed'][0]['sourceBlockId']=='b1','audit refers to correct source block')
# No original category suffix means no authority to retain a fabricated label.
bad=Marshal.load(Marshal.dump(v));bad['evidence']['sourceBlocks'][3]['sourceText']='OriginalBrand';out=run.call(bad);ok.call(out['candidate']['text'].none?{|x|x['text'].include?('Novsight')},'new brand never promoted to safe label')
raw=File.read(__dir__+'/live-attempts/rule-analysis-Sentinel_4bf47119390c8191b1204614b725fcd1/response.raw.json');parsed=ReferenceProvider.parse(p,200,raw);ok.call(parsed['semanticAudit']['state']=='candidate-with-warnings'&&parsed['plan']['text'].length==4,'actual parser exposes usable local plan with warnings')
puts JSON.generate({checks:n,newModelCalls:0,hardRulesPreserved:true,wholeImageReview:true})
