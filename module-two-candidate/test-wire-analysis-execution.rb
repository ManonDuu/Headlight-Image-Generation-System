require_relative 'bridge-server';require 'tmpdir'
n=0
Dir.mktmpdir('wire-analysis-mock-') do |dir|
 %w[success error invalid-schema].each do |scenario|
  b=Bridge.new(mock:true,data:File.join(dir,scenario),scenario:scenario)
  plan=b.wire_analysis_plan;raise unless plan['requestHash']==BridgeWireAnalysis::WIRE_BINDING['requestHash'];n+=1
  begin
   r=b.execute_wire_analysis(BridgeWireAnalysis::WIRE_BINDING)
   raise unless scenario=='success'&&r['automaticGeneration']==false;n+=1
  rescue => e
   raise if scenario=='success';raise unless File.file?(b.wire_analysis_ledger+'/result.json');n+=1
  end
  begin;b.execute_wire_analysis(BridgeWireAnalysis::WIRE_BINDING);raise 'duplicate accepted';rescue => e;raise unless e.message.include?('already consumed');n+=1;end
 end
 b=Bridge.new(mock:false,data:File.join(dir,'denied'))
 begin;b.execute_wire_analysis(BridgeWireAnalysis::WIRE_BINDING);raise 'unexpected live';rescue => e;raise unless e.message.include?('maintained');n+=1;end
end
puts "PASS #{n} corrected-schema execution mock checks; zero network"
