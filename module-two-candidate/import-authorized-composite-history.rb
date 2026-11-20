# Idempotent local import of the already-authorized, already-completed real case.
# No transport, credentials, generation or changes to previous tasks.
require_relative 'bridge-server'
module AuthorizedCompositeHistory
 ID='19943cd47d3b42b02d8c8739'
 def self.import(data)
  root=File.expand_path(__dir__);d=root+'/diagnostics/authorized-background-20261018';a=root+'/diagnostics/compact-analysis-authorized-20261018'
  p=JSON.parse(File.read(d+'/plan.json'));m=JSON.parse(File.read(d+'/composition-manifest.json'));f=p['frozen'];DirectImagePlan.validate(f)
  files={'reference.jpg'=>root+'/assets/amazon-example/reference.jpg','background.jpg'=>d+'/background.jpg','output.png'=>d+'/B0FBFPH2Y8-reference-reconstruction.png'}
  expected={'reference.jpg'=>f['binding']['sourceHash'],'background.jpg'=>m['backgroundHash'],'output.png'=>m['outputHash']}
  files.each{|name,path|raise 'asset hash mismatch' unless Digest::SHA256.file(path).hexdigest==expected[name]}
  manifest=JSON.parse(File.read(root+'/assets/fonts/inter-4.1/manifest.json'));manifest['files'].each{|item|raise 'font/license hash mismatch' unless Digest::SHA256.file(root+'/assets/fonts/inter-4.1/'+item['file']).hexdigest==item['sha256']}
  %w[background-Sentinel_34ec2b52a6188191a6dae1af7ca8a24e compact-analysis-Sentinel_d41e04709adc81918ce0e25a4c39a85d].each{|name|receipt=JSON.parse(File.read(root+'/live-attempts/'+name+'/receipt.json'));raise 'real completed receipt required' unless receipt['httpStatus']=='200'&&receipt['curlExit']==0}
  dest=File.join(data,ID)
  if File.directory?(dest)
   s=JSON.parse(File.read(dest+'/state.json'));raise 'conflicting existing record' unless s['outputHash']==m['outputHash']&&s['workflow']=='reference-layer-composite';return s
  end
  state={'id'=>ID,'module'=>'reference-reconstruction','workflow'=>'reference-layer-composite','state'=>'composed-pending-review','mode'=>f['options']['mode'],'mock'=>false,'createdAt'=>'2026-10-18T11:01:06Z','finishedAt'=>'2026-10-18T11:01:21Z','requestHash'=>p['binding']['requestHash'],'sourceHash'=>f['binding']['sourceHash'],'sourceMime'=>'image/jpeg','sourceDimensions'=>[1200,1500],'backgroundHash'=>m['backgroundHash'],'outputHash'=>m['outputHash'],'outputMime'=>'image/png','outputFilename'=>'output.png','ruleTrace'=>f['trace'],'visualAcceptance'=>'overall-usable-awaiting-user-confirmation','budgetMicroUSD'=>260000,'usage'=>JSON.parse(File.read(d+'/background-result.json'))['usage'],'prompt'=>'真实分层流程：已完成分析→显式缓存修正→一次无字背景→Inter本地合成。含执行者校正，不是整图直接生成。','preflight'=>f['preflight'],'composition'=>{'texts'=>m['textPlans'].map{|t|t['text']},'layout'=>m['compositionLayout'],'changes'=>m['changes'],'fontHashes'=>manifest['files'],'nativeDimensions'=>[1856,2304],'exactRequestedRatio'=>false,'stretch'=>false,'crop'=>false,'executorIntervention'=>true},'bindings'=>{'background'=>p['binding'],'analysis'=>JSON.parse(File.read(a+'/plan.json'))['binding']},'libraryFileId'=>JSON.parse(File.read(d+'/library-result.json'))['library_file_id'],'approvalStatus'=>'both-consumed-no-retry'}
  finding={'status'=>'visual-advisory','summary'=>'整体可用候选：字体、大小写、禁词、数字品牌和上下对照检查通过，无重复标签。下方光域较宽为具体视觉差异，不自动整图拒收或重做；用户最终确认待定。','basis'=>'Parent review applying user overall-usability standard; no claim of explicit final user acceptance','supersedes'=>'diagnostics strict evidence preservation flag for whole-image rejection; historical observation retained'}
  FileUtils.mkdir_p(data,mode:0700);temp=dest+'.importing';Dir.mkdir(temp,0700)
  begin
   files.each{|name,path|FileUtils.cp(path,File.join(temp,name))}
   {'state.json'=>state,'manual-findings.json'=>finding,'generic-gc-plan.json'=>f,'composition-manifest.json'=>m,'cost-and-delivery.json'=>JSON.parse(File.read(d+'/cost-and-delivery.json'))}.each{|name,v|File.write(File.join(temp,name),JSON.pretty_generate(v))}
   File.rename(temp,dest)
  ensure
   FileUtils.rm_rf(temp) if File.directory?(temp)
  end
  state
 end
end
if __FILE__==$0
 s=AuthorizedCompositeHistory.import(File.join(__dir__,'bridge-jobs'));puts JSON.generate(s.select{|k,_|%w[id state workflow outputHash].include?(k)})
end
