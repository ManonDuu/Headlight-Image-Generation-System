require_relative 'product-asset-provider'
out=File.join(__dir__,'diagnostics/real-scenes');FileUtils.mkdir_p(out)
old=JSON.parse(File.read('diagnostics/two-backgrounds-20261018/step1-plan.json'));reference=File.binread('diagnostics/final-readiness/deer-road.png')
options=DefaultProductFacts.apply(old['frozen']['options'].merge('mode'=>'preserve-reference'))
frozen=DirectImagePlan.prepare(reference,nil,options,mock:false)
raw=Marshal.load(Marshal.dump(old['layout']));raw['evidence']['sourceBlocks'].find{|b|b['id']=='block_3'}['meaningUnitIds']<<'f_brand'
processed=PreserveReferenceCopy.process(raw,frozen['options'],frozen['trace']['expectedDimensions']);value=processed['candidate'];value['text'].each{|t|t.delete('mode')};layout=ReferenceProvider.layout(value,frozen)
raise 'unexpected preserved copy' unless layout['text'].map{|t|t['text']}==['ULTRA BRIGHTNESS','OTHER']
audit=JSON.parse(File.read('reference-anchor-audits/'+frozen['binding']['sourceHash']+'/64080305673d3a109bcfab9ab3dbc12376b32be894bdebc22386da3d86598fed.json'))
audit['renderAnchors']=audit['renderAnchors'].select{|a|%w[block_2 block_5].include?(a['blockId'])};audit['renderAnchors'].each_with_index{|a,i|a['renderIndex']=i}
audit['sourceBlocks'].each do |b|
 rw=layout['evidence']['rewrites'].find{|r|r['blockId']==b['id']};next unless rw['action']=='omit'
 b.merge!('state'=>'reviewed-clearance-region','clearanceBox'=>b['ocrBox'],'outputAction'=>'omit','clearanceReview'=>'reviewed','sourceRecognitionReview'=>'manual-pixel-verified','recognizedSourceText'=>b['sourceText'],'omissionReason'=>rw['omissionReason'])
end
audit.merge!('evidencePolicy'=>'retained-and-clearance-v1','layoutHash'=>ReferenceAnchorReview.fingerprint(layout),'nativeLayout'=>layout,'nativeLayoutHash'=>ReferenceAnchorReview.fingerprint(layout),'meaningReview'=>['Original source pixels viewed: retain ULTRA BRIGHTNESS and OTHER verbatim; omit unsupported 800%, numeric specs and unprovided brand. CANBUS default remains in selected facts, not invented as source copy.'],'scope'=>'This reference and preserve-reference layout only; local pixel review on 2026-10-18, not a general detector.')
path=File.join(ReferenceAnchorReview::ROOT,frozen['binding']['sourceHash'],audit['layoutHash']+'.json');File.write(path,JSON.pretty_generate(audit));ReferenceAnchorReview.require!(frozen['binding']['sourceHash'],layout)
w,h=frozen['trace']['expectedDimensions'];k=[w/1122.0,h/1402.0].min;dx=(w-1122*k)/2;dy=(h-1402*k)/2
rect=lambda{|x,y,a,b|{'x'=>dx+x*k,'y'=>dy+y*k,'width'=>a*k,'height'=>b*k}}
assets=%w[led halogen].map do |name|
 bytes=File.binread(out+'/scene-'+name+'.png');meta=InputImage.inspect(bytes);raise 'wrong scene dimensions' unless meta['dimensions']==[1536,1024]
 {'id'=>name,'sha256'=>Digest::SHA256.hexdigest(bytes),'width'=>1536,'height'=>1024,'cleanSceneOnlyReviewed'=>true,'bakedFramesAbsentReviewed'=>true,'cameraAndEvidenceReview'=>'reviewed','protectedEvidenceBounds'=>[{'x'=>740,'y'=>400,'width'=>74,'height'=>78},{'x'=>1276,'y'=>262,'width'=>136,'height'=>280},{'x'=>160,'y'=>475,'width'=>1256,'height'=>363}]}
end
contract={'schemaVersion'=>'deterministic-decoration-1','sourceHash'=>frozen['binding']['sourceHash'],'textLayoutHash'=>ReferenceAnchorReview.fingerprint(layout),'canvas'=>{'width'=>w,'height'=>h,'backgroundFill'=>'#000000'},'sceneAssets'=>assets,'comparisonGroups'=>[{'id'=>'lighting','panelIds'=>%w[upper lower],'sharedSceneCoordinateSystem'=>'same-generated-farm-camera-reviewed-pair','sharedUniformScale'=>1033.0/1536*k,'sharedTranslationInPanelCoordinates'=>{'x'=>0,'y'=>-90*k},'mappingReview'=>'reviewed'}],'panels'=>[['upper','led',204,597,'#ffdc00'],['lower','halogen',825,539,'#737373']].map{|id,asset,y,height,color|{'id'=>id,'outerRect'=>rect.call(45,y,1033,height),'sceneViewportRect'=>rect.call(45,y,1033,height),'cornerRadius'=>19*k,'borderStyle'=>{'width'=>3*k,'color'=>color},'comparisonGroupId'=>'lighting','sceneAssetId'=>asset}},'labelContainers'=>[{'id'=>'header','panelId'=>nil,'rect'=>rect.call(0,0,1122,203),'cornerRadius'=>0,'fillStyle'=>'#000000','retainedTextIndices'=>[0]},{'id'=>'upper-label','panelId'=>'upper','rect'=>rect.call(48,207,270,62),'cornerRadius'=>[0,0,25*k,0],'fillStyle'=>'#ffdc00','retainedTextIndices'=>[]},{'id'=>'lower-label','panelId'=>'lower','rect'=>rect.call(48,828,249,64),'cornerRadius'=>[0,0,25*k,0],'fillStyle'=>'#737373','retainedTextIndices'=>[1]}]}
normalize=lambda{|v|case v;when Hash;v.map{|key,value|[key,normalize.call(value)]}.to_h;when Array;v.map{|value|normalize.call(value)};when Float;v==v.to_i ? v.to_i : v;else;v;end};contract=normalize.call(contract)
{'frozen'=>frozen,'proposal'=>{'layout'=>layout,'warnings'=>[processed]},'contract'=>contract,'anchor-audit'=>audit,'source-map'=>{'scale'=>k,'dx'=>dx,'dy'=>dy}}.each{|name,data|File.write(out+'/'+name+'.json',JSON.pretty_generate(data))}
puts JSON.generate({texts:layout['text'].map{|t|t['text']},options:frozen['options'],outputSize:[w,h],requestHash:frozen['binding']['requestHash'],sharedScale:contract['comparisonGroups'][0]['sharedUniformScale']})
