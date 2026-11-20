require_relative 'reference-provider'
require 'tmpdir';require 'fileutils'
f=JSON.parse(File.read('diagnostics/final-live-20261018/step1-plan.json'))['frozen'];layout=JSON.parse(File.read('diagnostics/final-live-20261018/step1-parsed.json'))['plan'];good=ReferenceAnchorReview.require!(f['binding']['sourceHash'],layout);checks=[]
ok=lambda{|v,m|raise m unless v;checks<<m};reject=lambda{|m,&block|begin;block.call;raise 'unexpected pass';rescue=>e;raise if e.message=='unexpected pass';checks<<m;end}
p=ReferenceProvider.prepare(f,'background',layout);ok.call(p['layout']==good['nativeLayout']&&p['layout']!=layout,'background uses reviewed native layout, not rejected model coordinates')
ok.call(!JSON.parse(p['body'])['contents'][0]['parts'][0]['text'].include?('sourceBox'),'unverified model sourceBoxes excluded from background prompt')
ok.call(p['binding']['retries']==0&&p['binding']['maxRequests']==1,'existing no-retry request bound unchanged; plan only')
File.write('diagnostics/keep-reference-gate/next-background-OFFLINE-ONLY.json',JSON.pretty_generate(p))
Dir.mktmpdir('anchor-gate-') do |tmp|
 ReferenceAnchorReview.send(:remove_const,:ROOT);ReferenceAnchorReview.const_set(:ROOT,tmp)
 folder=File.join(tmp,good['sourceHash']);FileUtils.mkdir_p(folder);path=File.join(folder,good['layoutHash']+'.json')
 reject.call('missing audit blocks'){ReferenceAnchorReview.require!(good['sourceHash'],layout)}
 cases={'OCR misread'=>lambda{|a|a['sourceBlocks'][0]['matches']=0},'duplicate match'=>lambda{|a|a['sourceBlocks'][0]['matches']=2},'missing block'=>lambda{|a|a['sourceBlocks'].pop},'unresolved semantics'=>lambda{|a|a['semanticReview']='uncertain'},'unresolved role'=>lambda{|a|a['renderAnchors'][0]['semanticState']='uncertain'},'changed glyph state'=>lambda{|a|a['renderAnchors'][0]['glyphState']='uncertain'},'changed reference hash'=>lambda{|a|a['sourceHash']='0'*64}}
 cases.each{|name,change|v=Marshal.load(Marshal.dump(good));change.call(v);File.write(path,JSON.generate(v));reject.call(name+' blocks'){ReferenceAnchorReview.require!(good['sourceHash'],layout)}}
 File.write(path,JSON.generate(good));changed=Marshal.load(Marshal.dump(layout));changed['text'][0]['text']='Different';reject.call('copy/layout change requires separate review'){ReferenceAnchorReview.require!(good['sourceHash'],changed)}
 %w[diagnostics/preserve-copy/proposal.json diagnostics/preflight-wire-20261018/candidate-policy-replay.json].each{|name|v=JSON.parse(File.read(name));l=v['layout']||v['plan'];reject.call('unreviewed historical layout blocks: '+name){ReferenceAnchorReview.require!('0'*64,l)}}
end
File.write('diagnostics/keep-reference-gate/gate-regression.json',JSON.pretty_generate({checks:checks,modelCalls:0}));puts JSON.generate({checks:checks.size,modelCalls:0})
