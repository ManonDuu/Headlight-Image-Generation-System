require_relative 'bridge-server'
require 'tmpdir'
n=0;check=lambda{|ok,label|raise label unless ok;n+=1}
reject=lambda{|&f|begin;f.call;raise 'unexpected acceptance';rescue => e;raise if e.message=='unexpected acceptance';n+=1;end}
bytes=File.binread(File.join(__dir__,'assets/81gMZuoRq6L._AC_SL1500_.jpg'))
base={'module'=>'reference-reconstruction','mode'=>'no-copy','output'=>{'aspectRatio'=>'4:5','imageSize'=>'2K'},'layoutTone'=>'keep-reference','budgetMicroUSD'=>260000,'sourceHash'=>Digest::SHA256.hexdigest(bytes),'imageBase64'=>Base64.strict_encode64(bytes)}
wait=lambda{|b,id|200.times{state=b.snapshot(id);break state if state['state']!='running';sleep 0.05}}
Dir.mktmpdir('generic-execution-') do |root|
  RulesCompiler::SIZES.each do |ratio,dims|
    dir=File.join(root,ratio.tr(':','-'));b=Bridge.new(mock:true,data:dir)
    s=b.freeze_task(base.merge('output'=>{'aspectRatio'=>ratio,'imageSize'=>'2K'}))
    req={'id'=>s['id'],'requestHash'=>s['genericGC']['requestHash']}
    outcomes=2.times.map{Thread.new{begin;b.generate_generic(req);:ok;rescue;:blocked;end}}.map(&:value)
    check.call(outcomes.sort==[:blocked,:ok],'concurrent submission reserved once')
    done=wait.call(b,s['id']);check.call(done['state']=='mock-result',"native #{ratio}: #{done['error']}")
    check.call(Digest::SHA256.file(File.join(dir,s['id'],'output.jpg')).hexdigest==done['outputHash'],'native output preserved')
    raw=File.read(File.join(dir,s['id'],'generic-response.json'))
    reject.call{GenerateContentAdapter.parse(200,raw,expected_dimensions:dims.reverse)} unless dims==dims.reverse
    ledger=b.generic_ledger(s['genericGC']);before=Digest::SHA256.file(ledger+'/binding.json').hexdigest
    restarted=Bridge.new(mock:true,data:dir)
    repeated=restarted.freeze_task(base.merge('output'=>{'aspectRatio'=>ratio,'imageSize'=>'2K'}))
    reject.call{restarted.generate_generic({'id'=>repeated['id'],'requestHash'=>repeated['genericGC']['requestHash']})}
    check.call(Digest::SHA256.file(ledger+'/binding.json').hexdigest==before,'ledger retained across restart/recreated task')
  end
  %w[empty error timeout over-budget multiple].each do |scenario|
    dir=File.join(root,scenario);b=Bridge.new(mock:true,data:dir,scenario:scenario)
    s=b.freeze_task(base);req={'id'=>s['id'],'requestHash'=>s['genericGC']['requestHash']}
    b.generate_generic(req);done=wait.call(b,s['id'])
    check.call(done['state']=='stopped',scenario+' stops')
    check.call(!File.exist?(File.join(dir,s['id'],'output.jpg')),scenario+' no deliverable')
    reject.call{b.generate_generic(req)}
    check.call(File.file?(b.generic_ledger(s['genericGC'])+'/binding.json'),scenario+' reservation consumed')
  end
  dir=File.join(root,'live-denied');b=Bridge.new(mock:false,data:dir)
  # Simulate a crash after reservation but before any response is recorded.
  crash_dir=File.join(root,'interrupted');crash=Bridge.new(mock:true,data:crash_dir)
  interrupted=crash.freeze_task(base)
  ledger=crash.generic_ledger(interrupted['genericGC']);Dir.mkdir(ledger)
  File.write(ledger+'/binding.json',JSON.generate(interrupted['genericGC']))
  interrupted['state']='running';File.write(File.join(crash_dir,interrupted['id'],'state.json'),JSON.generate(interrupted))
  recovered=Bridge.new(mock:true,data:crash_dir)
  state=recovered.snapshot(interrupted['id'])
  check.call(state['state']=='stopped'&&state['error'].include?('remote outcome unknown'),'interrupted remote result stays unknown')
  reject.call{recovered.generate_generic({'id'=>state['id'],'requestHash'=>state['genericGC']['requestHash']})}
  duplicate=recovered.freeze_task(base)
  reject.call{recovered.generate_generic({'id'=>duplicate['id'],'requestHash'=>duplicate['genericGC']['requestHash']})}
  check.call(!File.exist?(File.join(crash_dir,state['id'],'output.jpg')),'unknown result has no invented deliverable')
  s=b.freeze_task(base)
  reject.call{b.generate_generic({'id'=>s['id'],'requestHash'=>s['genericGC']['requestHash']})}
  check.call(b.snapshot(s['id'])['state']=='frozen','no live request or reservation without fresh authority')
  dir=File.join(root,'analysis');b=Bridge.new(mock:true,data:dir)
  plan=b.analyze_generic(base)
  check.call(plan['state']=='analysis-awaiting-approval','generic analysis bypasses known manual cache')
  approval={'requestHash'=>plan['requestHash'],'sourceHash'=>base['sourceHash'],'budgetMicroUSD'=>20000}
  result=b.analyze_generic(base.merge('approval'=>approval))
  check.call(result['state']=='analysis-ready'&&!result['automaticGeneration'],'analysis does not generate')
  check.call(b.analyze_generic(base)['state']=='analysis-cached','analysis no duplicate')
  ai=b.freeze_task(base.merge('mode'=>'ai-rewrite'))
  check.call(ai.dig('ruleTrace','copyPolicy','default')=='preserve-original-capitalization-style','explicit AI default')
  check.call(ai['prompt'].include?('product parameter')&&ai['prompt'].include?('functional label verbatim'),'AI protection instructions')
end
puts "PASS #{n} general execution/native sizes/errors/budgets/restart/analysis checks; zero network calls"
