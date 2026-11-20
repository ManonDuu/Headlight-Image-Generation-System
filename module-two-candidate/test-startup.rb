require 'net/http';require 'json';require 'tmpdir';require 'fileutils';require 'open3'
ROOT=File.expand_path(__dir__);PORT=8797
n=0;check=lambda{|ok,msg|raise msg unless ok;n+=1}
Dir.mktmpdir('bridge-startup-') do |dir|
 r,w=IO.pipe
 args=['/usr/bin/ruby',ROOT+'/bridge-server.rb','--mock','--audited-repair-once','--port',PORT.to_s,'--data',dir+'/one']
 pid=Process.spawn({'PATH'=>'/usr/bin:/bin'},*args,out:w,err:File::NULL,unsetenv_others:true);w.close
 begin
  raise 'no ready' unless IO.select([r],nil,nil,10)
  ready=r.gets
  check.call(ready.include?('rules=recovered-approved-core-20261017.5')&&ready.include?('remaining=1')&&ready.include?('approval=module-one-audited-repair-20261017-one-call'),'unambiguous ready line')
  out,err,st=Open3.capture3({'PATH'=>'/usr/bin:/bin'},'/usr/bin/ruby',ROOT+'/bridge-server.rb','--mock','--port',PORT.to_s,'--data',dir+'/two',unsetenv_others:true)
  check.call(st.exitstatus==78,'port conflict nonzero exit')
  check.call(err.include?('已被占用')&&err.include?('本次服务未启动')&&!out.include?('READY'),'conflict never prints READY')
  h=Net::HTTP.new('127.0.0.1',PORT,nil);h.open_timeout=2;h.read_timeout=2
  s=JSON.parse(h.get('/api/session').body);check.call(s['remaining']==1&&s['history'].empty?,'conflict does not submit anything')
  Process.kill('INT',pid)
  check.call(IO.select([r],nil,nil,10)&&r.gets.to_s.include?('STOPPED'),'Ctrl+C signal closes idle listener clearly')
  Process.wait(pid);pid=nil
  begin;h.get('/api/session');raise 'listener still open';rescue Errno::ECONNREFUSED;n+=1;end
  check.call(Dir[dir+'/**/*.attempt'].empty?,'no attempt reserved')
 ensure
  if pid;Process.kill('TERM',pid) rescue nil;Process.wait(pid) rescue nil;end;r.close
 end
end
puts "PASS #{n} isolated mock startup/conflict/SIGINT checks. No user process touched."
