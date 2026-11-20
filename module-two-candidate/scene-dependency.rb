# Host-owned, source-bound evidence; never infer dependencies from panel count/order.
# Only lighting comparisons are implemented. Weather and unknown relationships stay independent.
require 'json'
require 'digest'
require 'base64'
module SceneDependency
 VERSION='scene-dependency-1'
 CHECKS=%w[actualReferencePixelsViewed sameEnvironment sameCamera lightingOnly].freeze
 PAIR_CHECKS=%w[actualBothPixelsViewed sameRoadAndTopology sameObjectsAndPositions sameCameraAndPerspective intendedLightingDifference noOverlayCopyOrFrames].freeze
 def self.hash(value);Digest::SHA256.hexdigest(JSON.generate(CurrentInputPipeline.normalized(value)));end
 def self.validate_relations(relations,frozen,proposal)
  raise 'DEPENDENCY_RELATIONS_INVALID' unless relations.is_a?(Array)
  panels=proposal['sourceStructure']['panels'];roles=panels.map{|p|p['sceneRole']}
  raise 'DEPENDENCY_TARGET_DUPLICATED' unless relations.map{|r|r['targetRole']}.uniq.size==relations.size
  relations.each do |r|
   raise 'DEPENDENCY_EVIDENCE_UNBOUND' unless r['version']==VERSION&&r['sourceHash']==frozen.dig('binding','sourceHash')&&r['sourceStructureHash']==hash(proposal['sourceStructure'])
   raise 'DEPENDENCY_KIND_UNSUPPORTED' unless r['kind']=='same-environment-lighting'&&CHECKS.all?{|k|r.dig('checks',k)==true}
   a,b=roles.index(r['parentRole']),roles.index(r['targetRole']);raise 'DEPENDENCY_ORDER_OR_CYCLE' unless a&&b&&a<b
   %w[parent target].each do |side|
    panel=panels.find{|p|p['sceneRole']==r[side+'Role']};ids=proposal['sourceStructure']['textGroups'].select{|g|g['owner']==panel['id']&&g['placement']=='label'}.flat_map{|g|g['blockIds']}.sort
    raise 'DEPENDENCY_LABEL_EVIDENCE_MISSING' unless !ids.empty?&&r[side+'LabelBlockIds']==ids
   end
   raise 'DEPENDENCY_CONDITION_INVALID' unless %w[warmer-shorter-dimmer cooler-longer-brighter].include?(r['lightingChange'])
  end
  relations
 end
 def self.prepare(independent,relation,parent)
  raise 'DEPENDENCY_PARENT_MISSING' unless parent&&parent['role']==relation['parentRole']
  raise 'DEPENDENCY_PARENT_NOT_REVIEWED' unless parent['developmentPixelReviewPassed']==true&&parent['newEnvironmentReviewed']==true&&parent['requestHash']&&parent['responseHash']
  bytes=Base64.strict_decode64(parent.fetch('base64'));raise 'DEPENDENCY_PARENT_BYTES_CHANGED' unless Digest::SHA256.hexdigest(bytes)==parent['sha256']
  raise 'DEPENDENCY_PARENT_DIMENSIONS_CHANGED' unless parent['dimensions']==independent.dig('binding','sceneDimensions')
  raise 'DEPENDENCY_PARENT_MIME_INVALID' unless %w[image/jpeg image/png].include?(parent['mime'])
  change=relation['lightingChange']=='warmer-shorter-dimmer' ? 'warmer halogen-colored headlights with a shorter, narrower illuminated reach and dimmer distant illumination' : 'cooler white headlights with a longer, broader illuminated reach and brighter distant illumination'
  body=JSON.parse(independent['body']);size=parent['dimensions'].join('x')
  prompt="Edit the SINGLE attached image. It is the already generated, reviewed NEW environment and is the sole geometry authority. Do not reconstruct another environment. Change ONLY the headlight illumination to #{change}. Preserve every road edge and curve, surface structure, building, tree, foliage mass, fence, wall, terrain, hood and object at the same image coordinates. Keep camera position, viewpoint, perspective, horizon, framing and lens unchanged. Relight surfaces naturally; retain visible structure where illumination permits. Do not achieve this through a uniform dark overlay or global exposure filter. No crop, zoom, mirror, new objects, removed objects or compositional redesign. Do not add text, logos, labels, frames, arrows or products. Return exactly one full-bleed #{size} image, same aspect ratio and 2K. The condition change is qualitative, not a measured performance claim."
  # One image only: the approved generated parent, not the original poster or rejected scene.
  body['contents']=[{'role'=>'user','parts'=>[{'text'=>prompt},{'inlineData'=>{'mimeType'=>parent['mime'],'data'=>parent['base64']}}]}]
  encoded=JSON.generate(body);p=Marshal.load(Marshal.dump(independent));p['body']=encoded
  p['binding'].merge!('requestHash'=>Digest::SHA256.hexdigest(encoded),'inputSceneHash'=>parent['sha256'],'dependency'=>{'version'=>VERSION,'relationHash'=>hash(relation),'parentRole'=>parent['role'],'parentRequestHash'=>parent['requestHash'],'parentResponseHash'=>parent['responseHash'],'parentSceneHash'=>parent['sha256'],'targetRole'=>relation['targetRole']},'analysisCalls'=>0,'maxRequests'=>1,'retries'=>0,'liveEnabled'=>false)
  p
 end
 def self.check_pair(path,relation,parent,child,layout)
  binding={'relationHash'=>hash(relation),'parentSceneHash'=>parent['sha256'],'childSceneHash'=>child['sha256'],'layoutHash'=>hash(layout)}
  return {'accepted'=>false,'binding'=>binding,'checksRequired'=>PAIR_CHECKS} unless File.file?(path)
  r=JSON.parse(File.read(path));raise 'DEPENDENCY_PAIR_REVIEW_UNBOUND' unless r['binding']==binding
  raise 'DEPENDENCY_PAIR_REJECTED' if r['decision']=='reject'
  {'accepted'=>r['decision']=='accept'&&PAIR_CHECKS.all?{|k|r.dig('checks',k)==true},'binding'=>binding,'checksRequired'=>PAIR_CHECKS}
 end
end
