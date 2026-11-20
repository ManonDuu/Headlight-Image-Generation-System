# Normal protected maintenance only, after all requests are terminal. No credential access.
require 'net/http';require 'json';require 'digest'
root=File.expand_path(__dir__)
h=Net::HTTP.new('127.0.0.1',8773,nil);h.max_retries=0;h.open_timeout=3;h.read_timeout=20
get=lambda{r=h.get('/api/session');raise 'session unavailable' unless r.code=='200';JSON.parse(r.body)}
raise 'global pause required' unless File.file?(root+'/LIVE-REQUESTS-PAUSED')
before=get.call
raise 'maintained GC session required' unless before['maintenanceAvailable']==true&&before.dig('gcComparison','enabled')==true&&before.dig('gcComparison','remaining')==0
raise 'in-flight request; no restart' if before['history'].any?{|s|s['state']=='running'}
files=Dir[root+'/live-attempts/**/*'].select{|p|File.file?(p)}+Dir[root+'/bridge-jobs/**/*',root+'/bridge-jobs/.internal-reference/**/*'].select{|p|File.file?(p)}+[root+'/LIVE-REQUESTS-PAUSED']
hashes=files.map{|p|[p,Digest::SHA256.file(p).hexdigest]}.to_h
r=Net::HTTP::Post.new('/api/maintenance/restart');r['Origin']='http://127.0.0.1:8773';r['Content-Type']='application/json';r['X-Session-Token']=before['token'];r.body='{}'
response=h.request(r);raise "maintenance refused HTTP #{response.code}" unless response.code=='200'
after=nil
30.times do
  sleep 1
  begin
    candidate=get.call
    if candidate['token']!=before['token'];after=candidate;break;end
  rescue SystemCallError,IOError,EOFError
    # Readiness observation only, never resubmit restart or model calls.
  end
end
raise 'new session not ready; do not repeat restart' unless after
raise 'allowance or authority changed' unless after.dig('gcComparison','remaining')==0&&after['gcComparison']['approval']==before['gcComparison']['approval']&&after['analysisLiveEnabled']==false&&after['generationLiveEnabled']==false
raise 'records changed' unless hashes.all?{|p,sha|File.file?(p)&&Digest::SHA256.file(p).hexdigest==sha}
raise 'generic authority unexpectedly enabled' unless after.dig('genericGC','enabled')==false&&after.dig('genericAnalysis','enabled')==false
raise 'product backend not ready or unexpectedly enabled' unless after.dig('genericGC','productReplacement','version')=='product-replacement-20261018.1'&&after.dig('genericGC','productReplacement','liveEnabled')==false
raise 'analysis repair not loaded' unless after.dig('offlineReference','providerVersion')=='reference-assets-20261018.6'&&after.dig('offlineReference','outputContractVersion')=='analysis-output-contract-2'
raise 'business rules not loaded' unless after.dig('genericGC','businessSpec')=='car-light-direct-20261018.9'
old_states=before['history'].map{|s|[s['id'],s['state']]}.sort
raise 'history changed' unless after['history'].map{|s|[s['id'],s['state']]}.sort==old_states
# Prove stale sessions cannot operate, without another successful restart.
rejected=h.request(r)
raise 'old token unexpectedly valid' unless rejected.code=='400'
result={maintenanceRestart:'passed',sessionRotated:true,staleTokenRejected:true,gcRemaining:0,
 approvalPreserved:true,ledgerAndOutputHashesPreserved:hashes.size,historyPreserved:true,productBackendLoaded:true,businessSpec:after.dig('genericGC','businessSpec'),providerVersion:after.dig('offlineReference','providerVersion'),outputContractVersion:after.dig('offlineReference','outputContractVersion'),productLiveEnabled:false,genericLiveEnabled:false,
 inFlightRequestsAtRestart:0,modelRequestsFromMaintenance:0,credentialReadOrPersistedByVerifier:false}
File.write(root+'/MAINTENANCE-LIVE-VERIFICATION.json',JSON.pretty_generate(result));puts JSON.pretty_generate(result)
