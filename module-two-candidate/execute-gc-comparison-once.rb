# Exactly one authenticated loopback submission after the user launches the selected profile.
# Never reads an API key or sends user-supplied image data; server uses the pinned local input.
require 'net/http';require 'json';require_relative 'generate-content-adapter'
root=File.expand_path(__dir__);h=Net::HTTP.new('127.0.0.1',8773,nil)
h.max_retries=0;h.open_timeout=3;h.read_timeout=15
s=JSON.parse(h.get('/api/session').body)
gc=s['gcComparison']
raise 'selected maintained GC profile not ready' unless s['mock']==false&&s['maintenanceAvailable']==true&&s['analysisLiveEnabled']==false&&s['generationLiveEnabled']==false&&gc&&gc['enabled']&&gc['remaining']==1
a=gc['approval']
raise 'rules version mismatch' unless s['rulesVersion']=='recovered-approved-core-20261017.5'&&a['rulesVersion']==s['rulesVersion']&&a['conservativeMicroUSD']==258560
raise 'unexpected approval' unless a['id']=='generate-content-comparison-20261018-one-call'&&a['endpoint']==GenerateContentAdapter::ENDPOINT&&a['model']==GenerateContentAdapter::MODEL&&a['requestHash']==GenerateContentAdapter::REQUEST_HASH&&a['sourceHash']==GenerateContentAdapter::SOURCE&&a['promptHash']=='20144bb869497f1ce69bf294be38ec49a000962dd67de1a1a8c592280cfb15d9'&&a['budgetMicroUSD']==260000&&a['maxRequests']==1&&a['retries']==0&&a['analysisCalls']==0
raise 'another job running' if s['history'].any?{|job|job['state']=='running'}
raise 'experiment ledger exists' if File.exist?(root+'/live-attempts/'+a['id'])
receipt=root+'/GC-COMPARISON-LIVE-RECEIPT.json'
File.open(receipt,File::WRONLY|File::CREAT|File::EXCL,0600){|f|f.write(JSON.pretty_generate(state:'submitting-once',requestHash:a['requestHash'],analysisCalls:0,budgetMicroUSD:260000))}
r=Net::HTTP::Post.new('/api/experiment/generate-content');r['Origin']='http://127.0.0.1:8773';r['Content-Type']='application/json';r['X-Session-Token']=s['token'];r.body=JSON.generate(requestHash:a['requestHash'])
response=h.request(r)
raise "Submission HTTP #{response.code}; receipt retained, do not retry" unless response.code=='200'
result=JSON.parse(response.body)
safe=result.select{|k,_|%w[id state requestHash analysisCalls budgetMicroUSD].include?(k)}
File.write(receipt,JSON.pretty_generate(safe));puts JSON.generate(safe)
