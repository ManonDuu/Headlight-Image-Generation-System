# Explicit offline reception of same-source historical semantic/scene records.
# No generated-final cache, synthetic source structure, response wrapping or model dispatch.
module LocalHistoricalContinuation
 def self.run(frozen,reference,spec)
  source=Digest::SHA256.hexdigest(reference);raise 'historical reference mismatch' unless source==spec.fetch('sourceHash')
  raw=File.binread(spec.fetch('semanticFile'));raise 'historical semantic bytes changed' unless Digest::SHA256.hexdigest(raw)==spec.fetch('semanticHash')
  original=JSON.parse(raw);observed=Marshal.load(Marshal.dump(original));observed['_locallyOmittedBlockIds']=spec.fetch('copyResolutions',{}).select{|_,v|v['action']=='remove'}.keys;structure=LocalSourceStructure.observe(reference,observed,inventory:spec['panelInventory'])
  resolved=CopyElementResolution.process(original,frozen['options'],frozen.dig('trace','expectedDimensions'),resolutions:spec.fetch('copyResolutions',{}));raise 'historical copy unresolved' unless resolved['pending'].empty?
  # Use the same canonical mode/precision contract as received model analyses.
  # Otherwise a later scene plan rejects this locally resolved layout as changed.
  resolved['candidate']['text'].each{|t|t.delete('mode')}
  resolved['candidate'].delete('sourceStructure');resolved['candidate'].delete('productSlot')
  resolved['candidate']=ReferenceProvider.layout(resolved['candidate'],frozen)
  proposal={'layout'=>resolved['candidate'],'copyDecisions'=>resolved['decisions'],'sourceStructure'=>structure};SourceStructure.validate(structure,proposal['layout'],product:false)
  scenes=spec.fetch('scenes').map do |s|
   b=File.binread(s.fetch('file'));raise 'historical scene bytes changed' unless Digest::SHA256.hexdigest(b)==s.fetch('sha256')
   s.reject{|k,_|k=='file'}.merge('base64'=>Base64.strict_encode64(b))
  end
  image_skill=spec['sceneOrigin']=='main-thread-image-skill'
  if image_skill
   review=spec.fetch('sceneReview');raise 'scene review binding mismatch' unless review['sourceHash']==source&&review['sceneHashes']==scenes.map{|s|s['sha256']}&&review['actualPixelsViewed']&&review['cleanDecorationFree']
  end
  warning=image_skill ? '主对话 image skill 合成场景；不是实测照明数据，也不代表 Gemini 接口已通过。' : '同源历史背景离线联调，未生成新背景；场景像素未涂抹，保留的旧装饰残留不作为干净背景验收。'
  binding={'sourceHash'=>source,'analysisResponseHash'=>Digest::SHA256.hexdigest(raw),'layoutHash'=>Digest::SHA256.hexdigest(JSON.generate(CurrentInputPipeline.normalized(proposal['layout']))),'sourceStructureHash'=>Digest::SHA256.hexdigest(JSON.generate(CurrentInputPipeline.normalized(structure))),'sceneHashes'=>scenes.map{|s|s['sha256']},'outputSize'=>frozen.dig('trace','expectedDimensions')}
  {'state'=>'analysis-ready-for-local-composition','jobHash'=>frozen.dig('binding','requestHash'),'sourceHash'=>source,'productHash'=>nil,'analysisResponseHash'=>binding['analysisResponseHash'],'proposal'=>proposal,'binding'=>binding,'currentInputPipeline'=>true,'options'=>frozen['options'],'outputSize'=>binding['outputSize'],'scenes'=>scenes,'analysisOrigin'=>'offline-historical-same-source-semantics-plus-native-observations','newModelCalls'=>0,'finalPackageCacheRead'=>false,'sceneQuality'=>{'visualAcceptance'=>'not-evaluated','warnings'=>[warning],'historicalSceneReplay'=>!image_skill,'sceneOrigin'=>spec['sceneOrigin']||'historical-replay','sceneReview'=>spec['sceneReview'],'syntheticStructure'=>false,'pixelsPainted'=>false}}
 end
end
