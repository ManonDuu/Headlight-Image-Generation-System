require 'json'
require_relative 'copy-evidence-policy'
n=0;ok=lambda{|v|raise 'assertion failed' unless v;n+=1};reject=lambda{|&f|begin;f.call;raise 'unexpected success';rescue=>e;raise if e.message=='unexpected success';n+=1;end}
source=['Made for Everyday Comfort','A gentle feel throughout your workday','Explore the details']
blocks=source.each_with_index.map{|s,i|{'id'=>i.to_s,'sourceText'=>s,'coreIntent'=>'meaning-'+i.to_s,'marketingFunction'=>i==0?'benefit':'support','meaningUnitIds'=>['unit-'+i.to_s]}}
rewrites=blocks.map{|b|{'blockId'=>b['id'],'coreIntent'=>b['coreIntent'],'marketingFunction'=>b['marketingFunction'],'preservedMeaningUnitIds'=>b['meaningUnitIds'],'usedFactIds'=>[],'omittedFactIds'=>[]}}
e={'facts'=>[],'sourceBlocks'=>blocks,'rewrites'=>rewrites};o={'mode'=>'ai-rewrite','productParameters'=>'','brandName'=>''}
text=source.map{|s|{'text'=>s}};text[2]={'text'=>'Discover the details'}
a=CopyEvidencePolicy.audit(e,o,text);ok.call(a['wholeImageLexicalDifference']&&a['meaningfulDifference']=='requires-review'&&!a['perBlockDifferenceRequired']);ok.call(a['state']=='candidate-with-warnings')
reject.call{CopyEvidencePolicy.audit(e,o,source.map{|s|{'text'=>s}})}
reject.call{CopyEvidencePolicy.audit(e,o,source.map{|s|{'text'=>s.upcase.gsub(' ',"\n")+'!'}})}
bad=Marshal.load(Marshal.dump(e));bad['rewrites'][0]['coreIntent']='unrelated-performance';ok.call(CopyEvidencePolicy.audit(bad,o,text.map{|t|{'text'=>t['text']+' changed'}})['pending'].any?{|v|v['reason'].include?('metadata differs')})
bad=Marshal.load(Marshal.dump(e));bad['rewrites'][1]['preservedMeaningUnitIds']=[];ok.call(CopyEvidencePolicy.audit(bad,o,text)['pending'].any?{|v|v['reason'].include?('metadata differs')})
ok.call(CopyEvidencePolicy.audit(nil,{'mode'=>'custom'},source.map{|s|{'text'=>s}})['state']=='custom-verbatim')
%w[linen ceramic].each do |category|
 f=Marshal.load(Marshal.dump(e));f['facts']=[{'id'=>'material','value'=>category,'origin'=>'reference','userField'=>''}];f['rewrites'][0]['usedFactIds']=['material']
 result=CopyEvidencePolicy.audit(f,o,text);ok.call(result['pending'].any?{|p|p['factId']=='material'})
 f['facts'][0].merge!('origin'=>'user','userField'=>'productParameters');reject.call{CopyEvidencePolicy.audit(f,o,text)}
 result=CopyEvidencePolicy.audit(f,o.merge('productParameters'=>category),text);ok.call(result['pending'].none?{|p|p['factId']=='material'})
end
# Matching intent metadata cannot prove that vacuous output preserves the selling point.
empty_meaning=text.map{|t|{'text'=>'Generic neutral scene'}}
ok.call(CopyEvidencePolicy.audit(e,o,empty_meaning)['state']=='candidate-with-warnings')
puts JSON.generate({checks:n,modelCalls:0,automaticSemanticTruthClaim:false,perBlockRewriteRequired:false})
