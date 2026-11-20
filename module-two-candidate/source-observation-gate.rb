require 'tmpdir'
require 'open3'
module SourceObservationGate
 def self.audit(reference,observed,refinement,retained_ids)
  pending=[]
  if !refinement || refinement['state']=='not-refined'
   pending<<{'code'=>'SOURCE_LOCAL_GEOMETRY_UNVERIFIED','reason'=>refinement&&refinement['reason']}
  elsif (Array(refinement['unresolvedTextBlocks'])&retained_ids).any?
   pending<<{'code'=>'SOURCE_RETAINED_TEXT_GEOMETRY_UNVERIFIED'}
  end
  # Text-only corroboration cannot validate arbitrary scene segmentation.
  if observed.dig('sourceStructure','panels').any? && (!refinement||refinement['panelsRefined']!=true)
   pending<<{'code'=>'SOURCE_SCENE_GEOMETRY_UNVERIFIED'}
  end
  coverage=nil
  Dir.mktmpdir('source-coverage-') do |d|
   File.binwrite(d+'/source.image',reference);File.write(d+'/observed.json',JSON.generate(observed))
   raw,err,status=Open3.capture3('python3',File.join(__dir__,'source-scene-coverage.py'),d+'/source.image',d+'/observed.json')
   if status.success?
    coverage=JSON.parse(raw)
    pending<<{'code'=>'SOURCE_SCENE_COVERAGE_PENDING','reason'=>'Textured source pixels lie outside recorded regions; this does not classify them or authorize removal.'} if coverage['state']=='unexplained-raster-review-required'
   else
    pending<<{'code'=>'SOURCE_RASTER_COVERAGE_UNVERIFIED'}
   end
  end
  {'state'=>pending.empty? ? 'locally-corroborated-with-limited-scope' : 'pending','pending'=>pending,'coverage'=>coverage,'sourceHash'=>Digest::SHA256.hexdigest(reference),'newModelCalls'=>0,'automaticSemanticCompleteness'=>false}
 end
end
