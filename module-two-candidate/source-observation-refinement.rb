# Optional bounded pixel/OCR refinement. Never changes product identity or copy.
require_relative 'local-source-structure'
module SourceObservationRefinement
 def self.apply(reference,value,source_hash)
  raise 'refinement source mismatch' unless Digest::SHA256.hexdigest(reference)==source_hash
  result=Marshal.load(Marshal.dump(value));prior=result.fetch('sourceStructure');panels=prior.fetch('panels')
  # Text measurement applies to any layout; strip measurement has a narrower scope.
  strips=!panels.empty?&&panels.all?{|p|p['labelBounds']&&p.dig('bounds','width')>=result.dig('sourceGeometry','width')*0.9}
  measured=LocalSourceStructure.observe(reference,result,text_only:!strips)
  if strips
   raise 'refinement panel inventory differs' unless measured['panels'].size==panels.size
   # Bind by unique source label identity, never guessed panel order.
   mapping={}
   measured['panels'].each do |p|
    ids=measured['textGroups'].select{|g|g['owner']==p['id']&&g['placement']=='label'}.flat_map{|g|g['blockIds']}.sort
    matches=panels.select{|old|prior['textGroups'].select{|g|g['owner']==old['id']&&g['placement']=='label'}.flat_map{|g|g['blockIds']}.sort==ids}
    raise 'refinement label association ambiguous' unless !ids.empty?&&matches.size==1
    mapping[p['id']]=matches[0]
   end
   raise 'refinement panel mapping duplicated' unless mapping.values.map{|p|p['id']}.uniq.size==panels.size
   measured['textGroups'].each{|g|g['owner']=mapping.fetch(g['owner'])['id'] unless g['owner']=='canvas'}
   measured['panels'].each{|p|old=mapping.fetch(p['id']);p['id']=old['id'];p['sceneRole']=old['sceneRole']}
  else
   measured['panels']=panels
   measured['textGroups'].each do |g|
    old=prior['textGroups'].find{|x|x['blockIds']==g['blockIds']};raise 'refinement source group ambiguous' unless old
    g['owner']=old['owner'];g['placement']=old['placement']
   end
  end
  # The local strip detector is not a product classifier: never turn a positive flag off.
  measured['productPresent']=prior['productPresent'];measured['productVisibleBounds']=prior['productVisibleBounds'];measured['decorations']||=prior.fetch('decorations',[])
  measured['textGroups'].each do |g|
   old=prior['textGroups'].find{|x|x['blockIds']==g['blockIds']}
   unless g['colorEvidence']
    %w[color fillStops fillDirection].each{|k|g[k]=old[k] if old&&old.key?(k)}
   end
   g.delete('weightEvidence') if g.dig('colorEvidence','method').to_s.start_with?('chromatic-')
   g['weight']=old['weight'] if old&&!g['weightEvidence']
   %w[italic outline].each{|k|g[k]=old[k] if old&&old.key?(k)}
   g['fillStops']||=[];g['outline']||={'color'=>'#000000','width'=>0}
   result['evidence']['sourceBlocks'].find{|b|g['blockIds']==[b['id']]}['sourceBox']=g['bounds'].dup
  end
  result['sourceStructure']=measured
  [result,{'state'=>measured['observationEvidence'].fetch('unresolvedTextBlocks',[]).empty? ? 'locally-refined' : 'partially-refined','unresolvedTextBlocks'=>measured['observationEvidence'].fetch('unresolvedTextBlocks',[]),'sourceHash'=>source_hash,'method'=>measured['observationEvidence']['method'],'panelsRefined'=>strips,'productClassificationChanged'=>false,'copyChanged'=>false,'newModelCalls'=>0}]
 rescue StandardError=>e
  raise if e.message.include?('SOURCE_DECORATION_UNRESOLVED')
  raise if Digest::SHA256.hexdigest(reference)!=source_hash
  [Marshal.load(Marshal.dump(value)),{'state'=>'not-refined','sourceHash'=>source_hash,'reason'=>e.message,'newModelCalls'=>0}]
 end
end
