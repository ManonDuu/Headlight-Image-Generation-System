require 'net/http';require 'json';require 'tmpdir';require 'digest'
root=File.expand_path(__dir__);pause=Digest::SHA256.file(root+'/LIVE-REQUESTS-PAUSED').hexdigest;ledger=Digest::SHA256.file(root+'/diagnostics/cumulative-budget/global-ledger/ledger.json').hexdigest
Dir.mktmpdir do |d|
 script="require '#{root}/bridge-server';Bridge.new(mock:true,data:#{(d+'/jobs').inspect},supervised:true).serve(8799)"
 pid=Process.spawn('/usr/bin/ruby','-e',script,out:File::NULL,err:File::NULL)
 begin
  h=Net::HTTP.new('127.0.0.1',8799,nil);s=nil;100.times{begin;s=JSON.parse(h.get('/api/session').body);break;rescue SystemCallError;sleep 0.1;end}
  r=Net::HTTP::Post.new('/api/cumulative-scene/execute');r['Origin']='http://127.0.0.1:8799';r['Content-Type']='application/json';r['X-Session-Token']=s.fetch('token');r.body=JSON.generate({'requestHash'=>'5aeba59aded4a8f268417673c29835fcd913540769642d28337ac35a7c3c9851'});res=h.request(r)
  raise res.body unless res.code.to_i>=400&&res.body.include?('cumulative paid acceptance disabled')
  raise 'ledger mutated' unless Digest::SHA256.file(root+'/diagnostics/cumulative-budget/global-ledger/ledger.json').hexdigest==ledger
  raise 'pause modified' unless Digest::SHA256.file(root+'/LIVE-REQUESTS-PAUSED').hexdigest==pause
  File.write(root+'/diagnostics/cumulative-budget/route-tests.json',JSON.pretty_generate({'existingBridgeRoute'=>'integrated','disabledNewApprovalRejected'=>true,'ledgerUnchanged'=>true,'oldPauseUnchanged'=>true,'modelCalls'=>0,'live8773Touched'=>false}));puts 'Existing bridge new controlled route rejects disabled approval before transport; pause and ledger unchanged'
 ensure
  Process.kill('TERM',pid)rescue nil;Process.wait(pid)rescue nil
 end
end
