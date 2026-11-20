# Exactly one local POST can dispatch the explicitly authorized analysis.
# No credential access; no automatic retry; receipt persists before dispatch.
require 'net/http';require 'json';require 'digest';require 'base64';require 'time'
root=File.expand_path(__dir__)
plan=JSON.parse(File.read(root+'/generic-analysis-validation-20261018/analysis-plan.json'))
bytes=File.binread(root+'/assets/81gMZuoRq6L._AC_SL1500_.jpg')
raise 'source changed' unless Digest::SHA256.hexdigest(bytes)==plan.dig('binding','sourceHash')
raise 'request changed' unless Digest::SHA256.hexdigest(JSON.generate(plan['request']))==plan['requestHash']&&plan['requestHash']=='e40147c2533608e8170a56f98331e0a86253c9a601a336f53d93ed230f30bb4a'
raise 'already reserved; no repeat' if Dir.exist?(root+'/live-attempts/generic-analysis-20261018-one-call')
h=Net::HTTP.new('127.0.0.1',8773,nil);h.max_retries=0;h.open_timeout=3;h.read_timeout=180
session=JSON.parse(h.get('/api/session').body)
raise 'wrong session' unless session['mock']==false&&session['maintenanceAvailable']==true&&session.dig('gcComparison','remaining')==0&&session.dig('genericGC','enabled')==false
raise 'another task running' if session['history'].any?{|x|x['state']=='running'}
binding={'requestHash'=>plan['requestHash'],'budgetMicroUSD'=>20000,'sourceHash'=>plan['binding']['sourceHash']}
receipt=root+'/generic-analysis-validation-20261018/dispatch-receipt.json'
File.open(receipt,File::WRONLY|File::CREAT|File::EXCL,0600){|f|f.write(JSON.pretty_generate(binding.merge('state'=>'dispatching','purpose'=>'real visual analysis without manual seed; no generation','at'=>Time.now.utc.iso8601,'maxRequests'=>1,'retries'=>0)))}
r=Net::HTTP::Post.new('/api/generic/analyze');r['Origin']='http://127.0.0.1:8773';r['Content-Type']='application/json';r['X-Session-Token']=session['token']
r.body=JSON.generate({'sourceHash'=>binding['sourceHash'],'imageBase64'=>Base64.strict_encode64(bytes),'approval'=>binding})
response=h.request(r)
File.binwrite(root+'/generic-analysis-validation-20261018/local-result.json',response.body)
result=JSON.parse(response.body)
File.write(receipt,JSON.pretty_generate(binding.merge('state'=>'returned','localHttpStatus'=>response.code.to_i,'resultState'=>result['state'],'error'=>result['error'],'at'=>Time.now.utc.iso8601,'maxRequests'=>1,'retries'=>0)))
puts JSON.generate({'localHttpStatus'=>response.code.to_i,'state'=>result['state'],'error'=>result['error'],'automaticGeneration'=>result['automaticGeneration']})
