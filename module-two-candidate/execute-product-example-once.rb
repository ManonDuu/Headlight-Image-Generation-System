require_relative 'direct-image-plan'
require 'net/http'
abort 'PAUSED: reconcile shared module-one rules before any paid request' if File.exist?(File.join(__dir__,'assets/module-two-history/PAUSED'))
root=File.expand_path(__dir__);dir=root+'/assets/module-two-history'
plan=JSON.parse(File.read(dir+'/candidate-v6-product-replacement-local.json'));DirectImagePlan.validate(plan)
b=plan.fetch('binding');hash='8ec0af2ce7c0dad555fd1a91226cd4ca68cc5f584819d2ea8b3ef2c57ce51ebc'
raise 'wrong plan' unless b['requestHash']==hash&&b['budgetMicroUSD']==270000&&b['retries']==0&&b['analysisCalls']==0&&!b['mock']
raise 'attempt consumed; stop' if File.exist?(root+'/live-attempts/generic-gc-'+hash)||File.exist?(dir+'/dispatch-receipt.json')
ref=File.binread(root+'/assets/module-two-history/reference.jpg')
raise 'source changed' unless Digest::SHA256.hexdigest(ref)==b['sourceHash']
h=Net::HTTP.new('127.0.0.1',8773,nil);h.max_retries=0;h.open_timeout=5;h.read_timeout=20
s=JSON.parse(h.get('/api/session').body)
raise 'wrong service' unless s['mock']==false&&s['maintenanceAvailable']&&s.dig('genericGC','businessSpec')==DirectImagePlan::SPEC&&!s.dig('genericGC','preAnalysisEnabled')
raise 'in flight or duplicate' if s['history'].any?{|v|v['state']=='running'||v['requestHash']==hash}
post=lambda{|path,data|r=Net::HTTP::Post.new(path);r['Origin']='http://127.0.0.1:8773';r['Content-Type']='application/json';r['X-Session-Token']=s['token'];r.body=JSON.generate(data);x=h.request(r);raise "local HTTP #{x.code}: #{x.body[0,300]}" unless x.code=='200';JSON.parse(x.body)}
product=File.binread(dir+"/product.jpg")
raise 'product changed' unless Digest::SHA256.hexdigest(product)==b['productHash']
f=post.call('/api/freeze',plan['options'].merge('budgetMicroUSD'=>270000,'sourceHash'=>b['sourceHash'],'productHash'=>b['productHash'],'productImageBase64'=>Base64.strict_encode64(product),'imageBase64'=>Base64.strict_encode64(ref)))
raise 'freeze differs' unless f['genericGC']==b&&f['requestHash']==hash
id=f.fetch('id')
File.open(dir+'/dispatch-receipt.json',File::WRONLY|File::CREAT|File::EXCL,0600){|io|io.write(JSON.pretty_generate({task:id,requestHash:hash,approvalEvidence:'Sentinel_8d6715d76118819193cf192014f4cf21; Sentinel_552aac6120688191be3997c3a3f0dddf; resume same single authority with shared v6 rules',budgetUSD:0.27,maxRequests:1,retries:0,analysisCalls:0,at:Time.now.utc.iso8601}))}
x=post.call('/api/direct/approved-once',{'id'=>id,'requestHash'=>hash})
puts JSON.generate({task:id,state:x['state'],requestHash:hash});STDOUT.flush
45.times do
 sleep 5
 r=Net::HTTP::Get.new('/api/task/'+id);r['X-Session-Token']=s['token'];res=h.request(r);raise 'observation failed; do not repeat' unless res.code=='200';x=JSON.parse(res.body)
 next if x['state']=='running'
 File.write(dir+'/live-result.json',JSON.pretty_generate(x))
 if x['state']=='generated-pending-review'
  r=Net::HTTP::Get.new('/api/task/'+id+'/image');r['X-Session-Token']=s['token'];download=h.request(r)
  raise 'download mismatch' unless download.code=='200'&&Digest::SHA256.hexdigest(download.body)==x['outputHash']&&Digest::SHA256.file(root+'/bridge-jobs/'+id+'/'+x['outputFilename']).hexdigest==x['outputHash']
  File.write(dir+'/download-verification.json',JSON.pretty_generate({task:id,http:200,sha256:x['outputHash'],originalBytes:download.body.bytesize,matched:true}))
 end
 puts JSON.pretty_generate(x.reject{|k,_|%w[prompt ruleTrace preflight].include?(k)});exit
end
raise 'outcome unknown; observe only, never resend'
