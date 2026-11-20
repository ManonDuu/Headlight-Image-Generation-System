# Exact newly authorized single analysis. No key access, no generation, no retry.
require_relative 'bridge-server'
require 'net/http'
root=Bridge::ROOT
plan=Object.new.extend(BridgeWireAnalysis).wire_analysis_plan
raise 'candidate budget drift' unless plan['conservativeMicroUSD']<=20000&&plan['binding']==BridgeWireAnalysis::WIRE_BINDING
ledger=File.join(root,'live-attempts/schema-projection-analysis-20261018-one-call')
raise 'candidate already consumed' if File.exist?(ledger)
h=Net::HTTP.new('127.0.0.1',8773,nil);h.max_retries=0;h.open_timeout=3;h.read_timeout=180
r=h.get('/api/session');raise 'session unavailable' unless r.code=='200';s=JSON.parse(r.body)
raise 'wrong session or in-flight task' unless s['maintenanceAvailable']&&s.dig('gcComparison','enabled')&&s.dig('gcComparison','remaining')==0&&s['history'].none?{|x|x['state']=='running'}
receipt=File.join(root,'generic-analysis-validation-20261018/schema-projection-dispatch.json')
File.open(receipt,File::WRONLY|File::CREAT|File::EXCL,0600){|f|f.write(JSON.pretty_generate({'binding'=>plan['binding'],'conservativeMicroUSD'=>plan['conservativeMicroUSD'],'generationCalls'=>0,'retries'=>0,'at'=>Time.now.utc.iso8601}))}
r=Net::HTTP::Post.new('/api/analysis-wire/execute');r['Origin']='http://127.0.0.1:8773';r['Content-Type']='application/json';r['X-Session-Token']=s['token'];r.body=JSON.generate(plan['binding'])
response=h.request(r)
result=JSON.parse(response.body)
File.write(File.join(root,'generic-analysis-validation-20261018/schema-projection-local-result.json'),JSON.pretty_generate({'httpStatus'=>response.code.to_i,'result'=>result}))
puts JSON.generate({'localHttpStatus'=>response.code.to_i,'state'=>result['state'],'error'=>result['error'],'usage'=>result['usage'],'regions'=>result.dig('analysis','regions')&.size,'labels'=>result.dig('analysis','labels')&.size,'generationCalls'=>0,'retries'=>0})
