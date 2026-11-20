# Offline plans only. Uses the existing layout/copy contract; never dispatches requests.
require_relative 'reference-provider'
require_relative 'background-geometry-review'
require_relative 'deterministic-decoration-review'
module ProductAssetProvider
 VERSION='product-original-assets-20261018.1'
 def self.prepare(frozen,stage='layout-copy',proposal=nil)
  DirectImagePlan.validate(frozen);raise 'product task required' unless frozen.dig('binding','module')=='product-replacement'
  ref=DirectImagePlan.image_part(frozen,'reference');input=Base64.strict_decode64(ref['data'])
  opts=frozen['options'].merge('module'=>'reference-reconstruction','businessSpec'=>DirectImagePlan::SPEC);%w[productName sceneMode].each{|k|opts.delete(k)}
  surrogate=DirectImagePlan.prepare(input,nil,opts,mock:false)
  p=ReferenceProvider.prepare(surrogate,stage,proposal&&proposal.fetch('layout'))
  proposal=proposal.merge('layout'=>p['layout']) if stage=='background'
  body=JSON.parse(p['body']);instruction=body['contents'][0]['parts'][0]['text']
  if stage=='layout-copy'
   slot={'type'=>'object','properties'=>%w[x y width height].map{|k|[k,{'type'=>'number'}]}.to_h,'required'=>%w[x y width height]}
   body['generationConfig']['responseFormat']['text']['schema']['properties']['productSlot']=slot
   body['generationConfig']['responseFormat']['text']['schema']['required']<<'productSlot'
   instruction<<"\nPRODUCT COMPOSITE OVERRIDE: Analyze image 1 solely for scene/layout and eligible overlay copy. The replacement product is composited locally from its original pixels, never redrawn. Return productSlot in OUTPUT pixels: one free, non-cropping rectangle separate from every retained text box, for a uniformly scaled upright product. Transparent image-canvas dimensions are NOT the physical product aspect ratio. Preserve the reference visible-body height occupancy and bottom contact; local alpha measurement determines final uniform scale. Background and text must yield to that occupancy; never shrink the product to solve a text conflict. No rotations or new viewpoint. Keep layout hierarchy but move conflicting text minimally to reserve a large usable product area. Omit source product-specific cooling-fan/chip/performance claims and attached arrows/effects unless supplied user facts support them; do not infer hidden parts. Selected product options: #{JSON.generate(frozen['options'])}."
  else
   compiled=BackgroundSceneContract.compile(frozen,proposal.fetch('layout'),product_slot:proposal.fetch('productSlot'));instruction=compiled['instruction'];p['sceneInputContract']=compiled['contract']
  end
  body['contents'][0]['parts'][0]['text']=instruction;p['body']=JSON.generate(body)
  p['binding']=p['binding'].merge('version'=>VERSION,'productHash'=>frozen.dig('binding','productHash'),'frozenRequestHash'=>frozen.dig('binding','requestHash'),'requestHash'=>Digest::SHA256.hexdigest(p['body']),'productImageSent'=>false)
  p.merge('productFrozen'=>frozen,'referenceAdapter'=>surrogate,'proposal'=>proposal,'liveEnabled'=>false)
 end
 def self.parse_analysis(plan,http,raw,defer_layout:false)
  r,part,_usage=ReferenceProvider.analysis_envelope(http,raw)
  value=ReferenceProvider.decode_analysis(part);slot=value.delete('productSlot');w,h=plan['productFrozen']['trace']['expectedDimensions']
  raise 'invalid product slot' unless slot.is_a?(Hash)&&slot.keys.sort==%w[height width x y]&&slot.values.all?{|n|n.is_a?(Numeric)&&n.finite?}&&slot['x']>=0&&slot['y']>=0&&slot['width']>0&&slot['height']>0&&slot['x']+slot['width']<=w&&slot['y']+slot['height']<=h
  part['text']=JSON.generate(value)
  adapter=ReferenceProvider.prepare(plan['referenceAdapter'],'layout-copy')
  adapter['frozen']=Marshal.load(Marshal.dump(adapter['frozen']))
  adapter['frozen']['options']['module']='product-replacement'
  parsed=ReferenceProvider.parse(adapter,http,JSON.generate(r));raise 'analysis contract needs correction' unless parsed['plan']
  unless defer_layout;parsed['plan']['text'].each{|t|b=t['box'];raise 'product/text overlap' unless b['x']+b['width']<=slot['x']||b['x']>=slot['x']+slot['width']||b['y']+b['height']<=slot['y']||b['y']>=slot['y']+slot['height']};end
  {'layout'=>parsed['plan'],'copyDecisions'=>parsed['copyDecisions'],'sourceStructure'=>parsed['sourceStructure'],'productSlot'=>slot,'warnings'=>[parsed['semanticAudit'],parsed['contractAudit']].compact}
 end
 def self.cache(frozen,root,mock:false)
  path=File.join(root,frozen['binding']['requestHash'],'package.json');return nil unless File.file?(path)
  p=JSON.parse(File.read(path));raise 'fixture cache forbidden' if p['fixtureOnly']&&!mock
  raise 'cache inputs changed' unless p['sourceHash']==frozen.dig('binding','sourceHash')&&p['productHash']==frozen.dig('binding','productHash')&&p['options']==frozen['options']
  bytes=Base64.strict_decode64(p.fetch('background').fetch('base64'));raise 'cache background hash mismatch' unless Digest::SHA256.hexdigest(bytes)==p['backgroundHash']
  expected_origin=p['decoration'] ? 'local-deterministic-decoration' : 'clean-background-only'
  raise 'cache must identify clean-background provenance' unless p['backgroundOrigin']==expected_origin
  p['decorationReview']=DeterministicDecorationReview.require!(p) if p['decoration']
  AnalysisOutputContract.validate_render!(p.fetch('proposal').fetch('layout').fetch('text'),frozen['options'])
  unless p['proposal']['layout']['text'].empty?
   dimensions=InputImage.inspect(bytes,max_bytes:p['decoration'] ? 20*1024*1024 : 4*1024*1024)['dimensions']
   p['geometryAudit']=BackgroundGeometryReview.require!(p['sourceHash'],p['backgroundHash'],p['proposal']['layout'],dimensions)
  end
  p['anchorAudit']=ReferenceAnchorReview.require!(p['sourceHash'],p['proposal']['layout']) if frozen['options']['layoutMode']=='keep-reference'&&!p['proposal']['layout']['text'].empty?
  p
 end
