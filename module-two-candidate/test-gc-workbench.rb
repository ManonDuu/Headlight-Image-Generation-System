require 'net/http';require 'json';require 'tmpdir';require 'digest';require_relative 'bridge-server'
PORT=8799;ROOT=File.expand_path(__dir__)
n=0;check=lambda{|ok,msg|raise msg unless ok;n+=1}
Dir.mktmpdir('gc-workbench-') do |dir|
  pid=Process.spawn({'PATH'=>'/usr/bin:/bin'},'/usr/bin/ruby',ROOT+'/maintenance-supervisor.rb','--mock','--gc-comparison-once','--port',PORT.to_s,'--data',dir,unsetenv_others:true,out:File::NULL,err:File::NULL)
  request=lambda do |path,data=nil,token=nil,origin="http://127.0.0.1:#{PORT}"|
    h=Net::HTTP.new('127.0.0.1',PORT,nil);h.open_timeout=2;h.read_timeout=15;h.max_retries=0
    r=data ? Net::HTTP::Post.new(path) : Net::HTTP::Get.new(path)
    r['X-Session-Token']=token if token
    if data;r['Origin']=origin;r['Content-Type']='application/json';r.body=JSON.generate(data);end
    h.request(r)
  end
  wait=lambda{|old|100.times do;begin;s=JSON.parse(request.call('/api/session').body);break s if old.nil?||s['token']!=old;rescue SystemCallError,IOError;end;sleep 0.1;end}
  begin
    s=wait.call(nil);check.call(s.is_a?(Hash)&&s['maintenanceAvailable']&&s.dig('gcComparison','enabled'),'one launch installs both capabilities')
    check.call(s.dig('gcComparison','remaining')==1&&s['history'].empty?,'startup sends nothing')
    check.call(s['analysisLiveEnabled']==false&&s['generationLiveEnabled']==false,'other live paths stay locked')
    path='/api/experiment/generate-content';body={'requestHash'=>GenerateContentAdapter::REQUEST_HASH}
    check.call(request.call(path,body,'wrong').code=='400','session token enforced')
    check.call(request.call(path,body,s['token'],'http://other.invalid').code=='400','same origin enforced')
    check.call(request.call(path,{'requestHash'=>'wrong'},s['token']).code=='400','fixed hash enforced')
    results=2.times.map{Thread.new{request.call(path,body,s['token'])}}.map(&:value)
    check.call(results.map(&:code).sort==%w[200 400],'concurrent submissions execute once')
    id=JSON.parse(results.find{|r|r.code=='200'}.body)['id']
    state=nil;100.times{state=JSON.parse(request.call('/api/task/'+id,nil,s['token']).body);break if state['state']!='running';sleep 0.1}
    check.call(state['state']=='mock-result'&&state['analysisCalls']==0,'full adapter returns terminal result with no analysis')
    img=request.call('/api/task/'+id+'/image',nil,s['token'])
    check.call(img['Content-Type']=='image/jpeg'&&Digest::SHA256.hexdigest(img.body)==state['outputHash'],'download original bytes')
    check.call(JSON.parse(File.read(dir+'/'+id+'/request.json')).key?('contents'),'actual GC request persisted')
    check.call(request.call('/api/maintenance/restart',{},s['token']).code=='200','normal maintenance works')
    after=wait.call(s['token']);check.call(after.is_a?(Hash)&&after.dig('gcComparison','remaining')==0,'restart does not restore quota')
    check.call(request.call(path,body,after['token']).code=='400','repeat rejected after restart')
  ensure
    Process.kill('TERM',pid) rescue nil;Process.wait(pid) rescue nil
  end
end
puts "PASS #{n} isolated GC workbench/startup/download/maintenance/replay checks; no model requests."
