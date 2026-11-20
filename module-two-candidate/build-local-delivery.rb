# Local-only evidence snapshot. No service, network, credentials, or model execution.
require 'json';require 'digest';require 'fileutils'
root=File.expand_path(__dir__)
job=File.join(root,'bridge-jobs','3bdaaef4bf062f158e862cab')
request=JSON.parse(File.read(File.join(job,'request.json')))
request.fetch('input').each{|part|part['data']='[REDACTED: ORIGINAL JPEG BASE64]' if part.key?('data')}
File.write(File.join(root,'DIAGNOSTIC-REQUEST-REDACTED.json'),JSON.pretty_generate(request))
response=JSON.parse(File.read(File.join(job,'response.json')))
raise 'unexpected response evidence changed' unless Digest::SHA256.file(File.join(job,'response.json')).hexdigest=='bf97b99dae1567834b3ca5a0bea1d24e583e56858032048d7d27a1402329041d'
raise 'unexpected request changed' unless Digest::SHA256.file(File.join(job,'request.json')).hexdigest=='04ef522c895160a78a7f90134fdabbcf0fa13254a771013e10a4d1699938af78'
raise 'unexpected response shape' unless response.keys.sort==%w[status usage created updated service_tier object model].sort
dest=File.join(File.dirname(root),'delivery','picture-module-one-20261018-acceptance')
raise 'delivery already exists; preserve previous snapshot' if File.exist?(dest)
FileUtils.mkdir_p(dest,mode:0700)
files=Dir.glob(File.join(root,'*.{rb,js,zsh,html}'))
names=%w[START-HERE.txt INCOMPLETE-DIAGNOSIS.txt DIAGNOSTIC-REQUEST-REDACTED.json approved-rules.txt rules-status.json manual-review-template.json AUDITED-REPAIR-AUTHORIZATION.json AUDITED-REPAIR-RESULT.json AUDITED-REPAIR-RESULT.txt AUDITED-REPAIR-LIVE-RECEIPT.json MODEL-AUDIT-CANDIDATE.json MAINTENANCE-AND-APPROVAL-HANDOFF.txt]
files.concat(names.map{|f|File.join(root,f)})
files << File.join(root,'INCOMPLETE-REGRESSION-DELIVERY.txt')
files << File.join(root,'NEXT-CONTROLLED-EXPERIMENT.txt')
files << File.join(root,'GC-EXPERIMENT-PLAN.json')
%w[GC-READY-TO-RUN.txt GC-SUCCESS-AND-MAINTENANCE.txt GC-COMPARISON-RESULT.json GC-COMPARISON-LIVE-RECEIPT.json GC-VISUAL-REVIEW.json GC-VISUAL-REVIEW-PRELIMINARY.json MAINTENANCE-LIVE-VERIFICATION.json REAL-RESULT-WORKBENCH-ACCEPTANCE.json NATIVE-JPEG-DELIVERY.json LIGHTING-REPAIR-CANDIDATE.json MODULE-ONE-FINAL-ACCEPTANCE.txt USER-GUIDE.txt].each{|f|files<<File.join(root,f)}
files.each{|f|FileUtils.cp(f,dest)}
%w[assets fixtures analysis-cache bridge-jobs live-attempts gc-comparison-20261018].each{|dir|FileUtils.cp_r(File.join(root,dir),dest)}
manifest={}
scrub=lambda do |value|
  case value
  when Hash;value.each_with_object({}){|(k,v),h|h[k]=%w[data imageBase64 thoughtSignature].include?(k) ? '[BINARY_OR_OPAQUE_PAYLOAD]' : scrub.call(v)}
  when Array;value.map{|v|scrub.call(v)}
  else;value
  end
end
Dir.glob(dest+'/**/*',File::FNM_DOTMATCH).select{|p|File.file?(p)}.sort.each do |p|
  raise 'symlink prohibited in snapshot' if File.symlink?(p)
  if File.extname(p)!='.jpg'&&File.extname(p)!='.png'
    content=File.binread(p)
    content=JSON.generate(scrub.call(JSON.parse(content))) if File.extname(p)=='.json'
    raise 'credential-pattern detected; snapshot must not be packaged' if content.match?(/AIza[0-9A-Za-z_-]{35}/)
  end
  manifest[p.sub(dest+'/','')]={'sha256'=>Digest::SHA256.file(p).hexdigest,'bytes'=>File.size(p)}
end
File.write(File.join(dest,'MANIFEST-SHA256.json'),JSON.pretty_generate(manifest))
puts JSON.generate(delivery:dest,files:manifest.size,responseKeys:response.keys,requestMaxOutputTokens:request.dig('generation_config','max_output_tokens'),credentialPatternMatches:0)
