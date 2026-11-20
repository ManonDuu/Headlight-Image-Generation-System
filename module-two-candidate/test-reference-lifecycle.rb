require 'tmpdir'
require 'timeout'
require_relative 'bridge-server'
source=File.binread('/Users/manrongdu/Downloads/71efzt2fH8L._AC_SL1500_.jpg')
checks=[]
%w[success timeout multiple error].each do |scenario|
 Dir.mktmpdir('reference-lifecycle-') do |dir|
  begin
   bridge=Bridge.new(mock:true,data:dir,scenario:scenario)
   input={'businessSpec'=>DirectImagePlan::SPEC,'module'=>'reference-reconstruction','mode'=>'custom','customCopy'=>"Brighter Road Visibility\nLED\nHalogen",'layoutTone'=>'adjust-color','color'=>'#2864C8','layoutMode'=>'auto-layout','output'=>{'aspectRatio'=>'1:1','imageSize'=>'2K'},'imageBase64'=>Base64.strict_encode64(source),'sourceHash'=>Digest::SHA256.hexdigest(source),'budgetMicroUSD'=>260000}
   s=bridge.freeze_direct(input);d={'id'=>s['id'],'requestHash'=>s['requestHash']};bridge.generate_generic(d)
   done=Timeout.timeout(15){loop{x=bridge.snapshot(s['id']);break x unless x['state']=='running';sleep 0.05}}
   expected=scenario=='success' ? 'mock-result' : 'stopped'
   raise 'unexpected state: '+done['state'].to_s+' '+done['error'].to_s unless done['state']==expected
   restored=Bridge.new(mock:true,data:dir,scenario:scenario).snapshot(s['id'])
   raise 'history changed' unless restored['requestHash']==s['requestHash']&&restored['rawUserOptions']==s['rawUserOptions']&&restored['state']==expected
   if scenario=='success'
    bytes=File.binread(File.join(dir,s['id'],done['outputFilename']));raise 'output hash changed' unless Digest::SHA256.hexdigest(bytes)==done['outputHash']&&restored['outputHash']==done['outputHash']
    raise 'mock wrongly marked visually accepted' unless done['visualAcceptance']=='not-evaluated'
   end
   rejected=false;begin;bridge.generate_generic(d);rescue;rejected=true;end;raise 'duplicate request accepted' unless rejected
   same=bridge.freeze_direct(input);recreated={'id'=>same['id'],'requestHash'=>same['requestHash']};rejected=false;begin;bridge.generate_generic(recreated);rescue;rejected=true;end;raise 'recreated request bypassed ledger' unless rejected
   checks<<{'scenario'=>scenario,'passed'=>true,'terminal_state'=>done['state'],'duplicate_and_recreated_request_rejected'=>true,'history_restored'=>true,'output_hash_verified'=>scenario=='success'}
  rescue=>e
   checks<<{'scenario'=>scenario,'passed'=>false,'error'=>e.message}
  end
 end
end
report={'passed'=>checks.count{|x|x['passed']},'failed'=>checks.count{|x|!x['passed']},'checks'=>checks,'paidCalls'=>0,'networkCalls'=>0,'realImageGenerated'=>false,'scope'=>'Backend lifecycle in process; no HTTP, browser upload or actual model verification'}
File.write(File.join(__dir__,'lifecycle-report.json'),JSON.pretty_generate(report));puts JSON.pretty_generate(report);exit(report['failed']==0 ? 0 : 1)
