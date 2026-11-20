# Explicit local visual analysis input; no provider envelope, token usage or model impersonation.
require_relative 'current-input-pipeline'
require_relative 'scene-overlay-contract'
module LocalAssistantAnalysis
 def self.run(frozen,reference,spec)
  source=Digest::SHA256.hexdigest(reference)
  raise 'assistant source binding mismatch' unless spec['sourceHash']==source&&frozen.dig('binding','sourceHash')==source&&spec['frozenRequestHash']==frozen.dig('binding','requestHash')
  raw=File.binread(spec.fetch('analysisFile'));raise 'assistant analysis hash mismatch' unless Digest::SHA256.hexdigest(raw)==spec['analysisHash']
  doc=JSON.parse(raw);provenance=doc.fetch('provenance')
  raise 'assistant provenance missing' unless provenance['origin']=='current-assistant-visual-analysis'&&provenance['actualPixelsViewed']==true&&provenance['supplierValidated']==false&&provenance['sourceHash']==source
  render_frozen=Marshal.load(Marshal.dump(frozen))
  if frozen.dig('options','output','aspectRatio')=='follow-reference'
   sw,sh=InputImage.inspect(reference)['dimensions'];unit=sw.gcd(sh);rw,rh=sw/unit,sh/unit;factor=[1,(2048.0/[rw,rh].max).floor].max
   render_frozen['trace']['expectedDimensions']=[rw*factor,rh*factor]
  end
  value=doc.fetch('analysis');structure=value.fetch('sourceStructure');candidate=Marshal.load(Marshal.dump(value));candidate.delete('sourceStructure')
  resolved=CopyElementResolution.process(candidate,frozen['options'],render_frozen.dig('trace','expectedDimensions'),resolutions:doc.fetch('copyResolutions'))
  raise 'assistant copy unresolved' unless resolved['pending'].empty?
  contract=AnalysisOutputContract.process(resolved['candidate'],frozen['options'],InputImage.inspect(reference)['dimensions'],render_frozen.dig('trace','expectedDimensions'))
  raise 'assistant contract unresolved' if contract['state']=='awaiting-contract-review'
  layout=ReferenceProvider.layout(contract.fetch('candidate'),render_frozen);AnalysisOutputContract.validate_render!(layout['text'],frozen['options'])
  audit=CopyEvidencePolicy.audit(layout['evidence'],frozen['options'],layout['text']);SourceStructure.validate(structure,layout,product:!!frozen.dig('binding','productHash'))
  scenes=spec.fetch('scenes').map do |s|
   b=File.binread(s.fetch('file'));raise 'assistant scene hash mismatch' unless Digest::SHA256.hexdigest(b)==s['sha256']
   raise 'assistant scene review missing' unless s['actualPixelsViewed']==true&&s['overlayTextRemoved']==true
   s.reject{|k,_|k=='file'}.merge('base64'=>Base64.strict_encode64(b))
  end
  raise 'assistant visual review scene binding mismatch' unless (provenance['sceneHashes']||[provenance['sceneHash']])==scenes.map{|s|s['sha256']}
  expected=structure['panels'].empty? ? ['single'] : structure['panels'].map{|p|p['sceneRole']}
  raise 'assistant scene roles mismatch' unless scenes.map{|s|s['role']}.sort==expected.sort
  overlays=SceneOverlayContract.validate(doc['sceneOverlays'],source,scenes)
  proposal={'layout'=>layout,'sourceStructure'=>structure,'copyDecisions'=>resolved['decisions'],'warnings'=>[audit]}
  binding={'sourceHash'=>source,'analysisResponseHash'=>spec['analysisHash'],'layoutHash'=>Digest::SHA256.hexdigest(JSON.generate(CurrentInputPipeline.normalized(layout))),'sourceStructureHash'=>Digest::SHA256.hexdigest(JSON.generate(CurrentInputPipeline.normalized(structure))),'sceneHashes'=>scenes.map{|s|s['sha256']},'outputSize'=>render_frozen.dig('trace','expectedDimensions'),'sceneOverlayHash'=>overlays&&Digest::SHA256.hexdigest(JSON.generate(CurrentInputPipeline.normalized(overlays)))}
  {'state'=>'analysis-ready-for-local-composition','jobHash'=>frozen.dig('binding','requestHash'),'sourceHash'=>source,'productHash'=>frozen.dig('binding','productHash'),'analysisResponseHash'=>spec['analysisHash'],'proposal'=>proposal,'binding'=>binding,'currentInputPipeline'=>true,'options'=>frozen['options'],'outputSize'=>binding['outputSize'],'scenes'=>scenes,'sceneOverlays'=>overlays,'analysisOrigin'=>provenance['origin'],'analysisProvenance'=>provenance,'newModelCalls'=>0,'finalPackageCacheRead'=>false,'sceneQuality'=>{'visualAcceptance'=>'not-evaluated','sceneOrigin'=>'main-thread-image-skill','warnings'=>['当前助手视觉分析＋主对话 image skill 场景，仅验证通用契约与本地渲染；Gemini供应商链路未验证。','私有视觉排版测试，不是实测光学、耐候或产品性能证据。']}}
 end
end