end
module ProductAssetProvider
 # One explicitly authorized batch. No key lookup or network implementation here.
 def self.execute(frozen,root,approval:,transport:,mock:false)
  a=prepare(frozen);raise 'fresh bounded authorization required' unless approval.is_a?(Hash)&&approval['id'].is_a?(String)&&!approval['id'].empty?&&approval['analysisRequestHash']==a['binding']['requestHash']&&approval['maxRequests']==2&&approval['budgetMicroUSD']==280000
  LiveRequestPause.check! unless mock
  folder=File.join(root,frozen['binding']['requestHash']);raise 'attempt exists; never retry' if File.exist?(folder);FileUtils.mkdir_p(File.dirname(folder));Dir.mkdir(folder,0700)
  receipt={'approval'=>approval,'newModelCalls'=>0,'retries'=>0,'state'=>'running','mock'=>mock}
  begin
   File.write(File.join(folder,'analysis-plan.json'),JSON.pretty_generate(a));receipt['newModelCalls']+=1
   http,raw=transport.call(a['binding']['endpoint'],a['body'],{retries:0,timeoutSeconds:120});File.binwrite(File.join(folder,'analysis-response.json'),raw)
   proposal=parse_analysis(a,http,raw);b=prepare(frozen,'background',proposal);File.write(File.join(folder,'background-plan.json'),JSON.pretty_generate(b))
   receipt['newModelCalls']+=1;http,raw=transport.call(b['binding']['endpoint'],b['body'],{retries:0,timeoutSeconds:180});File.binwrite(File.join(folder,'background-response.json'),raw)
   parsed=GenerateContentAdapter.parse(http,raw,expected_dimensions:frozen['trace']['expectedDimensions'])
   candidate={'sourceHash'=>frozen['binding']['sourceHash'],'productHash'=>frozen['binding']['productHash'],'options'=>frozen['options'],'sceneCandidate'=>{'base64'=>Base64.strict_encode64(parsed['bytes']),'mime'=>parsed['outputMime'],'sha256'=>parsed['outputHash'],'dimensions'=>frozen['trace']['expectedDimensions']},'sceneInputContract'=>b['sceneInputContract'],'proposal'=>proposal,'fixtureOnly'=>mock,'compositionAllowed'=>false,'localDecorationRequired'=>true,'visualAcceptance'=>'not-evaluated'}
   File.write(File.join(folder,'scene-candidate.json'),JSON.pretty_generate(candidate));receipt['state']='scene-candidate-awaiting-local-decoration';receipt['sceneHash']=parsed['outputHash'];receipt['compositionAllowed']=false
  rescue=>e
   receipt['state']='stopped';receipt['error']=e.message
  ensure
   File.write(File.join(folder,'receipt.json'),JSON.pretty_generate(receipt))
  end
  receipt
 end
end
