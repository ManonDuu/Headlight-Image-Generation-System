# A scene-only attestation is local reviewed evidence, never a caller-supplied pass.
require_relative 'background-geometry-review'
module DeterministicDecorationReview
 ROOT=File.join(__dir__,'deterministic-decoration-audits')
 def self.require!(p)
  d=p.fetch('decoration');c=d.fetch('contract');h=ReferenceAnchorReview.fingerprint(c)
  raise 'decoration contract binding mismatch' unless h==d['contractHash']&&c['sourceHash']==p['sourceHash']&&c['textLayoutHash']==ReferenceAnchorReview.fingerprint(p.dig('proposal','layout'))
  binding={'sourceHash'=>p['sourceHash'],'backgroundHash'=>p['backgroundHash'],'layoutHash'=>c['textLayoutHash'],'contractHash'=>h,'outputSize'=>[c.dig('canvas','width'),c.dig('canvas','height')]}
  path=File.join(ROOT,ReferenceAnchorReview.fingerprint(binding)+'.json')
  raise 'decoration requires trusted local scene review' unless File.file?(path)
  review=JSON.parse(File.read(path))
  raise 'decoration scene review mismatch' unless review['binding']==binding&&review['reviewState']=='verified-local-review'&&review['cleanScenesReviewed']==true&&review['evidenceAndMappingReviewed']==true
  action=p.dig('options','module')=='product-replacement'&&p.dig('options','sceneMode')=='keep' ? 'clear-existing-environment' : 'rebuild-environment'
  raise 'selected scene action has not passed local review' unless review['sceneAction']==action&&review['sceneActionVerdict']=='pass'
  c.fetch('sceneAssets').each do |a|
   bytes=Base64.strict_decode64(d.fetch('assets').fetch(a.fetch('id')).fetch('base64'))
   raise 'decoration asset mismatch' unless Digest::SHA256.hexdigest(bytes)==a['sha256']&&InputImage.inspect(bytes)['dimensions']==[a['width'],a['height']]
  end
  review
 end
end
