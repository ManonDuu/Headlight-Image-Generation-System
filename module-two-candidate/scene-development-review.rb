# Local development acceptance, not a model or unattended visual-quality claim.
# Review contains booleans only: never copy, replacement analysis or coordinates.
require 'json'
require 'digest'
module SceneDevelopmentReview
 CHECKS=%w[actualPixelsViewed noOverlayCopyOrFrames coreEvidencePresent safeForLocalComposition].freeze
 def self.binding(source_hash:,scene_hash:,layout:,output_size:,scene_size:,role:)
  {'version'=>'scene-development-review-1','sourceHash'=>source_hash,'sceneHash'=>scene_hash,
   'layoutHash'=>Digest::SHA256.hexdigest(JSON.generate(CurrentInputPipeline.normalized(layout))),
   'outputSize'=>output_size,'sceneSize'=>scene_size,'sceneRole'=>role}
 end
 def self.check(path,expected)
  return {'accepted'=>false,'state'=>'awaiting-development-scene-review'} unless File.file?(path)
  r=JSON.parse(File.read(path))
  raise 'development scene review binding changed' unless r['binding']==expected
  raise 'development scene review has unexpected fields' unless (r.keys-%w[binding checks decision note]).empty?
  raise 'development scene review checks invalid' unless r['checks'].is_a?(Hash)&&(r['checks'].keys-CHECKS).empty?
  raise 'scene rejected by development pixel review; no further generation' if r['decision']=='reject'
  ok=r['decision']=='accept'&&CHECKS.all?{|k|r['checks'][k]==true}
  {'accepted'=>ok,'state'=>ok ? 'development-pixel-review-accepted' : 'awaiting-development-scene-review'}
 end
end
