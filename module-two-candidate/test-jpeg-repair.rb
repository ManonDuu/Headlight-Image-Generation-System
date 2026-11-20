require_relative 'bridge-server'
unless Bridge::GENERATION_LIVE_ENABLED
  puts 'Live paused: verify stale prior approval rejection instead of authorizing current candidate.'
  load File.join(__dir__,'test-stale-repair.rb')
  exit
end
require 'net/http';require 'json';require 'tmpdir';require 'digest';require 'base64'
ROOT=File.expand_path(__dir__);PORT=8796
n=0;check=lambda{|v,msg|raise msg unless v;n+=1}
request=lambda do |path,data=nil,token=nil|
 h=Net::HTTP.new('127.0.0.1',PORT,nil);h.max_retries=0
 r=data ? Net::HTTP::Post.new(path) : Net::HTTP::Get.new(path)
 r['X-Session-Token']=token if token
 if data;r['Origin']="http://127.0.0.1:#{PORT}";r['Content-Type']='application/json';r.body=JSON.generate(data);end
 res=h.request(r);[res.code,JSON.parse(res.body)]
end
old=Dir[ROOT+'/live-attempts/**/*'].select{|p|File.file?(p)}.map{|p|[p,Digest::SHA256.file(p).hexdigest]}.to_h
Dir.mktmpdir('jpeg-repair-policy-') do |data|
 bytes=File.binread(ROOT+'/assets/81gMZuoRq6L._AC_SL1500_.jpg')
 body={'module'=>'reference-reconstruction','mode'=>'no-copy','layoutTone'=>'keep-reference','output'=>{'aspectRatio'=>'4:5','imageSize'=>'2K'},'imageBase64'=>Base64.strict_encode64(bytes),'sourceHash'=>Digest::SHA256.hexdigest(bytes),'budgetMicroUSD'=>260000}
 2.times do |run|
  r,w=IO.pipe
  pid=Process.spawn({'PATH'=>'/usr/bin:/bin'},'/usr/bin/ruby',ROOT+'/bridge-server.rb','--mock','--jpeg-repair-once','--port',PORT.to_s,'--data',data,out:w,err:File::NULL,unsetenv_others:true);w.close
  begin
   raise 'startup failed' unless IO.select([r],nil,nil,10)&&r.gets.to_s.include?('READY')
   code,s=request.call('/api/session');token=s['token']
   check.call(code=='200'&&s['rulesVersion']=='recovered-approved-core-20261017.4','exact .4 startup')
   check.call(s['analysisLiveEnabled']==false&&s['approval']['analysisAllowed']==false,'analysis disabled')
   check.call(s['approval']['id']=='module-one-jpeg-repair-20261017-one-call'&&s['approval']['budgetMicroUSD']==260000,'fixed independent quota')
   check.call(s['remaining']==(run==0 ? 1 : 0),'restart does not replenish')
   if run==0
    check.call(s['history']==[]&&!File.exist?(data+'/'+s['approval']['id']),'startup sends nothing/reserves nothing')
    check.call(request.call('/api/analyze',body,token)[0]=='400','analysis route forbidden')
    check.call(request.call('/api/freeze',body.merge('mode'=>'keep-layout'),token)[0]=='400','other mode forbidden')
    check.call(request.call('/api/freeze',body.merge('sourceHash'=>'0'*64),token)[0]=='400','other image forbidden')
   end
   code,f=request.call('/api/freeze',body,token)
   check.call(code=='200'&&f['requestHash']==s['approval']['requestHash'],'freeze exactly pinned JPEG request')
   check.call(request.call('/api/generate',{'id'=>f['id'],'requestHash'=>'wrong'},token)[0]=='400','wrong hash cannot consume')
   gen={'id'=>f['id'],'requestHash'=>f['requestHash']}
   if run==0
    results=2.times.map{Thread.new{request.call('/api/generate',gen,token)[0]}}.map(&:value)
    check.call(results.sort==['200','400'],'concurrent clicks execute once')
    100.times{sleep 0.1;_,state=request.call('/api/task/'+f['id'],nil,token);break if state['state']!='running'}
    _,state=request.call('/api/task/'+f['id'],nil,token)
    check.call(state['state']=='mock-result'&&state['outputMime']=='image/jpeg','JPEG mock completes')
    binding=JSON.parse(File.read(data+'/'+s['approval']['id']+'/binding.json'))
    check.call(binding['approvalId']==s['approval']['id'],'ledger binds fixed approval ID')
   else
    check.call(request.call('/api/generate',gen,token)[0]=='400','new job after restart cannot spend again')
   end
  ensure
   Process.kill('TERM',pid) rescue nil;Process.wait(pid) rescue nil;r.close
  end
 end
end
old.each{|p,hash|check.call(Digest::SHA256.file(p).hexdigest==hash,'historical ledger unchanged')}
check.call(!File.exist?(ROOT+'/live-attempts/module-one-jpeg-repair-20261017-one-call'),'live repair unconsumed')
puts "PASS #{n} JPEG repair approval/startup/restart checks. Mock only; zero live calls."
