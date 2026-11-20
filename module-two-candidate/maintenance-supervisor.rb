# User-started, foreground supervisor. No daemon, credential file, or auto-retry.
require_relative 'bridge-server'
mock=ARGV.delete('--mock')
audited=ARGV.delete('--audited-repair-once')
gc_once=ARGV.delete('--gc-comparison-once')
abort 'choose one profile' if audited&&gc_once
port=8773;data=nil;generic=nil;analysis_approval=nil
until ARGV.empty?
  option=ARGV.shift
  case option
  when '--analysis-approved-plan'
    plan=JSON.parse(File.read(File.expand_path(ARGV.shift)))
    bytes=Base64.strict_decode64(plan.fetch('request').fetch('input')[1].fetch('data'))
    expected=VisualAnalysis.request(bytes,plan.fetch('width'),plan.fetch('height'))
    raise 'analysis request altered' unless expected==plan['request']&&Digest::SHA256.hexdigest(JSON.generate(expected))==plan['requestHash']&&plan['binding']==VisualAnalysis.binding(Digest::SHA256.hexdigest(bytes))&&plan['analysisBudgetMicroUSD']==20000
    analysis_approval={'requestHash'=>plan['requestHash'],'sourceHash'=>plan['binding']['sourceHash'],'budgetMicroUSD'=>20000}
  when '--port';port=Integer(ARGV.shift)
  when '--data';raise 'custom data is mock-only' unless mock;data=File.expand_path(ARGV.shift)
  when '--generic-approved-plan'
    plan=JSON.parse(File.read(File.expand_path(ARGV.shift)))
    (plan.dig('binding','module')=='product-replacement' ? ProductReplacementPlan : GenericGCPlan).validate(plan)
    raise 'mock plan cannot authorize live generation' if !mock&&plan.dig('binding','mock')
    generic=plan.fetch('binding')
  else;abort 'unsupported supervisor option'
  end
end
raise 'invalid port' unless port.between?(1024,65535)
raise 'choose one approval profile' if [generic,analysis_approval,audited,gc_once].count{|x|x} > 1
key=ENV.delete('GEMINI_API_KEY')
key=nil if mock
abort 'No configured credential; nothing started or sent' unless mock||(key&&key.match?(/\A[A-Za-z0-9._-]+\z/)&&key.bytesize<4096)
boot={'key'=>key,'approval'=>gc_once ? Bridge::GC_COMPARISON_APPROVAL : audited ? Bridge::AUDITED_REPAIR : nil,'rulesVersion'=>RulesCompiler::VERSION}
boot['genericApproval']=generic
boot['genericAnalysisApproval']=analysis_approval
key=nil
args=['/usr/bin/ruby',File.join(Bridge::ROOT,'bridge-server.rb'),'--supervised-fd','3','--port',port.to_s]
args << '--mock' if mock
args << '--audited-repair-once' if audited
args << '--gc-comparison-once' if gc_once
args.concat(['--data',data]) if data
child=nil;stopping=false;exit_status=0
%w[INT TERM].each do |signal|
  trap(signal){stopping=true;begin;Process.kill('TERM',child) if child;rescue Errno::ESRCH;end}
end
begin
  loop do
    break if stopping
    read_end,write_end=IO.pipe
    begin
      child=Process.spawn({'GEMINI_API_KEY'=>nil},*args,3=>read_end,close_others:true)
      read_end.close
      write_end.write(JSON.generate(boot));write_end.close
      _,status=Process.wait2(child);child=nil
    ensure
      read_end.close unless read_end.closed?
      write_end.close unless write_end.closed?
    end
    # Only a protected, idle maintenance action requests restart. Crash/stop ends it.
    unless !stopping&&status.exitstatus==75
      exit_status=stopping ? 0 : (status.exitstatus||1)
      break
    end
    puts 'MAINTENANCE: restarting own service; existing approval and ledger retained.'
    STDOUT.flush
  end
ensure
  boot['key']=nil
end
exit exit_status
