require_relative 'product-asset-provider'
require 'tmpdir'
checks=[];ok=lambda{|v,m|raise m unless v;checks<<m}
a=JSON.parse(File.read('diagnostics/two-backgrounds-20261018/step1-plan.json'));b=JSON.parse(File.read('diagnostics/two-backgrounds-20261018/step2-plan.json'))
p1=ReferenceProvider.prepare(a['frozen'],'background',a['layout']);p2=ProductAssetProvider.prepare(b['productFrozen'],'background',b['proposal'])
[p1,p2].each_with_index do |p,i|
 text=JSON.parse(p['body'])['contents'][0]['parts'][0]['text'];c=p['sceneInputContract']
 ok.call(c['deliveryKind']=='scene-candidate-only'&&c['renderedDecorations']==false&&c['localDecorationRequired']&&!c['automaticCompositionAllowed'],"module #{i+1} stages scene-only input")
 ok.call(text.include?('Do not draw any outer frame')&&text.include?('Do not compose comparison panels')&&!text.include?('Retain the selected panel count'),"module #{i+1} removes old raster frame instructions")
 ok.call(!p['liveEnabled']&&p['binding']['retries']==0,"module #{i+1} remains disabled")
end
# Fixture parser replaces only image decoding, not provider orchestration; no transport network.
module GenerateContentAdapter
 class << self
  alias_method :original_scene_test_parse,:parse
  def parse(*args,**kw);{'bytes'=>'fixture','outputMime'=>'image/png','outputHash'=>'fixture-sha','usage'=>{}};end
 end
end
r=ReferenceProvider.parse(p1,200,'{}');ok.call(r['sceneCandidate']&&!r.key?('background')&&!r['compositionAllowed'],'reference scene candidate cannot masquerade as decorated background')
module ProductAssetProvider
 class << self
  alias_method :original_scene_test_analysis,:parse_analysis
  attr_accessor :scene_test_proposal
  def parse_analysis(*);scene_test_proposal;end
 end
end
ProductAssetProvider.scene_test_proposal=b['proposal'];f=b['productFrozen'];analysis=ProductAssetProvider.prepare(f)
Dir.mktmpdir do |dir|
 calls=0;r=ProductAssetProvider.execute(f,dir,approval:{'id'=>'OFFLINE-ONLY','analysisRequestHash'=>analysis['binding']['requestHash'],'maxRequests'=>2,'budgetMicroUSD'=>280000},transport:lambda{|*_|calls+=1;[200,'{}']},mock:true)
 folder=File.join(dir,f['binding']['requestHash']);ok.call(r['state']=='scene-candidate-awaiting-local-decoration'&&File.file?(folder+'/scene-candidate.json')&&!File.exist?(folder+'/package.json'),'product pipeline stores scene candidate, not directly compositable cache')
 ok.call(calls==2&&!r['compositionAllowed'],'one existing bounded stub batch; no implicit extra pair generation')
end
puts JSON.pretty_generate({checks:checks,externalCalls:0})
File.write('diagnostics/deterministic-decoration/scene-only-integration.json',JSON.pretty_generate({checks:checks,externalCalls:0}))
