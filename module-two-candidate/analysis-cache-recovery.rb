# Explicit trusted recovery of a returned analysis after a local post-processing fix.
# Keeps the failed job untouched; never dispatches or deletes a stop record.
require_relative 'current-input-pipeline'
module AnalysisCacheRecovery
 CODE_FILES=%w[analysis-cache-recovery.rb current-input-session.rb current-input-pipeline.rb local-reference-ocr.rb analysis-output-contract.rb render-association-resolution.rb reference-provider.rb copy-element-resolution.rb source-observation-refinement.rb local-reference-ocr.js local-source-structure.rb observe-reference-strips.py source-decoration-pixels.py source-structure.rb fresh-analysis-flow.rb automatic-analysis-compose.js].freeze
 def self.code_hashes;CODE_FILES.to_h{|n|[n,Digest::SHA256.file(File.join(__dir__,n)).hexdigest]};end
 def self.prepare(frozen,config,root:)
  FileUtils.mkdir_p(root)
  File.open(File.join(root,'analysis-recovery.lock'),'a'){|lock|lock.flock(File::LOCK_EX);prepare_locked(frozen,config,root:root)}
 end
 def self.prepare_locked(frozen,config,root:)
  r=config.fetch('analysisRecovery');raise 'recovery is scenes only' unless config['fullValidation']==true&&config['releaseScenes']==true&&r['codeHashes']==code_hashes
  original=config.fetch('analysisRequestHash');raise 'invalid recovery hash' unless original.match?(/\A[0-9a-f]{64}\z/)
  old=File.join(root,original);raise 'recovery requires original stopped record' unless File.file?(File.join(old,'session-stop.json'))
  p=FreshAnalysisIntake.prepare(frozen,2);raise 'original analysis request changed' unless p.dig('plan','binding','requestHash')==original
  ar=CurrentInputPipeline.request(old,p['plan'],'analysis',nil);raise 'returned analysis missing' unless ar&&ar[0]==200
  raise 'recovery response hash mismatch' unless Digest::SHA256.hexdigest(ar[1])==r['responseHash']
  result=FreshAnalysisFlow.consume(p,ar[0],ar[1]);proposal=result.fetch('proposal')
  raise 'recovery layout changed' unless Digest::SHA256.hexdigest(JSON.generate(CurrentInputPipeline.normalized(proposal['layout'])))==r['layoutHash']
  raise 'recovery source structure changed' unless Digest::SHA256.hexdigest(JSON.generate(CurrentInputPipeline.normalized(proposal['sourceStructure'])))==r['sourceStructureHash']
  key=Digest::SHA256.hexdigest(JSON.generate(CurrentInputPipeline.normalized(r.merge('originalAnalysisRequestHash'=>original))))
  dir=File.join(root,key);FileUtils.mkdir_p(dir)
  CurrentInputPipeline.request(dir,p['plan'],'analysis',nil)
  binding=JSON.parse(File.read(File.join(dir,'analysis','plan.json')))['binding'];receipt=File.join(dir,'analysis','receipt.json')
  if File.file?(receipt)
   CurrentInputPipeline.request(dir,p['plan'],'analysis',nil)
  else
   File.binwrite(File.join(dir,'analysis','response.raw.json'),ar[1]);CurrentInputPipeline.write(receipt,{'binding'=>binding,'httpStatus'=>200,'responseHash'=>r['responseHash'],'origin'=>ar[2],'recoveredFromJob'=>original,'offlineRepairCodeHashes'=>r['codeHashes']})
  end
  CurrentInputPipeline.write(File.join(dir,'analysis-recovery.json'),{'originalJob'=>original,'originalFailurePreserved'=>true,'newModelCalls'=>0,'audit'=>r})
  key
 end
end
