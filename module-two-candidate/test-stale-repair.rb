require_relative 'bridge-server'
n=0;check=lambda{|v|raise 'failed stale approval check' unless v;n+=1}
Dir.mktmpdir do |dir|
 begin;Bridge.new(mock:true,data:dir,repair_once:true);raise 'old approval accepted';rescue=>e;check.call(e.message=='repair requires exact approved rules version and disabled analysis');end
 check.call(!File.exist?(dir+'/'+Bridge::JPEG_REPAIR['id']))
 check.call(Dir[dir+'/*/state.json'].empty?)
 live=Bridge.allocate;live.instance_variable_set(:@mock,false)
 begin;live.generate('unused','unused');raise 'live lock failed';rescue=>e;check.call(e.message.include?('live generation locked'));end
end
puts "PASS #{n} obsolete-approval and default-paused-live guards; no requests."
