# Offline artifact construction only; consumes reviewed local glyph composition.
require_relative 'product-asset-provider'
f=JSON.parse(File.read('diagnostics/final-live-20261018/step3-plan.json'))['productFrozen'];proposal=JSON.parse(File.read('diagnostics/preserve-copy/proposal.json'));layout=proposal['layout'];audit=ReferenceAnchorReview.require!(f['binding']['sourceHash'],layout)
m=JSON.parse(File.read('diagnostics/final-readiness/transparent-output/automatic-manifest.json'));raise 'copy/source mismatch' unless m['sourceHash']==audit['sourceHash']&&m['preparedLayout']['text'].map{|t|t['text']}==layout['text'].map{|t|t['text']}&&m['selectedOptions']['layoutMode']=='keep-reference'
w,h=f['trace']['expectedDimensions'];k=[w.to_f/m['width'],h.to_f/m['height']].min;dx=(w-m['width']*k)/2;dy=(h-m['height']*k)/2
native=Marshal.load(Marshal.dump(m['preparedLayout']));native['text'].each do |t|
 t.delete('mode');t['fontSize']*=k;t['lineHeightPx']*=k;b=t['box'];b['x']=dx+b['x']*k;b['y']=dy+b['y']*k;b['width']*=k;b['height']*=k
end
native=ReferenceProvider.layout(native,f);audit.merge!('nativeLayout'=>native,'nativeLayoutHash'=>ReferenceAnchorReview.fingerprint(native),'outputSize'=>[w,h])
[audit,audit.merge('layoutHash'=>audit['nativeLayoutHash'])].each{|a|File.write(File.join(ReferenceAnchorReview::ROOT,a['sourceHash'],a['layoutHash']+'.json'),JSON.pretty_generate(a))}
p=ProductAssetProvider.prepare(f,'background',proposal);raise 'wrong product' unless f['binding']['productHash']==m['productHash']
File.write('diagnostics/canbus-clearance/next-background-OFFLINE-ONLY.json',JSON.pretty_generate(p));File.write('diagnostics/canbus-clearance/audit.json',JSON.pretty_generate(audit));puts JSON.generate(p['binding'])
