require_relative 'fresh-analysis-flow'
require_relative 'analysis-observations-v2'
module FreshAnalysisIntake
 ROOT=File.join(__dir__,'reviewed-analysis-inputs')
 def self.prepare(frozen,revision=nil)
  raise 'unsupported observation revision' unless [nil,2].include?(revision)
  revision==2 ? AnalysisObservationsV2.prepare(frozen) : FreshAnalysisFlow.prepare(frozen)
 end
 def self.register_response(frozen:, raw:, scenes:, response_request_hash:, directory: ROOT, analysis_revision: nil)
  prepared=prepare(frozen,analysis_revision)
  raise 'analysis response request binding changed' unless response_request_hash==prepared.dig('plan','binding','requestHash')
  validated=FreshAnalysisFlow.consume(prepared,200,raw);raise 'analysis response incomplete' unless validated['proposal']
  scenes.each{|a|raise 'scene not approved clean material' unless a['cleanSceneReviewed']==true && Digest::SHA256.file(a.fetch('path')).hexdigest==a['sha256']}
  FileUtils.mkdir_p(directory);hash=Digest::SHA256.hexdigest(raw);path=File.join(directory,hash+'.response.json');File.binwrite(path,raw)
  spec={'sourceHash'=>frozen.dig('binding','sourceHash'),'responseFile'=>path,'responseHash'=>hash,'analysisRequestHash'=>response_request_hash,'analysisOrigin'=>'request-bound-analysis-response','scenes'=>scenes,'replayFixture'=>false,'analysisRevision'=>analysis_revision}
  target=File.join(directory,spec['sourceHash']+'.json');File.write(target+'.tmp',JSON.pretty_generate(spec));File.rename(target+'.tmp',target);spec
 end
 # Explicitly reviewed local recompositions do not masquerade as fresh model responses.
 # Exact current options/source/product/output and every scene byte remain bound.
 def self.reviewed_local(frozen,directory:File.join(__dir__,'reviewed-local-compositions'))
  file=File.join(directory,frozen.fetch('binding').fetch('requestHash')+'.json');return nil unless File.file?(file)
  record=JSON.parse(File.read(file));hash=record.delete('recordHash')
  raise 'reviewed local record changed' unless Digest::SHA256.hexdigest(JSON.generate(record))==hash
  c=record.fetch('continuation');raise 'reviewed local input mismatch' unless record['version']=='reviewed-local-composition-1'&&record['requestHash']==frozen.dig('binding','requestHash')&&c['options']==frozen['options']&&c['sourceHash']==frozen.dig('binding','sourceHash')&&c['productHash']==frozen.dig('binding','productHash')&&c['outputSize']==frozen.dig('trace','expectedDimensions')
  raise 'reviewed policy missing' unless c['contentPolicyVersion']==ContentSelection::VERSION&&record['visualReview']=='reviewed-with-disclosed-lighting-limit'&&c['newModelCalls']==0
  c.fetch('scenes').each{|a|raise 'reviewed scene bytes changed' unless Digest::SHA256.hexdigest(Base64.strict_decode64(a.fetch('base64')))==a['sha256']}
  c.merge('candidateOnly'=>false,'reviewedLocalRecordHash'=>hash,'analysisOrigin'=>'reviewed-local-recomposition-of-cached-response')
 end
 def self.continue(frozen,exact_only:false,directory:ROOT)
  local=reviewed_local(frozen);return local if local
  h=frozen.dig('binding','sourceHash');file=File.join(directory,h+'.json');return nil unless File.file?(file)
  spec=JSON.parse(File.read(file));return nil if exact_only && spec['replayFixture']==true;raise 'analysis input source mismatch' unless spec['sourceHash']==h
  raw=File.binread(spec.fetch('responseFile'));raise 'analysis response bytes changed' unless Digest::SHA256.hexdigest(raw)==spec['responseHash']
  prepared=prepare(frozen,spec['analysisRevision'])
  return nil if exact_only && spec['analysisRequestHash']!=prepared.dig('plan','binding','requestHash')
  unless spec['replayFixture']==true && spec['analysisOrigin']=='historical-raw-analysis-with-explicit-controlled-source-structure-variant'
   raise 'analysis response request binding changed' unless spec['analysisRequestHash']==prepared.dig('plan','binding','requestHash')
  end
  result=FreshAnalysisFlow.consume(prepared,200,raw);return result unless result['proposal']
  scenes=spec.fetch('scenes').map do |a|
   bytes=File.binread(a.fetch('path'));raise 'scene not approved clean material' unless a['cleanSceneReviewed']==true&&Digest::SHA256.hexdigest(bytes)==a['sha256']
   {'role'=>a['role'],'base64'=>Base64.strict_encode64(bytes),'mime'=>a['mime'],'sha256'=>a['sha256'],'protectedEvidenceBounds'=>a['protectedEvidenceBounds'],'evidenceReviewHash'=>a['evidenceReviewHash']}
  end
  result.merge('state'=>'analysis-ready-for-local-composition','options'=>frozen['options'],'productHash'=>frozen['binding']['productHash'],'outputSize'=>frozen['trace']['expectedDimensions'],'scenes'=>scenes,'analysisOrigin'=>spec.fetch('analysisOrigin'),'newModelCalls'=>0,'finalPackageCacheRead'=>false,'visualAcceptance'=>'not-evaluated')
 end
end
