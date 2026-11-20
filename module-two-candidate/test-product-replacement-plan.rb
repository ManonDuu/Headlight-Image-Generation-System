require_relative 'product-replacement-plan'
require 'tmpdir'
def prepare(*args,**kwargs)
 ProductReplacementPlan.prepare(*args,**kwargs.merge(allow_mock:true))
end
n=0
check=lambda{|v|raise 'assertion failed' unless v;n+=1}
reject=lambda do |&b|
 begin;b.call;raise 'unexpected acceptance';rescue VisualAnalysis::Invalid,RulesCompiler::Invalid;n+=1;end
end
reference=File.binread(File.join(__dir__,'assets/81gMZuoRq6L._AC_SL1500_.jpg'))
# Synthetic parser fixture, NOT a usable product photo and never transmitted.
product=File.binread(File.join(__dir__,'fixtures/small-valid.jpg'))
a=VisualAnalysis.mock_contract(Digest::SHA256.hexdigest(reference),1200,1500)
a["regions"][0]["role"]="structure"
opts={'mode'=>'no-copy','output'=>{'aspectRatio'=>'4:5','imageSize'=>'2K'},'layoutTone'=>'keep-reference','sceneMode'=>'keep','productName'=>'OFFLINE synthetic fixture','targetRegions'=>[a['regions'][0]['id']]}
plan=nil
%w[keep change].product(%w[keep-layout no-copy custom ai-rewrite remove-all-copy],RulesCompiler::SIZES.keys).each do |scene,mode,ratio|
 o=Marshal.load(Marshal.dump(opts));o['mode']=mode;o['sceneMode']=scene;o['output']['aspectRatio']=ratio;o['customCopy']='Exact CASE' if mode=='custom'
 p=prepare(reference,product,a,o,allow_mock:true);body=JSON.parse(p['body']);parts=body['contents'][0]['parts']
 check.call(ProductReplacementPlan.validate(p))
 check.call(p['binding']['expectedDimensions']==RulesCompiler::SIZES[ratio])
 check.call(Base64.strict_decode64(parts[1]['inlineData']['data'])==reference&&Base64.strict_decode64(parts[2]['inlineData']['data'])==product)
 check.call(p['trace']['selectedOptions']['sceneMode']==scene&&parts[0]['text'].include?(scene=='keep' ? 'Keep reference background' : 'Change only non-product background'))
 check.call(parts[0]['text'].include?('Preserve its geometry')&&!parts[0]['text'].include?('Change concrete same-type scene details'))
 plan=p if scene=='keep'&&mode=='no-copy'&&ratio=='4:5'
end
check.call(plan['binding']['conservativeMicroUSD']==266752&&plan['binding']['budgetMicroUSD']==270000&&plan['binding']['providerDollarCap']==false)
check.call(plan['binding']['retries']==0&&plan['binding']['maxRequests']==1&&plan['binding']['analysisCalls']==0)
reject.call{prepare(reference,reference,a,opts)}
reject.call{prepare(product,reference,a,opts)}
reject.call{prepare(reference,'invalid',a,opts)}
reject.call{prepare(reference,product,a,opts.merge('targetRegions'=>['unknown']))}
reject.call{prepare(reference,product,a,opts.merge('targetRegions'=>[]))}
reject.call{prepare(reference,product,a,opts.merge('sceneMode'=>'invent'))}
reject.call{prepare(reference,product,a,opts.merge('productName'=>''))}
reject.call{prepare(reference,product,a,opts.merge('prompt'=>'override'))}
reject.call{prepare(reference,product,a,opts.merge('budgetMicroUSD'=>1000000))}
reject.call{prepare(reference,product,a,opts.merge('customCopy'=>'conflicting'))}
reject.call{prepare(reference,product,a,opts.merge('output'=>{'aspectRatio'=>'custom','imageSize'=>'2K','width'=>1000,'height'=>1000}))}
check.call(prepare(reference,product,a,opts.merge('output'=>{'aspectRatio'=>'custom','imageSize'=>'2K','width'=>2048,'height'=>2048}),allow_mock:true).dig('binding','expectedDimensions')==[2048,2048])
%w[body binding analysis options trace].each do |field|
 p=Marshal.load(Marshal.dump(plan));field=='body' ? p[field]+=' ' : p[field]['extra']='tamper'
 reject.call{ProductReplacementPlan.validate(p)}
end
%w[budgetMicroUSD inputTokenReserve maxOutputTokens productHash sourceHash requestHash].each do |field|
 p=Marshal.load(Marshal.dump(plan));p['binding'][field]=0;reject.call{ProductReplacementPlan.validate(p)}
end
p=Marshal.load(Marshal.dump(plan));body=JSON.parse(p['body']);body['contents'][0]['parts'][1],body['contents'][0]['parts'][2]=body['contents'][0]['parts'][2],body['contents'][0]['parts'][1];p['body']=JSON.generate(body);reject.call{ProductReplacementPlan.validate(p)}
reject.call{ProductReplacementPlan.prepare(reference,product,a,opts)}
weather=Marshal.load(Marshal.dump(a));weather["regions"][0]["role"]="weather-carrier"
reject.call{prepare(reference,product,weather,opts)}
remove=prepare(reference,product,a,opts.merge("mode"=>"remove-all-copy"))
check.call(JSON.parse(remove["body"])["contents"][0]["parts"][0]["text"].include?("Remove ALL added overlay text"))
check.call(remove["trace"]["appliedRuleIds"].include?("remove-all-scope"))
Dir.mktmpdir('product-offline-') do |root|
 reject.call{ProductReplacementPlan.reserve_simulation(plan,root,plan['binding'].merge('budgetMicroUSD'=>1))}
 check.call(Dir.children(root).empty?)
 results=2.times.map{Thread.new{begin;ProductReplacementPlan.reserve_simulation(plan,root,plan['binding'])['networkRequests'];rescue VisualAnalysis::Invalid;:blocked;end}}.map(&:value)
 check.call(results.sort_by(&:to_s)==[0,:blocked])
 before=Dir[File.join(root,'**/*')].select{|f|File.file?(f)}.map{|f|[f,Digest::SHA256.file(f).hexdigest]}
 reject.call{ProductReplacementPlan.reserve_simulation(JSON.parse(JSON.generate(plan)),root,plan['binding'])}
 check.call(before==Dir[File.join(root,'**/*')].select{|f|File.file?(f)}.map{|f|[f,Digest::SHA256.file(f).hexdigest]})
end
puts "PASS #{n} product replacement offline checks; synthetic product fixture; zero network requests"
