require 'net/http';require 'json';require 'tmpdir';require 'fileutils'
ROOT=File.expand_path(__dir__);PORT=8798
n=0
check=lambda{|ok,label|raise label unless ok;n+=1}
Dir.mktmpdir('picture-maintenance-') do |dir|
  runtime=dir+'/runtime';Dir.mkdir(runtime)
  Dir[ROOT+'/*.{rb,zsh,js,html}'].each{|p|FileUtils.cp(p,runtime)}
  pid=Process.spawn({'PATH'=>'/usr/bin:/bin'},'/usr/bin/ruby',runtime+'/maintenance-supervisor.rb','--mock','--audited-repair-once','--port',PORT.to_s,'--data',dir,out:File::NULL,err:File::NULL,unsetenv_others:true)
  http=Net::HTTP.new('127.0.0.1',PORT,nil);http.open_timeout=1;http.read_timeout=20
  get=lambda{JSON.parse(http.get('/api/session').body)}
  wait=lambda{|old|found=nil;100.times do;begin;s=get.call;if !old||s['token']!=old;found=s;break;end;rescue SystemCallError,IOError,EOFError;end;sleep 0.1;end;raise 'service not ready' unless found;found}
  post=lambda{|token,origin|req=Net::HTTP::Post.new('/api/maintenance/restart');req['X-Session-Token']=token;req['Origin']=origin;req['Content-Type']='application/json';req.body='{}';http.request(req)}
  origin="http://127.0.0.1:#{PORT}"
  begin
    s=wait.call(nil);check.call(s['maintenanceAvailable']&&s['mock'],'mock supervisor ready')
    check.call(post.call('wrong',origin).code=='400','token required')
    check.call(post.call(s['token'],'http://foreign.invalid').code=='400','origin required')
    File.write(runtime+'/broken-update.rb','def broken(')
    check.call(post.call(s['token'],origin).body.include?('syntax error'),'bad update rejected before shutdown')
    check.call(get.call['token']==s['token'],'healthy service retained after syntax failure')
    File.unlink(runtime+'/broken-update.rb')
    rulefile=runtime+'/rules-compiler.rb';original_rules=File.read(rulefile)
    File.write(rulefile,original_rules.sub('recovered-approved-core-20261017.5','changed-unapproved-version'))
    check.call(post.call(s['token'],origin).body.include?('changes rules/authorization'),'rules change rejected before shutdown')
    File.write(rulefile,original_rules)
    task=dir+'/0123456789abcdef01234567';Dir.mkdir(task);File.write(task+'/state.json',JSON.generate(id:'0123456789abcdef01234567',state:'running'))
    check.call(post.call(s['token'],origin).body.include?('task running'),'running task blocks restart')
    File.write(task+'/state.json',JSON.generate(id:'0123456789abcdef01234567',state:'stopped'))
    ledger=dir+'/module-one-audited-repair-20261017-one-call';Dir.mkdir(ledger);File.write(ledger+'/binding.json','preserved test marker')
    check.call(post.call(s['token'],origin).code=='200','idle restart accepted')
    after=wait.call(s['token']);check.call(after['token']!=s['token'],'new session after restart')
    check.call(after['remaining']==0&&after['approval']==s['approval'],'consumed approval preserved')
    check.call(File.read(ledger+'/binding.json')=='preserved test marker'&&after['history'].size==1,'ledger and history preserved')
    check.call(post.call(s['token'],origin).code=='400','old token rejected')
    check.call(Dir[dir+'/**/request.json'].empty?,'maintenance creates no model request')
    Process.kill('TERM',pid);Process.wait(pid);pid=nil
    begin;get.call;raise 'listener remains';rescue Errno::ECONNREFUSED;n+=1;end
  ensure
    if pid;Process.kill('TERM',pid) rescue nil;Process.wait(pid) rescue nil;end
  end
end
puts "PASS #{n} isolated mock maintenance checks; no model or user-process access."
