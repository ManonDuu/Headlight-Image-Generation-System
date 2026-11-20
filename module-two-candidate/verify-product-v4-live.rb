require_relative 'bridge-server'
require 'timeout'
report_path=File.join(__dir__,'product-v4-live-report.json')
raise 'existing run record; no repeated paid test' if File.exist?(report_path)
boot=JSON.parse(STDIN.read);key=boot.delete('key');raise 'credential missing' unless key.is_a?(String)&&!key.empty?
bridge=Bridge.new(mock:false,data:File.join(__dir__,'bridge-jobs'),key:key,reference_daily:true,product_daily:true)
raise 'existing active task' if Dir.glob(File.join(__dir__,'bridge-jobs/*/state.json')).any?{|f|JSON.parse(File.read(f))['state']=='running'}
prior=JSON.parse(File.read(File.join(__dir__,'bridge-jobs/afcfc360e26b95ffbf379f94/state.json')))
report={'state'=>'started','maximumImages'=>2,'budgetMicroUSD'=>540000,'automaticRetries'=>0,'tasks'=>[]}
File.write(report_path,JSON.pretty_generate(report))
last=prior
2.times do
 s=bridge.repeat_product_task({'id'=>last.fetch('id')});entry={'id'=>s['id'],'state'=>'reserved','requestHash'=>s['requestHash']};report['tasks']<<entry;File.write(report_path,JSON.pretty_generate(report))
 bridge.generate_generic({'id'=>s['id'],'requestHash'=>s['requestHash']})
 Timeout.timeout(220){loop{s=bridge.snapshot(s['id']);break unless s['state']=='running';sleep 1}}
 entry.merge!('state'=>s['state'],'error'=>s['error'],'outputFilename'=>s['outputFilename'],'outputHash'=>s['outputHash']);File.write(report_path,JSON.pretty_generate(report));puts JSON.generate(entry);STDOUT.flush
 if s['state']!='generated-pending-review';report['state']='stopped-no-retry';File.write(report_path,JSON.pretty_generate(report));exit 1;end
 last=s
end
report['state']='awaiting-visual-review';File.write(report_path,JSON.pretty_generate(report))
