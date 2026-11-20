# Fresh analysis orchestration, independent of the final asset cache. Network is supplied
# only by a separately authorized caller; prepare/consume never dispatch or read keys.
require_relative 'product-asset-provider'
require_relative 'local-source-structure'
require_relative 'source-observation-refinement'
require_relative 'source-observation-gate'
module FreshAnalysisFlow
 VERSION='fresh-analysis-flow-20261019.1'
 def self.prepare(frozen)
  plan=frozen.dig('binding','module')=='product-replacement' ? ProductAssetProvider.prepare(frozen) : ReferenceProvider.prepare(frozen,'layout-copy')
  {'version'=>VERSION,'state'=>'fresh-analysis-prepared','plan'=>plan,'finalAssetCacheRead'=>false,'responseCacheRead'=>false,'modelCalls'=>0,'liveEnabled'=>false}
 end
 def self.consume(prepared,http,raw)
  original_response_hash=Digest::SHA256.hexdigest(raw)
  plan=prepared.fetch('plan');raise 'fresh payload changed' unless Digest::SHA256.hexdigest(plan['body'])==plan.dig('binding','requestHash')
  opts=(plan['productFrozen']||plan['frozen'])['options']
  envelope,part,_usage=ReferenceProvider.analysis_envelope(http,raw);observed=ReferenceProvider.decode_analysis(part)
  refinement=nil
  if observed['sourceStructure']&&!plan['productFrozen']
   body=JSON.parse(plan['body']);image=body['contents'].flat_map{|c|c['parts']}.find{|p|p['inlineData']}
   bytes=Base64.strict_decode64(image.fetch('inlineData').fetch('data'))
   observed,refinement=SourceObservationRefinement.apply(bytes,observed,plan.dig('binding','sourceHash'))
   part['text']=JSON.generate(observed);raw=JSON.generate(envelope)
  end
  unless observed['sourceStructure']
   body=JSON.parse(plan['body']);image=body['contents'].flat_map{|c|c['parts']}.find{|p|p['inlineData']}
   bytes=Base64.strict_decode64(image.fetch('inlineData').fetch('data'));raise 'local structure source mismatch' unless Digest::SHA256.hexdigest(bytes)==plan.dig('binding','sourceHash')
   observed['sourceStructure']=LocalSourceStructure.observe(bytes,observed);part['text']=JSON.generate(observed);raw=JSON.generate(envelope)
  end
  if %w[custom remove-all-copy].include?(opts['mode'])
   envelope=JSON.parse(raw);part=envelope.fetch('candidates')[0].fetch('content').fetch('parts').find{|x|x['text']&&!x['thought']};v=JSON.parse(part['text']);v['text'].each{|t|t.delete('mode')};v['text']=opts['mode']=='custom' ? [v.fetch('text').first.merge('text'=>opts.fetch('customCopy'),'role'=>'body')] : [];part['text']=JSON.generate(v);raw=JSON.generate(envelope)
  end
  if plan['productFrozen'];proposal=ProductAssetProvider.parse_analysis(plan,http,raw,defer_layout:true)
  else
   parsed=ReferenceProvider.parse(plan,http,raw)
   return {'state'=>'stopped-unresolved-copy','audit'=>parsed['contractAudit'],'backgroundCalls'=>0,'compositionAllowed'=>false} unless parsed['plan']
   proposal={'layout'=>parsed['plan'],'copyDecisions'=>parsed['copyDecisions'],'sourceStructure'=>parsed['sourceStructure'],'localObservationRefinement'=>refinement,'warnings'=>[parsed['semanticAudit'],parsed['contractAudit']].compact}
  end
  SourceStructure.validate(proposal['sourceStructure'],proposal['layout'],product:!!plan['productFrozen'])
  unless plan['productFrozen']
   retained=proposal['layout']['evidence']['rewrites'].select{|r|r['action']=='render'}.map{|r|r['blockId']}
   gate=SourceObservationGate.audit(bytes,observed,refinement,retained)
   return {'state'=>'stopped-source-observation-review','blocker'=>'源图区域或文字位置尚未获得可靠的本地核验，已停止后续生成。已保存分析可复用；不会自动重新分析或重试。','sourceObservationAudit'=>gate,'candidateProposal'=>proposal,'analysisResponseHash'=>original_response_hash,'analysisRequestHash'=>plan['binding']['requestHash'],'backgroundCalls'=>0,'compositionAllowed'=>false} if gate['state']=='pending'
   proposal['sourceObservationAudit']=gate
  end
  {'contentPolicyVersion'=>(!plan['productFrozen']&&opts['mode']=='ai-rewrite' ? ContentSelection::VERSION : nil),'state'=>'fresh-analysis-ready-for-local-layout','proposal'=>proposal,'analysisResponseHash'=>original_response_hash,'analysisRequestHash'=>plan['binding']['requestHash'],'sourceHash'=>plan['binding']['sourceHash'],'finalAssetCacheRead'=>false,'manualFinalCopyProvided'=>false,'manualFinalCoordinatesProvided'=>false,'backgroundCalls'=>0,'compositionAllowed'=>false}
 end
end
