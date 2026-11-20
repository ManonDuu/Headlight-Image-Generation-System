require 'json';require 'digest';require 'fileutils'
r=File.expand_path(__dir__);dest=File.join(File.dirname(r),'delivery','picture-current-20261018-reviewed')
raise 'preserve existing delivery' if File.exist?(dest)
FileUtils.mkdir_p(dest,mode:0700)
# Explicit source/document allowlist; no runtime, credentials, raw responses or request bodies.
files=Dir[r+'/*.{rb,js,html,css,zsh}']
names=%w[approved-rules.txt rules-status.json DELIVERY-STATUS-CURRENT.txt CURRENT-USE-AND-VALIDATION-20261018.txt GC-ENUM-FIELD-AUDIT-20261018.txt GC-ANALYSIS-LIVE-RESULT-20261018.txt MAINTENANCE-LIVE-VERIFICATION.json RULE-REQUEST-TRACE-20261018.json]
files+=names.map{|x|r+'/'+x}
files.each{|src|raise 'symlink' if File.symlink?(src);FileUtils.cp(src,dest)}
FileUtils.cp_r(r+'/diagnostics/delivery-ui-current',dest+'/screenshots')
FileUtils.mkdir_p(dest+'/accepted-example')
FileUtils.cp(r+'/bridge-jobs/9dce1ce10578330f6d472373/output.jpg',dest+'/accepted-example/output.jpg')
raise 'accepted image changed' unless Digest::SHA256.file(dest+'/accepted-example/output.jpg').hexdigest=='3b3113166988b49c8b471297fbf30a0ca216655cc64db4538d479b36e8850fa0'
manifest={}
Dir[dest+'/**/*'].select{|p|File.file?(p)}.sort.each do |p|
 raise 'symlink' if File.symlink?(p)
 unless %w[.png .jpg].include?(File.extname(p))
  s=File.binread(p)
  raise 'credential pattern: '+File.basename(p) if s.match?(/AIza[0-9A-Za-z_-]{35}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|Bearer\s+[A-Za-z0-9._-]{24,}/)
  raise 'embedded raw image payload' if s.match?(/"(?:data|imageBase64)"\s*:\s*"[A-Za-z0-9+\/=]{200,}"/)
 end
 manifest[p.sub(dest+'/','')]={sha256:Digest::SHA256.file(p).hexdigest,bytes:File.size(p)}
end
File.write(dest+'/MANIFEST-SHA256.json',JSON.pretty_generate(manifest))
archive=dest+'.zip';raise 'archive exists' if File.exist?(archive)
raise 'zip failed' unless system('/usr/bin/zip','-q','-r',archive,File.basename(dest),chdir:File.dirname(dest))
receipt={directory:dest,archive:archive,files:manifest.size,bytes:File.size(archive),sha256:Digest::SHA256.file(archive).hexdigest,credentialPatternMatches:0,rawRuntimeIncluded:false,allVisuallyAccepted:false}
File.write(r+'/CURRENT-DELIVERY-RECEIPT.json',JSON.pretty_generate(receipt));puts JSON.generate(receipt)
