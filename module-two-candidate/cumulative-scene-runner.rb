# New controlled scene-only acceptance entry, shared by both existing modules.
require_relative 'cumulative-scene-transport'
require_relative 'bounded-fresh-analysis-transport'
require_relative 'current-input-pipeline'
require_relative 'dependent-scene-session'
module CumulativeSceneRunner
 ROOT=CumulativeSceneTransport::ROOT
 def self.run(request_hash,key:,supervised:)
  raise 'supervised service required' unless supervised
  raise 'invalid request hash' unless request_hash.is_a?(String)&&request_hash.match?(/\A[0-9a-f]{64}\z/)
  ledger=JSON.parse(File.read(File.join(CumulativeSceneTransport::LEDGER,'ledger.json')))
  raise 'cumulative paid acceptance disabled' unless ledger['enabled']==true
  spec=ledger.fetch('approval').fetch('approvedRequests').fetch(request_hash)
  current=%w[current-input-analysis-single current-input-scene-single].include?(spec['scope'])
  raise 'scope not approved' unless (current||spec['identityAndLayoutReviewed']==true)&&%w[product-replacement reference-reconstruction].include?(spec['module'])
  if current
   matched=Dir.glob(File.join(CurrentInputPipeline::ROOT,'*','*','plan.json')).any?{|p|b=JSON.parse(File.read(p))['binding'];b['requestHash']==request_hash&&b['sourceHash']==spec['sourceHash']}
   raise 'current request not prepared' unless matched
  end
  body=File.binread(File.join(ROOT,'diagnostics/cumulative-budget/requests',request_hash+'.json'))
  fresh=%w[fresh-analysis-single current-input-analysis-single].include?(spec['scope'])
  transport=(fresh ? BoundedFreshAnalysisTransport : CumulativeSceneTransport).new(key:key,spec:spec)
  http,raw,details=transport.call(spec['endpoint'],body,{retries:0,timeoutSeconds:fresh ? 120 : 180})
  bound_jobs=CurrentInputPipeline.capture(request_hash,http,raw)
  # Response capture is not visual acceptance. The normal entry parses and composes it.
  {'state'=>http==200 ? (fresh ? 'analysis-response-awaiting-local-validation' : 'scene-response-awaiting-local-review') : 'stopped-response-review-required','requestHash'=>request_hash,'httpStatus'=>http,'responseHash'=>Digest::SHA256.hexdigest(raw),'retries'=>0,'compositionAllowed'=>false,'newModelCalls'=>1,'currentInputJobsCaptured'=>bound_jobs,'transport'=>details}
 ensure
  DependentSceneSession.pause(spec) if defined?(spec)&&spec&&spec['dependency']
 end
end
