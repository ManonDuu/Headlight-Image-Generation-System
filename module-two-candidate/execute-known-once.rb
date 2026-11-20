# Operator-approved single generation. Loopback API only; no credential/environment access.
require 'net/http';require 'json';require 'digest';require 'base64'
root=File.expand_path(__dir__);origin='http://127.0.0.1:8773'
http=Net::HTTP.new('127.0.0.1',8773,nil);http.open_timeout=5;http.read_timeout=15;http.max_retries=0
call=lambda do |path,data=nil,token=nil|
 r=data ? Net::HTTP::Post.new(path) : Net::HTTP::Get.new(path)
 r['X-Session-Token']=token if token
 if data;r['Origin']=origin;r['Content-Type']='application/json';r.body=JSON.generate(data);end
 res=http.request(r);raise "Local HTTP #{res.code}; stop without retry" unless res.code=='200';JSON.parse(res.body)
end
session=call.call('/api/session')
raise 'unexpected service state' unless session['mock']==false&&session['rulesVersion']=='recovered-approved-core-20261017.3'&&session['remaining']==1&&session['analysisLiveEnabled']==false&&session['history']==[]
raise 'allowance already reserved' if File.exist?(root+'/live-attempts/module-one-single-20261017')
receipt=root+'/KNOWN-REFERENCE-LIVE-RECEIPT.json';raise 'receipt exists; no repeat' if File.exist?(receipt)
expected=JSON.parse(File.read(root+'/KNOWN-REFERENCE-PREFLIGHT.json'))
bytes=File.binread(root+'/assets/81gMZuoRq6L._AC_SL1500_.jpg');raise 'source changed' unless Digest::SHA256.hexdigest(bytes)==expected['sourceHash']
data={'module'=>'reference-reconstruction','mode'=>'no-copy','layoutTone'=>'keep-reference','output'=>{'aspectRatio'=>'4:5','imageSize'=>'2K'},'imageBase64'=>Base64.strict_encode64(bytes),'sourceHash'=>expected['sourceHash'],'budgetMicroUSD'=>260000}
frozen=call.call('/api/freeze',data,session['token']);trace=frozen['ruleTrace']
raise 'not frozen/no analysis permitted' unless frozen['state']=='frozen'&&frozen['mock']==false
raise 'request binding changed' unless frozen['requestHash']==expected['requestHash']&&trace['promptHash']==expected['promptHash']&&frozen['sourceHash']==expected['sourceHash']
ids=%w[structure visual-reference layout-freeze scene-difference role-boundary proof typography readability brightness joint-acceptance copy-no-marketing]
raise 'rule or budget mismatch' unless trace['version']==expected['rulesVersion']&&trace['appliedRuleIds']==ids&&trace['checks'].size==11&&trace['inputAccounting']['conservativeMicroUSD']<=260000&&frozen['budgetMicroUSD']==260000
raise 'wrong candidate' unless trace['analysis']['origin']=='manual'
File.write(receipt,JSON.pretty_generate({'id'=>frozen['id'],'requestHash'=>frozen['requestHash'],'state'=>'frozen-verified-before-single-submit','analysisCalls'=>0,'budgetMicroUSD'=>260000}))
# Exactly one POST. An uncertain response leaves the receipt and prevents rerunning.
result=call.call('/api/generate',{'id'=>frozen['id'],'requestHash'=>frozen['requestHash']},session['token'])
File.write(receipt,JSON.pretty_generate({'id'=>frozen['id'],'requestHash'=>frozen['requestHash'],'state'=>result['state'],'analysisCalls'=>0,'generationSubmissions'=>1,'budgetMicroUSD'=>260000}))
puts JSON.generate(id:result['id'],state:result['state'],requestHash:result['requestHash'],generationSubmissions:1,analysisCalls:0)
