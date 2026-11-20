require_relative 'bridge-server'
require 'net/http';require 'tmpdir'
n=0;check=lambda{|v|raise 'assertion failed' unless v;n+=1}
Dir.mktmpdir('generic-http-') do |dir|
  port=8796
  pid=Process.spawn({'PATH'=>'/usr/bin:/bin'},'/usr/bin/ruby',File.join(__dir__,'maintenance-supervisor.rb'),'--mock','--port',port.to_s,'--data',dir,unsetenv_others:true,out:File::NULL,err:File::NULL)
  request=lambda do |path,data=nil,token=nil|
    h=Net::HTTP.new('127.0.0.1',port,nil);h.max_retries=0;h.read_timeout=20
    r=data ? Net::HTTP::Post.new(path) : Net::HTTP::Get.new(path)
    r['Origin']="http://127.0.0.1:#{port}";r['Content-Type']='application/json';r['X-Session-Token']=token if token
    r.body=JSON.generate(data) if data;h.request(r)
  end
  ready=lambda{|old|100.times{begin;s=JSON.parse(request.call('/api/session').body);break s if !old||s['token']!=old;rescue SystemCallError,IOError;end;sleep 0.1}}
  begin
    s=ready.call(nil);check.call(s.is_a?(Hash));token=s['token']
    bytes=File.binread(File.join(__dir__,'assets/exec-2f5b9ebc-8a90-43e8-aaf9-c4a4c0117844.png'))
    input={'businessSpec'=>DirectImagePlan::SPEC,'layoutMode'=>'keep-reference','module'=>'reference-reconstruction','mode'=>'ai-rewrite','output'=>{'aspectRatio'=>'16:9','imageSize'=>'2K'},'layoutTone'=>'keep-reference','budgetMicroUSD'=>260000,'sourceHash'=>Digest::SHA256.hexdigest(bytes),'imageBase64'=>Base64.strict_encode64(bytes)}
    task=JSON.parse(request.call('/api/freeze',input,token).body)
    check.call(task['workflow']=='direct-generation'&&task.dig('genericGC','analysisCalls')==0)
    source=request.call('/api/task/'+task['id']+'/reference',nil,token);check.call(source['content-type']=='image/png'&&source.body==bytes&&task['sourceMime']=='image/png')
    d={'id'=>task['id'],'requestHash'=>task.dig('genericGC','requestHash')}
    check.call(request.call('/api/generic/generate',d,'bad').code=='400')
    check.call(request.call('/api/generic/generate',d.merge('requestHash'=>'bad'),token).code=='400')
    check.call(request.call('/api/generic/generate',d,token).code=='200')
    check.call(request.call('/api/generic/generate',d,token).code=='400')
    done=nil;100.times{done=JSON.parse(request.call('/api/task/'+task['id'],nil,token).body);break if done['state']!='running';sleep 0.1}
    check.call(done['state']=='mock-result')
    check.call(done['ruleTrace']['checks'].all?{|c|c['status']=='not-evaluated'})
    img=request.call('/api/task/'+task['id']+'/image',nil,token)
    check.call(img.code=='200'&&Digest::SHA256.hexdigest(img.body)==done['outputHash'])
    ledgers=Dir[dir+'/**/binding.json'].map{|p|[p,Digest::SHA256.file(p).hexdigest]}.to_h
    check.call(request.call('/api/maintenance/restart',{},token).code=='200')
    fresh=ready.call(token);check.call(fresh['token']!=token)
    restored=JSON.parse(request.call('/api/task/'+task['id'],nil,fresh['token']).body)
    source=request.call('/api/task/'+task['id']+'/reference',nil,fresh['token']);check.call(source['content-type']=='image/png'&&source.body==bytes)
    check.call(restored['ruleTrace']==done['ruleTrace']&&restored['outputHash']==done['outputHash'])
    check.call(request.call('/api/task/'+task['id']+'/image',nil,fresh['token']).body==img.body)
    check.call(ledgers.all?{|p,hash|Digest::SHA256.file(p).hexdigest==hash})
    check.call(request.call('/api/generic/generate',d,fresh['token']).code=='400')
  ensure
    Process.kill('TERM',pid) rescue nil;Process.wait(pid) rescue nil
  end
end
puts "PASS #{n} PNG reference HTTP MIME/bytes/freeze/mock/download/restart checks; mock only"
