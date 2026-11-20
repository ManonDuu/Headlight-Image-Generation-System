require_relative 'bridge-server'
require 'tmpdir'
class RecordedBridge < Bridge
  attr_reader :responses
  def mock_response(path)
    @responses=(@responses||0)+1
    super
  end
end
n=0;check=lambda{|ok,label|raise label unless ok;n+=1}
Dir.mktmpdir('recorded-incomplete-') do |dir|
  live=Bridge.new(mock:false,data:dir+'/locked',audited_once:true)
  begin;live.generate('invalid','invalid');raise 'live guard missing';rescue RuntimeError=>e;check.call(e.message.include?('live generation locked'),'all live profiles locked before credentials/job/transport');end
  b=RecordedBridge.new(mock:true,data:dir+'/mock',audited_once:true,scenario:'recorded-incomplete')
  bytes=File.binread(Bridge::ROOT+'/assets/81gMZuoRq6L._AC_SL1500_.jpg')
  frozen=b.freeze_task({'module'=>'reference-reconstruction','mode'=>'no-copy','layoutTone'=>'keep-reference','output'=>{'aspectRatio'=>'4:5','imageSize'=>'2K'},'sourceHash'=>Digest::SHA256.hexdigest(bytes),'imageBase64'=>Base64.strict_encode64(bytes),'budgetMicroUSD'=>260000})
  b.generate(frozen['id'],frozen['requestHash'])
  deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+5
  loop do
    break if b.snapshot(frozen['id'])['state']!='running'
    raise 'infinite wait regression' if Process.clock_gettime(Process::CLOCK_MONOTONIC)>deadline
    sleep 0.02
  end
  s=b.snapshot(frozen['id']);path=dir+'/mock/'+frozen['id']
  check.call(s['state']=='stopped'&&s['providerStatus']=='incomplete','incomplete is terminal and never success')
  check.call(s['error'].include?('without retry or fallback'),'accurate failure diagnosis')
  check.call(s['usage']['total_output_tokens']==1025&&s['usage']['total_thought_tokens']==0,'actual usage preserved')
  check.call(s['http-status.txt']=='200'&&s['transport-exit-code.txt']=='0','HTTP success distinct from result failure')
  check.call(s['hasOutputImage']==false&&!File.exist?(path+'/output.jpg'),'no fabricated/hidden accepted image')
  check.call(s['visualAcceptance']=='not-evaluated','no visual acceptance')
  check.call(b.responses==1,'one response only; no fallback')
  begin;b.generate(frozen['id'],frozen['requestHash']);raise 'repeat accepted';rescue RuntimeError=>e;check.call(e.message.include?('already attempted'),'repeat rejected');end
  check.call(b.responses==1,'repeat makes no second call')
  check.call(Digest::SHA256.file(path+'/response.json').hexdigest=='bf97b99dae1567834b3ca5a0bea1d24e583e56858032048d7d27a1402329041d','exact raw fixture preserved')
end
puts "PASS #{n} recorded incomplete regression checks; mock only, no network."
