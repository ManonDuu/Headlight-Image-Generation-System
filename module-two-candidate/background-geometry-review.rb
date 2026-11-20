# Local human-reviewed geometry only. Heuristic detections are candidates, never approval.
require_relative 'reference-anchor-review'
module BackgroundGeometryReview
 ROOT=File.join(__dir__,'background-geometry-audits')
 MESSAGE='背景面板或标签位置尚未通过几何复核，已停止叠字；不会自动移动文字、拉伸面板或覆盖双框。'
 def self.key(source,background,layout,size)
  ReferenceAnchorReview.fingerprint({'sourceHash'=>source,'backgroundHash'=>background,'layoutHash'=>ReferenceAnchorReview.fingerprint(layout),'outputSize'=>size})
 end
 def self.valid?(a,source,background,layout,size)
  return false unless a.is_a?(Hash)&&a['sourceHash']==source&&a['backgroundHash']==background&&a['layoutHash']==ReferenceAnchorReview.fingerprint(layout)&&a['outputSize']==size
  return false unless a['reviewState']=='verified-local-review'&&a['verdict']=='pass'&&a['reviewMethod']=='manual-pixel-geometry'&&a['sourceStructureReviewed']==true&&a['backgroundStructureReviewed']==true&&a['inventoryComplete']==true
  regions=a['regions'];owners=a['textOwners']
  return false unless regions.is_a?(Array)&&owners.is_a?(Array)
  count=regions.count{|r|r['kind']=='panel'}
  return false unless a['sourcePanelCount']==count&&a['backgroundPanelCount']==count&&regions.all?{|r|r['id'].is_a?(String)&&!r['id'].empty?}
  if a['structure']=='unframed'
   return regions.empty?&&owners.empty?&&a['unframedClearanceReviewed']==true
  end
  return false unless a['structure']=='framed'&&regions.any?{|r|r['kind']=='panel'}&&regions.map{|r|r['id']}.uniq.size==regions.size
  valid_edges=lambda do |e|
   e.is_a?(Hash)&&e.keys.sort==%w[bottom left right top]&&e.all?{|k,v|limit=%w[left right].include?(k) ? size[0] : size[1];v.is_a?(Array)&&v.size==2&&v.all?{|n|n.is_a?(Numeric)&&n.finite?}&&v[0]>=0&&v[0]<=v[1]&&v[1]<=limit}&&e['left'][1]<e['right'][0]&&e['top'][1]<e['bottom'][0]
  end
  return false unless regions.all? do |r|
   e=r['expectedEdges'];o=r['observedEdges']
   %w[panel container header].include?(r['kind'])&&r['measurementState']=='reviewed'&&valid_edges.call(e)&&valid_edges.call(o)&&%w[left top right bottom].all?{|k|[e[k][0],o[k][0]].max<=[e[k][1],o[k][1]].min}
  end
  return false unless owners.map{|o|o['renderIndex']}.sort==(0...layout['text'].size).to_a
  owners.all? do |o|
   r=regions.find{|v|v['id']==o['regionId']};b=layout['text'][o['renderIndex']]['box'];e=r&&r['observedEdges']
   o['ownershipReviewed']==true&&e&&b.is_a?(Hash)
  end
 rescue StandardError
  false
 end
 def self.require!(source,background,layout,size)
  path=File.join(ROOT,key(source,background,layout,size)+'.json')
  raise MESSAGE unless File.file?(path)
  a=JSON.parse(File.read(path));raise MESSAGE unless valid?(a,source,background,layout,size);a
 end
end
