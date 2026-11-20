# Trusted, source-bound one-shot session for the normal prepare entry.
# No credential loading, no previous allowance reuse, no browser-supplied approval.
require_relative 'current-input-pipeline'
require_relative 'analysis-cache-recovery'
require_relative 'bounded-fresh-analysis-transport'
require_relative 'cumulative-scene-transport'
module CurrentInputSession
 LOADED_ANALYSIS_REPAIR=%w[default-product-facts.rb content-selection.rb direct-image-plan.rb local-preparation-record.rb bridge-direct-image.rb fresh-analysis-intake.rb business-ui.js internal-inter-text.js product-local-ui.js bridge-server.rb reference-provider.rb fresh-analysis-flow.rb product-asset-provider.rb analysis-observations-v2.rb current-input-session.rb current-input-pipeline.rb source-observation-refinement.rb source-observation-gate.rb source-scene-coverage.py local-source-structure.rb observe-reference-strips.py copy-element-resolution.rb source-structure.rb analysis-cache-recovery.rb analysis-output-contract.rb render-association-resolution.rb local-reference-ocr.js source-decoration-pixels.py automatic-analysis-compose.js].to_h{|name|[name,Digest::SHA256.file(File.join(__dir__,name)).hexdigest]}.freeze
 CONFIG=File.join(__dir__,'current-input-approval.json')
 def self.config_for(frozen,path:CONFIG)
  return nil unless File.file?(path)
  c=JSON.parse(File.read(path));return nil unless c['enabled']==true
  return nil unless c['sourceHash']==frozen.dig('binding','sourceHash')&&c['jobHash']==frozen.dig('binding','requestHash')
  if c['fullValidation']==true
   raise 'full validation limits changed' unless c['maxRequests']==3&&c['additionalCapMicroUSD']==1310000&&c['cumulativeCapMicroUSD']==9020000&&c['initialHeldMicroUSD']==7710000&&c['module']=='reference-reconstruction'&&[true,false].include?(c['releaseScenes'])&&c['developmentReview']==true
  elsif c['analysisOnly']==true
   raise 'analysis-only limits changed' unless c['maxRequests']==1&&c['additionalCapMicroUSD']==490000&&c['cumulativeCapMicroUSD']==7710000&&c['initialHeldMicroUSD']==7220000&&c['module']=='reference-reconstruction'
  else
  raise 'session limits changed' unless c['maxRequests']==3&&c['additionalCapMicroUSD']==1310000&&c['cumulativeCapMicroUSD']==8040000&&c['initialHeldMicroUSD']==6730000&&c['module']=='reference-reconstruction'
  end
  raise 'session module changed' unless frozen.dig('binding','module')==c['module']
  c
 end
 def self.authorize(plan,stage,c,ledger:BoundedFreshAnalysisTransport::LEDGER)
  b=plan.fetch('binding');analysis=stage=='analysis';raise 'recovered analysis must never dispatch again' if analysis&&c['analysisRecovery'];body=JSON.parse(plan.fetch('body'))
  raise 'analysis validation required before any scene dispatch' if c['fullValidation']==true&&!analysis&&c['releaseScenes']!=true
  raise 'analysis-only session forbids scene dispatch' if c['analysisOnly']==true&&!analysis
  raise 'session task binding changed' unless b['sourceHash']==c['sourceHash']&&b['requestHash']==Digest::SHA256.hexdigest(plan['body'])
  raise 'analysis request changed' if analysis&&b['requestHash']!=c['analysisRequestHash']
  raise 'scene stage invalid' unless analysis||stage.match?(/\Ascene-[a-zA-Z0-9_-]+\z/)
  images=body.fetch('contents').flat_map{|a|a.fetch('parts')}.select{|a|a['inlineData']}
  raise 'session reference scope changed' unless images.size==1&&Digest::SHA256.hexdigest(Base64.strict_decode64(images[0]['inlineData']['data']))==c['sourceHash']
  spec={'requestHash'=>b['requestHash'],'sourceHash'=>c['sourceHash'],'endpoint'=>analysis ? BoundedFreshAnalysisTransport::ENDPOINT : CumulativeSceneTransport::ENDPOINT,'module'=>c['module'],'scope'=>analysis ? 'current-input-analysis-single' : 'current-input-scene-single','identityAndLayoutReviewed'=>true,'sessionId'=>c.fetch('id'),'stage'=>stage,'reserveMicroUSD'=>analysis ? 490000 : 410000,'boundMicroUSD'=>analysis ? 488653 : 409600,'maxRequests'=>1,'retries'=>0}
  raise 'endpoint mismatch' unless b['endpoint']==spec['endpoint']
  File.open(File.join(ledger,'ledger.lock'),'a') do |lock|
   lock.flock(File::LOCK_EX);file=File.join(ledger,'ledger.json');s=JSON.parse(File.read(file));requests=s.fetch('requests');prior=requests.values.select{|a|a['sessionId']==c['id']}
   raise 'request already consumed' if requests.key?(b['requestHash'])||s['history'].any?{|a|a['requestHash']==b['requestHash']}
   raise 'session stage already consumed' if prior.any?{|a|a['stage']==stage}
   raise 'session request count exceeded' if prior.size>=c['maxRequests']||(!analysis&&prior.count{|a|a['stage']!='analysis'}>=2)
   raise 'scene requires returned analysis' if !analysis&&!prior.any?{|a|a['stage']=='analysis'&&a['state']=='returned-reserve-retained'}
   raise 'outstanding request remains' if requests.values.any?{|a|%w[reserved dispatched-uncertain uncertain-reserve-retained].include?(a['state'])}
   held=s['history'].sum{|a|a['reserveMicroUSD']}+requests.values.sum{|a|a['reserveMicroUSD']}
   raise 'session cumulative ceiling exceeded' if held+spec['reserveMicroUSD']>[s['capMicroUSD'],c['cumulativeCapMicroUSD']].min
   raise 'session allowance exceeded' if prior.sum{|a|a['reserveMicroUSD']}+spec['reserveMicroUSD']>c['additionalCapMicroUSD']
   raise 'historical budget unexpectedly reduced' if held-prior.sum{|a|a['reserveMicroUSD']}<c['initialHeldMicroUSD']
   s['approval']={'id'=>c['id'],'capMicroUSD'=>s['capMicroUSD'],'priorSTOPPreserved'=>true,'approvedRequests'=>{spec['requestHash']=>spec}}
   s['enabled']=true;s['events']<<{'event'=>'authorize-current-session-stage','sessionId'=>c['id'],'requestHash'=>spec['requestHash'],'stage'=>stage,'reserveReleased'=>0}
   File.write(file+'.tmp',JSON.pretty_generate(s));File.rename(file+'.tmp',file)
  end
  spec
 end
 # Close only this session's transient dispatch enablement; retained reserves stay untouched.
 def self.pause_dispatch(config,ledger:BoundedFreshAnalysisTransport::LEDGER)
  File.open(File.join(ledger,'ledger.lock'),'a') do |lock|
   lock.flock(File::LOCK_EX);file=File.join(ledger,'ledger.json');s=JSON.parse(File.read(file))
   return false unless s.dig('approval','id')==config.fetch('id')&&s['enabled']==true
   s['enabled']=false
   s['events']<<{'event'=>'pause-current-session-dispatch','sessionId'=>config['id'],'reserveReleased'=>0}
   File.write(file+'.tmp',JSON.pretty_generate(s));File.rename(file+'.tmp',file)
   true
  end
 end
 def self.run(frozen,key:,supervised:,config:)
  raise 'existing supervised runtime required' unless supervised
  root=CurrentInputPipeline::ROOT;recovery_key=AnalysisCacheRecovery.prepare(frozen,config,root:root) if config['analysisRecovery'];dir=File.join(root,recovery_key||(config['fullValidation']==true ? config.fetch('analysisRequestHash') : config['analysisOnly']==true ? 'analysis-only-'+config.fetch('analysisRequestHash') : config['jobHash']));FileUtils.mkdir_p(dir)
  return {'state'=>'stopped-current-session','newModelCalls'=>0,'blocker'=>'本轮已停止，不自动重试。'} if File.file?(File.join(dir,'session-stop.json'))
  transport=lambda do |plan,stage|
   spec=authorize(plan,stage,config);klass=stage=='analysis' ? BoundedFreshAnalysisTransport : CumulativeSceneTransport
   http,raw,_=klass.new(key:key,spec:spec).call(spec['endpoint'],plan['body'],{retries:0,timeoutSeconds:stage=='analysis' ? 120 : 180})
   [http,raw,'current-model-response']
  ensure
   pause_dispatch(config) if spec
  end
  if config['analysisOnly']==true||(config['fullValidation']==true&&config['releaseScenes']!=true)
   prepared=FreshAnalysisIntake.prepare(frozen,2)
   raise 'analysis-only request changed' unless prepared.dig('plan','binding','requestHash')==config['analysisRequestHash']
   http,raw,_=CurrentInputPipeline.request(dir,prepared['plan'],'analysis',transport)
   result=FreshAnalysisFlow.consume(prepared,http,raw).merge('analysisOnly'=>true,'sceneRequests'=>0,'compositionAllowed'=>false)
   if config['fullValidation']==true
    raise 'analysis unresolved; no scene dispatch' unless result['proposal']
    result.merge!('state'=>'awaiting-analysis-validation','analysisOnly'=>false,'blocker'=>'本轮分析已返回，正在进行免费文字、标签和产品范围检查；尚未调用场景模型。')
   end
   CurrentInputPipeline.write(File.join(dir,'analysis-result.json'),result)
   return result
  end
  result=CurrentInputPipeline.run(frozen,transport:transport,development_review:config['developmentReview']==true,max_scene_calls:2,job_key:recovery_key||(config['fullValidation']==true ? config['analysisRequestHash'] : nil))
  if result['state'].to_s.start_with?('stopped')
   CurrentInputPipeline.write(File.join(dir,'session-stop.json'),{'state'=>result['state'],'retries'=>0})
  end
  result
 rescue StandardError=>e
  CurrentInputPipeline.write(File.join(dir,'session-stop.json'),{'state'=>'stopped','reason'=>e.message,'retries'=>0}) if dir
  raise
 end
end
