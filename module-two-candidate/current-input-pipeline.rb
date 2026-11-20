# Request-bound scene ingestion. Production validates identity/geometry; optional pixel review is development-only.
require_relative 'fresh-analysis-intake'
require_relative 'local-reference-ocr'
require_relative 'scene-development-review'
require_relative 'scene-dependency'
module CurrentInputPipeline
 ROOT=File.join(__dir__,'current-input-jobs')
 def self.write(path,value)
  File.write(path+'.tmp',JSON.pretty_generate(value));File.rename(path+'.tmp',path)
 end
 def self.request(dir,plan,stage,transport)
  raise 'task cancelled; no further requests' if File.exist?(File.join(dir,'cancelled.json'))
  h=plan.fetch('binding').fetch('requestHash');raise 'request bytes changed' unless Digest::SHA256.hexdigest(plan['body'])==h
  folder=File.join(dir,stage);FileUtils.mkdir_p(folder);binding=plan['binding'].merge('jobHash'=>File.basename(dir),'stageId'=>stage)
  fp=File.join(folder,'plan.json');if File.exist?(fp);raise 'stage changed' unless JSON.parse(File.read(fp))['binding']==binding;else;write(fp,{'binding'=>binding,'body'=>plan['body']});end
  receipt=File.join(folder,'receipt.json');rawfile=File.join(folder,'response.raw.json')
  unless File.exist?(receipt)
   return nil unless transport
   # The transport must be configured by the trusted server with an exact authorization.
   # Durable begin before invoking it; an interruption or uncertain return never re-sends.
   beginfile=File.join(folder,'begun.json');raise 'request outcome uncertain; no automatic retry' if File.exist?(beginfile)
   File.open(beginfile,File::WRONLY|File::CREAT|File::EXCL,0600){|f|f.write(JSON.generate(binding));f.flush;f.fsync}
   http,raw,origin=transport.call(plan,stage)
   File.binwrite(rawfile,raw);write(receipt,{'binding'=>binding,'httpStatus'=>http,'responseHash'=>Digest::SHA256.hexdigest(raw),'origin'=>origin||'current-model-response'})
  end
  r=JSON.parse(File.read(receipt));raise 'response belongs to another task' unless r['binding']==binding
  raw=File.binread(rawfile);raise 'response bytes changed' unless Digest::SHA256.hexdigest(raw)==r['responseHash']
  [r['httpStatus'],raw,r['origin']]
 end
 def self.cancel(job,root:ROOT)
  raise 'invalid job hash' unless job.to_s.match?(/\A[0-9a-f]{64}\z/)
  dir=File.join(root,job);raise 'unknown job' unless File.directory?(dir)
  write(File.join(dir,'cancelled.json'),{'state'=>'cancelled','alreadySentRequestsNotUndone'=>true})
 end
 # Called only by the trusted existing transport after its exact authorized request.
 # Never accepts a browser-supplied raw response or fabricates semantic approval.
 def self.capture(request_hash,http,raw,root:ROOT)
  raise 'invalid request hash' unless request_hash.to_s.match?(/\A[0-9a-f]{64}\z/)
  matches=Dir.glob(File.join(root,'*','*','plan.json')).select{|f|JSON.parse(File.read(f)).dig('binding','requestHash')==request_hash}
  matches.each do |file|
   p=JSON.parse(File.read(file));raise 'pending request changed' unless Digest::SHA256.hexdigest(p['body'])==request_hash
   dir=File.dirname(file);receipt=File.join(dir,'receipt.json');digest=Digest::SHA256.hexdigest(raw)
   if File.exist?(receipt);raise 'different response already bound' unless JSON.parse(File.read(receipt))['responseHash']==digest;next;end
   File.binwrite(File.join(dir,'response.raw.json'),raw);write(receipt,{'binding'=>p['binding'],'httpStatus'=>http,'responseHash'=>digest,'origin'=>'current-model-response'})
  end
  matches.size
 end
 def self.normalized(value)
  case value;when Hash;value.keys.sort.to_h{|k|[k,normalized(value[k])]};when Array;value.map{|v|normalized(v)};when Float;value==value.to_i ? value.to_i : value;else;value;end
 end
 def self.scene_plan(frozen,proposal,role,dependency:nil)
  p=frozen.dig('binding','module')=='product-replacement' ? ProductAssetProvider.prepare(frozen,'background',proposal) : ReferenceProvider.prepare(frozen,'background',proposal['layout'])
  dims=frozen.dig('trace','expectedDimensions')
  if proposal['sourceStructure']['panels'].any?
   # All comparison assets have one raster size and receive exactly the same camera/layout
   # instruction. No asset is stretched separately and no image is duplicated for a pair.
   w,h=frozen.dig('trace','expectedDimensions');sw,sh=proposal['layout']['sourceGeometry'].values_at('width','height');k=[w.to_f/sw,h.to_f/sh].min
   views=proposal['sourceStructure']['panels'].map{|panel|v=SourceStructure.scene_bounds(panel,sw);[v['width']*k,v['height']*k]}
   raise 'invalid comparison scene viewport' unless views.all?{|v|v.all?{|n|n>0}}
   target=views.map(&:first).min/views.map(&:last).min;ratio,dims=RulesCompiler::SIZES.min_by{|_,size|(Math.log(size[0].to_f/size[1]/target)).abs}
   body=JSON.parse(p['body']);body['generationConfig']['imageConfig']={'aspectRatio'=>ratio,'imageSize'=>'2K'}
   panel=proposal['sourceStructure']['panels'].find{|item|item['sceneRole']==role};raise 'unknown scene role' unless panel
   body['contents'][0]['parts'][0]['text'] += "\nSCENE CONDITION: Render only reference panel #{panel['id']} at source-pixel bounds #{JSON.generate(panel['bounds'])}, condition key #{role}. Those source bounds identify the evidence, not output or generated-scene coordinates. Return a full-bleed #{dims.join('x')} scene, #{ratio}, 2K (overrides final poster size above). Preserve the same camera, scene arrangement, objects and positions across conditions; only the observed weather/lighting/evidence condition differs; never flatten distinct observed conditions into one generic scene. Never render poster frames, text or labels. Include the entire evidence field with margins."
   p['body']=JSON.generate(body);p['binding']['requestHash']=Digest::SHA256.hexdigest(p['body'])
  end
  p['binding']=p['binding'].merge('sceneRole'=>role,'sceneDimensions'=>dims)
  dependency ? SceneDependency.prepare(p,dependency.fetch('relation'),dependency.fetch('parent')) : p
 end
 def self.validate_scene_plan(plan,frozen,role,dependency:nil,proposal:nil)
  b=plan.fetch('binding');body=JSON.parse(plan.fetch('body'));images=body.fetch('contents').flat_map{|c|c.fetch('parts')}.select{|p|p['inlineData']}
  raise 'scene plan task mismatch' unless b['sourceHash']==frozen.dig('binding','sourceHash')&&b['frozenRequestHash']==frozen.dig('binding','requestHash')&&b['sceneRole']==role&&b['requestHash']==Digest::SHA256.hexdigest(plan['body'])
  if dependency
   raise 'DEPENDENCY_PLAN_NOT_EXACT' unless proposal&&plan['body']==scene_plan(frozen,proposal,role,dependency:dependency)['body']&&b.reject{|k,_|%w[jobHash stageId].include?(k)}==scene_plan(frozen,proposal,role,dependency:dependency)['binding']
  else
   raise 'DEPENDENCY_CONTEXT_REQUIRED' if b['dependency']
   raise 'scene plan must send only reference' unless images.size==1&&Digest::SHA256.hexdigest(Base64.strict_decode64(images[0]['inlineData']['data']))==b['sourceHash']
  end
  config=body.fetch('generationConfig');raise 'scene configuration changed' unless config['candidateCount']==1&&config['responseModalities']==['IMAGE']&&config['maxOutputTokens']==4096&&config.dig('imageConfig','imageSize')=='2K'&&b['sceneDimensions']==RulesCompiler::SIZES[config.dig('imageConfig','aspectRatio')]
  raise 'scene endpoint changed' unless b['endpoint']==GenerateContentAdapter::ENDPOINT&&b['retries']==0
  plan
 end
 # Reuse an already returned analysis and an exactly frozen scene request. No model call.
 def self.prime(frozen:,analysis_raw:,analysis_request_hash:,scene_plan:,root:ROOT)
  a=FreshAnalysisIntake.prepare(frozen,2);raise 'original analysis request mismatch' unless a.dig('plan','binding','requestHash')==analysis_request_hash
  result=FreshAnalysisFlow.consume(a,200,analysis_raw);raise 'analysis unresolved' unless result['proposal']
  raise 'prime single scene only' unless result['proposal']['sourceStructure']['panels'].empty?
  p=Marshal.load(Marshal.dump(scene_plan));p['binding'].merge!('sceneRole'=>'single','sceneDimensions'=>frozen.dig('trace','expectedDimensions'));validate_scene_plan(p,frozen,'single')
  dir=File.join(root,frozen.dig('binding','requestHash'));FileUtils.mkdir_p(dir);request(dir,a['plan'],'analysis',nil);capture(analysis_request_hash,200,analysis_raw,root:root);request(dir,p,'scene-single',nil)
  {'state'=>'awaiting-current-scene-response','jobHash'=>File.basename(dir),'requestHash'=>p.dig('binding','requestHash'),'newModelCalls'=>0}
 end
 def self.run(frozen,root:ROOT,transport:nil,development_review:false,max_scene_calls:nil,job_key:nil,scene_dependencies:[])
  raise 'invalid session job key' if job_key&&!job_key.match?(/\A[0-9a-f]{64}\z/)
  job=job_key||frozen.fetch('binding').fetch('requestHash');dir=File.join(root,job);FileUtils.mkdir_p(dir)
  File.open(File.join(dir,'lock'),'w') do |lock|
   lock.flock(File::LOCK_EX)
   raise 'DEPENDENCY_JOB_STOPPED' if !scene_dependencies.empty?&&File.file?(File.join(dir,'session-stop.json'))
   a=FreshAnalysisIntake.prepare(frozen,2);ar=request(dir,a['plan'],'analysis',transport)
   return {'state'=>'awaiting-current-analysis-response','jobHash'=>job,'requests'=>[a['plan']['binding']],'newModelCalls'=>0,'automaticCompositionAllowed'=>false,'missingAnalysisFields'=>['source text groups and roles','claim evidence and dependent-claim decisions','source subject/illustration/decor ownership','source-bound text-safe geometry'],'blocker'=>'缺少当前参考图的文字分组、文案依据、主体/线稿归属及安全排版几何；干净视觉层不能替代这些分析。已停止叠字，未调用模型。'} unless ar
   result=FreshAnalysisFlow.consume(a,ar[0],ar[1]);return result unless result['proposal']
   proposal=result['proposal'];panels=proposal['sourceStructure']['panels'];roles=panels.empty? ? ['single'] : panels.map{|p|p['sceneRole']};raise 'ambiguous scene roles' unless roles.uniq.size==roles.size
   raise 'SCENE_CALL_BUDGET_EXCEEDED: reference panel count is supported but current session scene-call allowance is insufficient; no scene dispatched' if max_scene_calls && roles.size>max_scene_calls
   SceneDependency.validate_relations(scene_dependencies,frozen,proposal)
   scenes=[];warnings=[];origins=[ar[2]]
   roles.each do |role|
    relation=scene_dependencies.find{|d|d['targetRole']==role};dependency=relation&&{'relation'=>relation,'parent'=>scenes.find{|v|v['role']==relation['parentRole']}}
    stored=File.join(dir,'scene-'+role,'plan.json');plan=File.file?(stored) ? JSON.parse(File.read(stored)) : scene_plan(frozen,proposal,role,dependency:dependency);validate_scene_plan(plan,frozen,role,dependency:dependency,proposal:proposal);reply=request(dir,plan,'scene-'+role,transport)
    return {'state'=>'awaiting-current-scene-response','jobHash'=>job,'pendingRole'=>role,'totalPlannedRequests'=>1+roles.size,'requests'=>[plan['binding']],'completedRoles'=>scenes.map{|s|s['role']},'newModelCalls'=>0} unless reply
    parsed=GenerateContentAdapter.parse(reply[0],reply[1],expected_dimensions:plan['binding']['sceneDimensions']);ocr=LocalReferenceOCR.observe(parsed['bytes'],parsed['outputHash'])
    warnings<<"Scene #{role}: local OCR unavailable; typography cleanliness not verified." if ocr['state']=='unavailable'
    warnings<<"Scene #{role}: OCR detected text; inspect for residual overlays before use." unless ocr.fetch('lines',[]).empty?
    # Optional development checkpoint, never a mandatory production approval.
    if (development_review||!scene_dependencies.empty?) && !reply[2].to_s.start_with?('offline-fixture:')
     expected=SceneDevelopmentReview.binding(source_hash:frozen.dig('binding','sourceHash'),scene_hash:parsed['outputHash'],layout:proposal['layout'],output_size:frozen.dig('trace','expectedDimensions'),scene_size:plan['binding']['sceneDimensions'],role:role)
     stage_dir=File.join(dir,'scene-'+role)
     File.binwrite(File.join(stage_dir,'candidate.image'),parsed['bytes'])
     write(File.join(stage_dir,'review-required.json'),{'binding'=>expected,'localOCR'=>ocr,'checksRequired'=>SceneDevelopmentReview::CHECKS,'automaticVisualAcceptance'=>false})
     review=SceneDevelopmentReview.check(File.join(stage_dir,'development-review.json'),expected)
     unless review['accepted']
      return {'state'=>review['state'],'jobHash'=>job,'pendingRole'=>role,'completedRoles'=>scenes.map{|s|s['role']},'newModelCalls'=>0,'automaticCompositionAllowed'=>false,'blocker'=>'场景响应已保存，等待开发期实际像素验收；OCR不能证明场景完整与安全，验收前不叠字、不生成下一张。'}
     end
    end
    parent_needed=scene_dependencies.any?{|d|d['parentRole']==role}
    if parent_needed
     novelty_path=File.join(dir,'scene-'+role,'new-environment-review.json');raise 'DEPENDENCY_NEW_ENVIRONMENT_REVIEW_REQUIRED' unless File.file?(novelty_path)
     novelty=JSON.parse(File.read(novelty_path));raise 'DEPENDENCY_NEW_ENVIRONMENT_UNBOUND' unless novelty['sourceHash']==frozen.dig('binding','sourceHash')&&novelty['sceneHash']==parsed['outputHash']&&novelty['actualBothPixelsViewed']==true&&novelty['newEnvironment']==true
    end
    scenes<<{'developmentPixelReviewPassed'=>!!(review&&review['accepted']),'newEnvironmentReviewed'=>parent_needed,'role'=>role,'base64'=>Base64.strict_encode64(parsed['bytes']),'mime'=>parsed['outputMime'],'sha256'=>parsed['outputHash'],'requestHash'=>plan.dig('binding','requestHash'),'responseHash'=>Digest::SHA256.hexdigest(reply[1]),'dimensions'=>plan.dig('binding','sceneDimensions')};origins<<reply[2]
    if dependency
     pair=SceneDependency.check_pair(File.join(dir,'scene-'+role,'dependency-pair-review.json'),relation,dependency['parent'],scenes.last,proposal['layout'])
     unless pair['accepted']
      write(File.join(dir,'scene-'+role,'dependency-pair-review-required.json'),pair)
      return {'state'=>'awaiting-dependent-pair-review','automaticCompositionAllowed'=>false,'newModelCalls'=>0,'jobHash'=>job,'pendingRole'=>role}
     end
    end
   end
   raise 'comparison requires distinct scene outputs' if scenes.size>1&&scenes.map{|s|s['sha256']}.uniq.size!=scenes.size
   fixture=origins.any?{|s|s.to_s.start_with?('offline-fixture:')}
   result.merge('state'=>'analysis-ready-for-local-composition','jobHash'=>job,'options'=>frozen['options'],'productHash'=>frozen.dig('binding','productHash'),'outputSize'=>frozen.dig('trace','expectedDimensions'),'scenes'=>scenes,'analysisOrigin'=>fixture ? 'offline-fixture:historical-response-current-input-pipeline' : 'current-request-model-response','newModelCalls'=>0,'finalPackageCacheRead'=>false,'currentInputPipeline'=>true,'sceneQuality'=>{'visualAcceptance'=>fixture ? 'offline-fixture-not-production-acceptance' : (development_review ? 'development-pixel-review' : 'not-evaluated'),'warnings'=>warnings,'humanPreapprovalRequired'=>development_review&&!fixture,'developmentPixelReviewPassed'=>development_review&&!fixture,'unattendedVisualGuarantee'=>false,'bindingValidated'=>true,'pairedMapping'=>'shared-uniform-contain-all-pixels'},'binding'=>{'sourceHash'=>result['sourceHash'],'analysisResponseHash'=>result['analysisResponseHash'],'layoutHash'=>Digest::SHA256.hexdigest(JSON.generate(normalized(proposal['layout']))),'sourceStructureHash'=>Digest::SHA256.hexdigest(JSON.generate(normalized(proposal['sourceStructure']))),'outputSize'=>frozen.dig('trace','expectedDimensions'),'sceneHashes'=>scenes.map{|s|s['sha256']}})
  end
 end
 # Deliberately only enabled by --mock --scenario current-input. Never available in live.
 def self.fixture_transport(file, allow_synthetic:false, source_hash:nil)
  config=JSON.parse(File.read(file))
  return nil if source_hash && !config.key?(source_hash) # No fixture: prepare only, never substitute another source.
  # Validate before run can resume cached stage receipts. Synthetic observations
  # must never be presented as reconstruction of an ordinary user upload.
  unless allow_synthetic
   (source_hash ? [config.fetch(source_hash)] : config.values).each do |spec|
    raise "离线结构测试素材不能作为参考图重构结果；缺少与当前原图一致的源结构分析，已停止合成（未调用模型）。" unless spec['usage']=='recorded-reference-observation'
   end
  end
  lambda do |plan,stage|
   spec=config.fetch(plan.dig('binding','sourceHash'));path=spec.fetch(stage)
   raw=if stage=='analysis';File.binread(path);else;b=File.binread(path);JSON.generate({'modelVersion'=>GenerateContentAdapter::MODEL,'candidates'=>[{'finishReason'=>'STOP','content'=>{'parts'=>[{'inlineData'=>{'mimeType'=>'image/png','data'=>Base64.strict_encode64(b)}}]}}],'usageMetadata'=>{'promptTokenCount'=>100,'candidatesTokenCount'=>100,'totalTokenCount'=>200}});end
   [200,raw,'offline-fixture:historical-analysis-and-generated-background']
  end
 end
end
