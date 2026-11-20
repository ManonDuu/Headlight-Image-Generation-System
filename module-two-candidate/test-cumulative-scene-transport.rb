require_relative 'cumulative-scene-transport';require 'tmpdir';require 'fileutils'
checks=[];calls=0
Dir.mktmpdir do |root|
 body=JSON.generate({'contents'=>[{'role'=>'user','parts'=>[{'text'=>'offline fixture'}]}],'generationConfig'=>{'candidateCount'=>1,'maxOutputTokens'=>4096,'responseModalities'=>['IMAGE'],'thinkingConfig'=>{'thinkingLevel'=>'MINIMAL'},'imageConfig'=>{'imageSize'=>'2K','aspectRatio'=>'4:5'}}})
 h=Digest::SHA256.hexdigest(body);spec={'requestHash'=>h,'reserveMicroUSD'=>410000,'boundMicroUSD'=>409600,'endpoint'=>CumulativeSceneTransport::ENDPOINT,'retries'=>0,'maxRequests'=>1}
 seed=lambda do |dir,history=5340000|
  FileUtils.mkdir_p(dir);File.write(dir+'/ledger.json',JSON.generate({'version'=>1,'enabled'=>true,'capMicroUSD'=>10000000,'history'=>[{'reserveMicroUSD'=>history}],'approval'=>{'approvedRequests'=>{h=>spec}},'requests'=>{},'events'=>[]}))
 end
 make=lambda{|dir,backend|CumulativeSceneTransport.new(spec:spec,mock:true,offline_ledger:dir,offline_transport:backend)}
 reject=lambda{|&f|begin;f.call;raise 'unexpected acceptance';rescue=>e;raise if e.message=='unexpected acceptance';end}
 backend=lambda{|*args|calls+=1;[200,'{"ok":true}',{'curlExitCode'=>0}]};dir=root+'/over';seed.call(dir,9700000);reject.call{make.call(dir,backend).call(spec['endpoint'],body,{retries:0,timeoutSeconds:180})};raise unless calls==0;checks<<'over-budget rejected before any backend invocation'
 dir=root+'/success';seed.call(dir);workers=8.times.map{Thread.new{begin;make.call(dir,backend).call(spec['endpoint'],body,{retries:0,timeoutSeconds:180});true;rescue;false;end}};raise unless workers.map(&:value).count(true)==1&&calls==1;checks<<'concurrent module entry points produce one transport call and one reserve/dispatch/settle'
 dir=root+'/unknown';seed.call(dir);unknown=lambda{|*_|calls+=1;[0,'partial',{'curlExitCode'=>28}]};make.call(dir,unknown).call(spec['endpoint'],body,{retries:0,timeoutSeconds:180});reject.call{make.call(dir,backend).call(spec['endpoint'],body,{retries:0,timeoutSeconds:180})};raise unless calls==2;ledger=JSON.parse(File.read(dir+'/ledger.json'));raise unless ledger['requests'][h]['state']=='uncertain-reserve-retained';checks<<'timeout preserves ceiling and fresh transport instance cannot resend'
 dir=root+'/crash';seed.call(dir);pid=fork{t=make.call(dir,lambda{|*_|exit! 9});t.call(spec['endpoint'],body,{retries:0,timeoutSeconds:180})};Process.wait(pid);raise unless JSON.parse(File.read(dir+'/ledger.json'))['requests'][h]['state']=='dispatched-uncertain';reject.call{make.call(dir,backend).call(spec['endpoint'],body,{retries:0,timeoutSeconds:180})};checks<<'process death after dispatch persists unknown marker and forbids recovery resend'
 checks<<'all tests use injected offline backend; no network or credentials'
end
File.write('diagnostics/cumulative-budget/transport-tests.json',JSON.pretty_generate({checks:checks,externalCalls:0}));puts checks
