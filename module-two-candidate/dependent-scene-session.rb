# Explicit one-edit recovery. Does not touch the stopped job, load credentials,
# dispatch an analysis, or release reserves. Existing transport remains the only sender.
require_relative 'current-input-pipeline'
module DependentSceneSession
 def self.prepare(frozen:,proposal:,relation:,old_job:,root:)
  SceneDependency.validate_relations([relation],frozen,proposal)
  a=FreshAnalysisIntake.prepare(frozen,2)['plan'];old_analysis=CurrentInputPipeline.request(old_job,a,'analysis',nil);raise 'DEPENDENCY_ANALYSIS_RECEIPT_MISSING' unless old_analysis&&old_analysis[0]==200
  # Validate cached analysis through the real semantic contract, not supplied proposal alone.
  actual=FreshAnalysisFlow.consume({'plan'=>a},old_analysis[0],old_analysis[1]).fetch('proposal')
  raise 'DEPENDENCY_PROPOSAL_CHANGED' unless actual['layout']==proposal['layout']&&actual['sourceStructure']==proposal['sourceStructure']
  folder=File.join(old_job,'scene-'+relation['parentRole']);parent_plan=JSON.parse(File.read(folder+'/plan.json'));CurrentInputPipeline.validate_scene_plan(parent_plan,frozen,relation['parentRole'])
  reply=CurrentInputPipeline.request(old_job,parent_plan,'scene-'+relation['parentRole'],nil);raise 'DEPENDENCY_PARENT_RECEIPT_MISSING' unless reply&&reply[2]=='current-model-response'
  parsed=GenerateContentAdapter.parse(reply[0],reply[1],expected_dimensions:parent_plan['binding']['sceneDimensions'])
  expected=SceneDevelopmentReview.binding(source_hash:frozen['binding']['sourceHash'],scene_hash:parsed['outputHash'],layout:proposal['layout'],output_size:frozen['trace']['expectedDimensions'],scene_size:parent_plan['binding']['sceneDimensions'],role:relation['parentRole'])
  raise 'DEPENDENCY_PARENT_NOT_REVIEWED' unless SceneDevelopmentReview.check(folder+'/development-review.json',expected)['accepted']
  novelty=relation.fetch('parentNovelty');raise 'DEPENDENCY_NEW_ENVIRONMENT_UNBOUND' unless novelty['sourceHash']==frozen['binding']['sourceHash']&&novelty['sceneHash']==parsed['outputHash']&&novelty['actualBothPixelsViewed']==true&&novelty['newEnvironment']==true
  parent={'role'=>relation['parentRole'],'base64'=>Base64.strict_encode64(parsed['bytes']),'mime'=>parsed['outputMime'],'sha256'=>parsed['outputHash'],'dimensions'=>parent_plan['binding']['sceneDimensions'],'requestHash'=>parent_plan['binding']['requestHash'],'responseHash'=>Digest::SHA256.hexdigest(reply[1]),'developmentPixelReviewPassed'=>true,'newEnvironmentReviewed'=>true}
  dependency={'relation'=>relation,'parent'=>parent};plan=CurrentInputPipeline.scene_plan(frozen,proposal,relation['targetRole'],dependency:dependency);CurrentInputPipeline.validate_scene_plan(plan,frozen,relation['targetRole'],dependency:dependency,proposal:proposal)
  key=SceneDependency.hash({'dependency'=>plan['binding']['dependency'],'requestHash'=>plan['binding']['requestHash'],'analysisResponseHash'=>Digest::SHA256.hexdigest(old_analysis[1])});dir=File.join(root,key)
  raise 'DEPENDENCY_RECOVERY_ALREADY_EXISTS' if File.exist?(dir)
  FileUtils.mkdir_p(dir)
  # Copy returned bytes into NEW bindings; never copy a rejected child, delete stop,
  # or copy a begun marker as permission to resend.
  [[a,'analysis',old_analysis],[parent_plan,'scene-'+relation['parentRole'],reply]].each do |p,stage,response|
   CurrentInputPipeline.request(dir,p,stage,nil);bound=JSON.parse(File.read(File.join(dir,stage,'plan.json')))['binding'];File.binwrite(File.join(dir,stage,'response.raw.json'),response[1]);CurrentInputPipeline.write(File.join(dir,stage,'receipt.json'),{'binding'=>bound,'httpStatus'=>response[0],'responseHash'=>Digest::SHA256.hexdigest(response[1]),'origin'=>response[2]})
  end
  FileUtils.cp(folder+'/development-review.json',File.join(dir,'scene-'+relation['parentRole'],'development-review.json'))
  CurrentInputPipeline.write(File.join(dir,'scene-'+relation['parentRole'],'new-environment-review.json'),novelty)
  CurrentInputPipeline.request(dir,plan,'scene-'+relation['targetRole'],nil)
  CurrentInputPipeline.write(dir+'/scene-dependencies.json',[relation])
  {'jobHash'=>key,'plan'=>plan,'sceneDependencies'=>[relation],'newModelCalls'=>0,'analysisCalls'=>0,'remainingSceneCalls'=>1,'automaticCompositionAllowed'=>false}
 end
 def self.authorize(prepared,ledger:,enabled:false)
  raise 'DEPENDENCY_EDIT_NOT_RELEASED' unless enabled
  plan=prepared.fetch('plan');b=plan.fetch('binding');raise 'DEPENDENCY_EDIT_BINDING_MISSING' unless b['dependency']&&b['requestHash']==Digest::SHA256.hexdigest(plan['body'])&&prepared['remainingSceneCalls']==1
  images=JSON.parse(plan['body']).fetch('contents').flat_map{|x|x['parts']}.select{|x|x['inlineData']};raise 'DEPENDENCY_EDIT_IMAGE_CHANGED' unless images.size==1&&Digest::SHA256.hexdigest(Base64.strict_decode64(images[0]['inlineData']['data']))==b['dependency']['parentSceneHash']
  spec={'requestHash'=>b['requestHash'],'sourceHash'=>b['sourceHash'],'endpoint'=>GenerateContentAdapter::ENDPOINT,'module'=>'reference-reconstruction','scope'=>'current-input-scene-single','identityAndLayoutReviewed'=>true,'sessionId'=>'dependent-edit-'+prepared['jobHash'],'stage'=>'scene-'+b['sceneRole'],'reserveMicroUSD'=>410000,'boundMicroUSD'=>409600,'maxRequests'=>1,'retries'=>0,'dependency'=>b['dependency']}
  File.open(File.join(ledger,'ledger.lock'),'a') do |lock|
   lock.flock(File::LOCK_EX);file=File.join(ledger,'ledger.json');s=JSON.parse(File.read(file));rs=s.fetch('requests');all=s.fetch('history')+rs.values
   raise 'DEPENDENCY_LEDGER_NOT_PAUSED' if s['enabled']
   raise 'DEPENDENCY_OUTSTANDING_REQUEST' if rs.values.any?{|x|%w[reserved dispatched-uncertain uncertain-reserve-retained].include?(x['state'])}
   raise 'DEPENDENCY_EDIT_ALREADY_CONSUMED' if all.any?{|x|x['requestHash']==b['requestHash']||x['sessionId']==spec['sessionId']}
   parent=rs[b['dependency']['parentRequestHash']];raise 'DEPENDENCY_PARENT_LEDGER_MISSING' unless parent&&parent['state']=='returned-reserve-retained'&&parent['responseHash']==b['dependency']['parentResponseHash']
   held=all.sum{|x|x['reserveMicroUSD']};raise 'DEPENDENCY_BUDGET_BASE_CHANGED' unless held==9020000
   raise 'DEPENDENCY_BUDGET_EXCEEDED' unless held+410000<=[s['capMicroUSD'],9430000].min
   requests_dir=File.join(File.dirname(ledger),'requests');FileUtils.mkdir_p(requests_dir);request_file=File.join(requests_dir,b['requestHash']+'.json')
   if File.exist?(request_file);raise 'DEPENDENCY_STORED_BODY_CHANGED' unless File.binread(request_file)==plan['body'];else;File.binwrite(request_file,plan['body']);end
   s['approval']={'id'=>spec['sessionId'],'capMicroUSD'=>s['capMicroUSD'],'priorSTOPPreserved'=>true,'approvedRequests'=>{b['requestHash']=>spec}};s['enabled']=true;s['events']<<{'event'=>'authorize-dependent-edit','requestHash'=>b['requestHash'],'maxAdditionalMicroUSD'=>410000}
   CurrentInputPipeline.write(file,s)
  end
  spec
 end
 def self.pause(spec,ledger:CumulativeSceneTransport::LEDGER)
  File.open(File.join(ledger,'ledger.lock'),'a') do |lock|
   lock.flock(File::LOCK_EX);file=File.join(ledger,'ledger.json');s=JSON.parse(File.read(file))
   return unless s.dig('approval','id')==spec['sessionId']
   s['enabled']=false;s['events']<<{'event'=>'pause-dependent-edit','requestHash'=>spec['requestHash'],'reserveReleased'=>0};CurrentInputPipeline.write(file,s)
  end
 end

end
