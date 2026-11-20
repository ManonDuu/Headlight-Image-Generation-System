require_relative 'bridge-server'
require 'tmpdir';require 'net/http'
n=0;check=lambda{|v,label|raise label unless v;n+=1}
Dir.mktmpdir('product-http-') do |dir|
 reference=File.binread(File.join(__dir__,'assets/81gMZuoRq6L._AC_SL1500_.jpg'));product=File.binread(File.join(__dir__,'assets/exec-2f5b9ebc-8a90-43e8-aaf9-c4a4c0117844.png'));hash=Digest::SHA256.hexdigest(reference)
 store=File.join(dir,'empty-analysis');FileUtils.mkdir_p(store)
 port=8795
 pid=fork{STDOUT.reopen(File::NULL,'w');Bridge.new(mock:true,data:File.join(dir,'jobs'),analysis_store:store).serve(port)}
 request=lambda do |path,data=nil,token=nil|
  h=Net::HTTP.new('127.0.0.1',port,nil);h.max_retries=0;h.read_timeout=20
  r=data ? Net::HTTP::Post.new(path) : Net::HTTP::Get.new(path);r['Origin']="http://127.0.0.1:#{port}";r['Content-Type']='application/json';r['X-Session-Token']=token if token;r.body=JSON.generate(data) if data;h.request(r)
 end
 begin
  session=nil;100.times{begin;session=JSON.parse(request.call('/api/session').body);break;rescue SystemCallError;end;sleep 0.1};token=session.fetch('token')
  d={'businessSpec'=>DirectImagePlan::SPEC,'module'=>'product-replacement','mode'=>'custom','customCopy'=>'60W Exact CASE','output'=>{'aspectRatio'=>'12:15','imageSize'=>'2K'},'layoutTone'=>'adjust-color','color'=>'#112233','layoutMode'=>'auto-layout','brandName'=>'OWN','productParameters'=>'','sceneMode'=>'keep','productName'=>'OFFLINE fixture','imageBase64'=>Base64.strict_encode64(reference),'sourceHash'=>hash,'productImageBase64'=>Base64.strict_encode64(product),'productHash'=>Digest::SHA256.hexdigest(product),'budgetMicroUSD'=>270000}
  swapped=d.merge('imageBase64'=>d['productImageBase64'],'productImageBase64'=>d['imageBase64']);check.call(request.call('/api/freeze',swapped,token).code=='400','swapped bytes rejected by role hashes')
  r=request.call('/api/freeze',d,token);check.call(r.code=='200','product HTTP freeze '+r.body[0,200]);s=JSON.parse(r.body)
  check.call(s.dig('ruleTrace','selectedOptions','sceneMode')=='keep','scene persisted')
  check.call(s.dig('ruleTrace','selectedOptions','layoutMode')=='auto-layout'&&!s.dig('ruleTrace','selectedOptions').key?('layoutInstructions'),'layout persisted')
  source=request.call('/api/task/'+s['id']+'/product',nil,token);check.call(source.code=='200'&&source.body==product&&source['content-type']=='image/png'&&s['productMime']=='image/png','original product restored')
  check.call(request.call('/api/task/'+s['id']+'/product',nil,'bad').code=='400','product source protected')
  req={'id'=>s['id'],'requestHash'=>s['genericGC']['requestHash']};check.call(request.call('/api/generic/generate',req,token).code=='200','mock dispatch')
  check.call(request.call('/api/generic/generate',req,token).code=='400','duplicate blocked')
  done=nil;100.times{done=JSON.parse(request.call('/api/task/'+s['id'],nil,token).body);break if done['state']!='running';sleep 0.1}
  check.call(done['state']=='mock-result','mock completes')
  check.call(done['visualAcceptance']!='passed'&&done['ruleTrace']['checks'].all?{|c|c['status']=='not-evaluated'},'HTTP success never visual pass')
  img=request.call('/api/task/'+s['id']+'/image',nil,token);check.call(Digest::SHA256.hexdigest(img.body)==done['outputHash'],'native download')
  hist=JSON.parse(request.call('/api/session').body)['history'].find{|x|x['id']==s['id']};check.call(hist['ruleTrace']['selectedOptions']==s['ruleTrace']['selectedOptions'],'history options immutable')
  Process.kill('TERM',pid);Process.wait(pid)
  pid=fork{STDOUT.reopen(File::NULL,'w');Bridge.new(mock:true,data:File.join(dir,'jobs'),analysis_store:store).serve(port)}
  fresh=nil;100.times{begin;fresh=JSON.parse(request.call('/api/session').body);break;rescue SystemCallError;end;sleep 0.1};token=fresh.fetch('token')
  restored=JSON.parse(request.call('/api/task/'+s['id'],nil,token).body)
  check.call(restored['ruleTrace']==done['ruleTrace']&&restored['outputHash']==done['outputHash'],'restart preserves task contract and output')
  check.call(request.call('/api/task/'+s['id']+'/product',nil,token).body==product,'restart preserves exact product bytes')
  check.call(request.call('/api/generic/generate',req,token).code=='400','restart cannot spend twice')
  wrong=d.merge('module'=>'reference-reconstruction','budgetMicroUSD'=>260000);check.call(request.call('/api/freeze',wrong,token).code=='400','cross-module scene/product blocked')
 ensure
  Process.kill('TERM',pid) rescue nil;Process.wait(pid) rescue nil
 end
end
puts "PASS #{n} isolated product HTTP/freeze/scene/history/dual-original/download checks; mock only"
