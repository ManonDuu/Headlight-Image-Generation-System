# Exact newly authorized single analysis. No key access, no generation, no retry.
require_relative 'bridge-server'
require 'net/http'
root=Bridge::ROOT
plan=Object.new.extend(BridgeAnalysisGC).analysis_gc_enum_plan
raise 'candidate budget drift' unless plan['binding']['conservativeMicroUSD']<=20000
ledger=File.join(root,'live-attempts/analysis-gc-cb4b67f9c84cf6ab8df4764d82737d6e8b4b26620996e78772a37891542c6e61')
raise 'candidate already consumed' if File.exist?(ledger)
h=Net::HTTP.new('127.0.0.1',8773,nil);h.max_retries=0;h.open_timeout=3;h.read_timeout=180
r=h.get('/api/session');raise 'session unavailable' unless r.code=='200';s=JSON.parse(r.body)
raise 'wrong session or in-flight task' unless s['maintenanceAvailable']&&s.dig('gcComparison','enabled')&&s.dig('gcComparison','remaining')==0&&s['history'].none?{|x|x['state']=='running'}
receipt=File.join(root,'analysis-gc-validation-20261018/enum-dispatch.json')
File.open(receipt,File::WRONLY|File::CREAT|File::EXCL,0600){|f|f.write(JSON.pretty_generate({'binding'=>plan['binding'],'conservativeMicroUSD'=>plan['binding']['conservativeMicroUSD'],'generationCalls'=>0,'retries'=>0,'at'=>Time.now.utc.iso8601}))}
r=Net::HTTP::Post.new('/api/analysis-gc-enum/execute');r['Origin']='http://127.0.0.1:8773';r['Content-Type']='application/json';r['X-Session-Token']=s['token'];r.body=JSON.generate(plan['binding'])
response=h.request(r)
result=JSON.parse(response.body)
File.write(File.join(root,'analysis-gc-validation-20261018/enum-local-result.json'),JSON.pretty_generate({'httpStatus'=>response.code.to_i,'result'=>result}))
puts JSON.generate({'localHttpStatus'=>response.code.to_i,'state'=>result['state'],'error'=>result['error'],'usage'=>result['usage'],'regions'=>result.dig('analysis','regions')&.size,'labels'=>result.dig('analysis','labels')&.size,'generationCalls'=>0,'retries'=>0})
