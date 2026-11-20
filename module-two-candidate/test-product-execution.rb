require_relative 'bridge-server'
require 'tmpdir'
n=0
check=lambda{|ok,label|raise label unless ok;n+=1}
reject=lambda{|&f|begin;f.call;raise 'unexpected acceptance';rescue => e;raise if e.message=='unexpected acceptance';n+=1;end}
reference=File.binread(File.join(__dir__,'assets/81gMZuoRq6L._AC_SL1500_.jpg'))
product=File.binread(File.join(__dir__,'fixtures/small-valid.jpg'))
hash=Digest::SHA256.hexdigest(reference)
analysis=VisualAnalysis.mock_contract(hash,1200,1500)
analysis['regions'][0]['role']='structure'
base={'module'=>'product-replacement','mode'=>'no-copy','output'=>{'aspectRatio'=>'4:5','imageSize'=>'2K'},'layoutTone'=>'keep-reference',
  'budgetMicroUSD'=>270000,'sourceHash'=>hash,'imageBase64'=>Base64.strict_encode64(reference),
  'productHash'=>Digest::SHA256.hexdigest(product),'productImageBase64'=>Base64.strict_encode64(product),
  'productName'=>'OFFLINE fixture only','sceneMode'=>'keep'}
wait=lambda do |b,id|
  300.times do
    s=b.snapshot(id);break s if s['state']!='running';sleep 0.05
  end
end
Dir.mktmpdir('product-execution-') do |root|
  store=File.join(root,'analysis');FileUtils.mkdir_p(File.join(store,'product-targets'))
  File.write(File.join(store,hash+'.json'),JSON.generate(analysis))
  targets={'sourceHash'=>hash,'analysisHash'=>Digest::SHA256.hexdigest(JSON.generate(analysis)),'targetRegions'=>[analysis['regions'][0]['id']]}
  target_path=File.join(store,'product-targets',hash+'.json')
  b=Bridge.new(mock:true,data:File.join(root,'guards'),analysis_store:store)
  reject.call{b.freeze_task(base)}
  File.write(target_path,JSON.generate(targets.merge('analysisHash'=>'wrong')))
  reject.call{b.freeze_task(base)}
  File.write(target_path,JSON.generate(targets))
  reject.call{b.freeze_task(base.merge('targetRegions'=>targets['targetRegions']))}
  reject.call{b.freeze_task(base.merge('budgetMicroUSD'=>260000))}
  reject.call{b.freeze_task(base.merge('productHash'=>hash))}
  %w[success empty error timeout over-budget multiple].each do |scenario|
    dir=File.join(root,scenario);b=Bridge.new(mock:true,data:dir,analysis_store:store,scenario:scenario)
    s=b.freeze_task(base);req={'id'=>s['id'],'requestHash'=>s['genericGC']['requestHash']}
    check.call(s['module']=='product-replacement'&&s.dig('genericGC','inputTokenReserve')==41984,'product binding')
    results=2.times.map{Thread.new{begin;b.generate_generic(req);:ok;rescue;:blocked;end}}.map(&:value)
    check.call(results.sort==[:blocked,:ok],'exactly one dispatch')
    done=wait.call(b,s['id']);check.call(done['state']==(scenario=='success' ? 'mock-result' : 'stopped'),scenario+': '+done['error'].to_s)
    check.call(File.file?(File.join(dir,s['id'],'output.jpg'))==(scenario=='success'),'output exists only on valid result')
    ledger=b.generic_ledger(s['genericGC']);prior=File.binread(ledger+'/binding.json')
    restarted=Bridge.new(mock:true,data:dir,analysis_store:store)
    again=restarted.freeze_task(base)
    reject.call{restarted.generate_generic({'id'=>again['id'],'requestHash'=>again['genericGC']['requestHash']})}
    check.call(File.binread(ledger+'/binding.json')==prior,'reservation retained')
  end
  b=Bridge.new(mock:true,data:File.join(root,'tamper'),analysis_store:store)
  s=b.freeze_task(base);File.binwrite(File.join(root,'tamper',s['id'],'product.jpg'),reference)
  reject.call{b.generate_generic({'id'=>s['id'],'requestHash'=>s['genericGC']['requestHash']})}
  check.call(!File.exist?(b.generic_ledger(s['genericGC'])),'tampered product rejected before reservation')
  # Turn off mock only after preparing an explicitly mock plan: it must never
  # authorize live execution, even if the exact binding was supplied.
  b=Bridge.new(mock:true,data:File.join(root,'denied'),analysis_store:store);s=b.freeze_task(base)
  b.instance_variable_set(:@mock,false);b.instance_variable_set(:@generic_approval,s['genericGC'])
  reject.call{b.generate_generic({'id'=>s['id'],'requestHash'=>s['genericGC']['requestHash']})}
  check.call(b.snapshot(s['id'])['state']=='frozen','live stays blocked')
  pending=Bridge.new(mock:false,data:File.join(root,'needs-analysis'),analysis_store:File.join(root,'empty-analysis'))
  plan=pending.freeze_task(base)
  check.call(plan['state']=='analysis-awaiting-approval','unknown product reference returns analysis plan')
  check.call(plan['liveAnalysisEnabled']==false,'missing analysis never grants authority')
end
puts "PASS #{n} product route/dual-source/errors/concurrency/restart/budget guards; zero network requests"
