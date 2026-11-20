require_relative 'generic-gc-plan'
require 'tmpdir'
n=0
check=lambda{|v|raise 'assertion failed' unless v;n+=1}
reject=lambda do |&block|
  begin;block.call;raise 'unexpected acceptance';rescue VisualAnalysis::Invalid,RulesCompiler::Invalid;n+=1;end
end
bytes=File.binread(File.join(__dir__,'assets','81gMZuoRq6L._AC_SL1500_.jpg'))
a=JSON.parse(File.read(Dir[File.join(__dir__,'analysis-cache','*.json')].first))
base={'mode'=>'no-copy','output'=>{'aspectRatio'=>'4:5','imageSize'=>'2K'},'layoutTone'=>'keep-reference'}
plan=nil
%w[keep-layout no-copy custom ai-rewrite].product(RulesCompiler::SIZES.keys).each do |mode,ratio|
  opts=Marshal.load(Marshal.dump(base));opts['mode']=mode;opts['output']['aspectRatio']=ratio
  opts['customCopy']='Exact CASE 123' if mode=='custom'
  p=GenericGCPlan.prepare(bytes,a,opts);body=JSON.parse(p['body'])
  check.call(GenericGCPlan.validate(p))
  check.call(body['generationConfig']['imageConfig']['aspectRatio']==ratio&&p['binding']['expectedDimensions']==RulesCompiler::SIZES[ratio])
  check.call(Base64.strict_decode64(body['contents'][0]['parts'][1]['inlineData']['data'])==bytes)
  check.call(body['contents'][0]['parts'][0]['text'].include?('Exact CASE 123')) if mode=='custom'
  plan=p if mode=='no-copy'&&ratio=='4:5'
end
reject.call{GenericGCPlan.prepare(bytes,a,base.merge('prompt'=>'override'))}
check.call(GenericGCPlan.prepare(bytes,a,base.merge('mode'=>'ai-rewrite')).dig('trace','copyPolicy','historicalConventionRecovered')==false)
reject.call{GenericGCPlan.prepare(bytes,a.merge('sourceHash'=>'0'*64),base)}
reject.call{GenericGCPlan.prepare(bytes,a.merge('width'=>1201),base)}
mock=VisualAnalysis.mock_contract(Digest::SHA256.hexdigest(bytes),1200,1500)
reject.call{GenericGCPlan.prepare(bytes,mock,base)}
check.call(GenericGCPlan.prepare(bytes,mock,base,allow_mock:true)['binding']['mock'])
%w[body binding analysis options trace].each do |field|
  tampered=Marshal.load(Marshal.dump(plan))
  field=='body' ? tampered[field]+=' ' : tampered[field]['extra']='tamper'
  reject.call{GenericGCPlan.validate(tampered)}
end
Dir.mktmpdir('generic-gc-offline-') do |dir|
  reject.call{GenericGCPlan.reserve_simulation(plan,dir,plan['binding'].merge('budgetMicroUSD'=>300000))}
  check.call(Dir.children(dir).empty?)
  results=2.times.map{Thread.new{begin;GenericGCPlan.reserve_simulation(plan,dir,plan['binding'])['networkRequests'];rescue VisualAnalysis::Invalid;:blocked;end}}.map(&:value)
  check.call(results.sort_by(&:to_s)==[0,:blocked])
  reject.call{GenericGCPlan.reserve_simulation(JSON.parse(JSON.generate(plan)),dir,plan['binding'])}
  check.call(Dir.children(dir).size==1)
end
puts "PASS #{n} generic GC mapping/binding/reservation checks; zero network requests"
