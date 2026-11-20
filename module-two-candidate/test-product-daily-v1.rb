require 'tmpdir'
require 'timeout'
require_relative 'bridge-server'

checks=[]
def assert(value,message);raise message unless value;end
def rejected
  begin;yield;rescue StandardError;return true;end
  false
end
def terminal(bridge,id)
  Timeout.timeout(12){loop{s=bridge.snapshot(id);return s unless s['state']=='running';sleep 0.02}}
end
# The live-mode policy is exercised with a fake credential and a local response
# fixture. This replacement transport cannot perform network I/O.
class GenerateContentTransport
  class << self;attr_accessor :fixture,:calls,:hold,:entered,:fail_next;end
  def call(endpoint,body,options)
    self.class.calls+=1
    self.class.entered << true if self.class.entered
    self.class.hold.pop if self.class.hold
    if self.class.fail_next
      self.class.fail_next=false
      raise 'fixture timeout; no network request'
    end
    [200,self.class.fixture,{'fixtureOnly'=>true,'networkCalls'=>0}]
  end
end
GenerateContentTransport.fixture=File.binread(File.join(__dir__,'bridge-jobs/3ee67ef451f4be758505cde4/generic-response.json'))
GenerateContentTransport.calls=0
source=File.binread(File.join(__dir__,'../测试素材/2.png'))
product=File.binread(File.join(__dir__,'../测试素材/产品图.png'))
base={'productImageBase64'=>Base64.strict_encode64(product),'productHash'=>Digest::SHA256.hexdigest(product),'productName'=>'LED car bulbs','businessSpec'=>DirectImagePlan::PRODUCT_SPEC,'module'=>'product-replacement','mode'=>'custom','customCopy'=>'Road Visibility','layoutMode'=>'keep-reference','layoutTone'=>'adjust-color','color'=>'#C62828','output'=>{'aspectRatio'=>'1:1','imageSize'=>'2K'},'imageBase64'=>Base64.strict_encode64(source),'sourceHash'=>Digest::SHA256.hexdigest(source),'budgetMicroUSD'=>270000}
Dir.mktmpdir('daily-policy-') do |dir|
  make=lambda do |daily|
    b=Bridge.new(mock:false,data:dir,key:'TEST_NOT_A_REAL_KEY',reference_daily:true,product_daily:daily)
    def b.generic_ledger(binding);File.join(@data,'daily-fixture-'+binding.fetch('requestHash'));end
    b
  end
  bridge=make.call(true)
  assert(bridge.generic_status['enabled'],'daily profile unavailable')
  assert(GenerateContentTransport.calls==0,'startup called model');checks<<'startup and prepare do not call model'
  a=bridge.freeze_direct(base)
  args={'id'=>a['id'],'requestHash'=>a['requestHash']}
  assert(rejected{bridge.generate_generic(args.merge('requestHash'=>'0'*64))},'changed request hash accepted')
  assert(GenerateContentTransport.calls==0,'rejection called model');checks<<'tampered task hash blocked before transport'
  old=make.call(false)
  assert(rejected{old.generate_generic(args)},'old profile gained daily authority');checks<<'legacy profile remains locked'
  GenerateContentTransport.hold=Queue.new;GenerateContentTransport.entered=Queue.new
  bridge.generate_generic(args)
  Timeout.timeout(5){GenerateContentTransport.entered.pop}
  b=bridge.freeze_direct(base.merge('customCopy'=>'Clear Road Details'))
  args_b={'id'=>b['id'],'requestHash'=>b['requestHash']}
  assert(rejected{bridge.generate_generic(args)},'double click accepted')
  assert(rejected{bridge.generate_generic(args_b)},'parallel second task accepted')
  checks<<'duplicate and parallel requests rejected'
  GenerateContentTransport.hold << true
  done=terminal(bridge,a['id']);GenerateContentTransport.hold=nil
  assert(done['state']=='generated-pending-review',done['error']||'fixture failed')
  assert(bridge.instance_variable_get(:@key)=='TEST_NOT_A_REAL_KEY','daily key lost after first task')
  checks<<'successful task keeps credential in memory for next explicit task'
  assert(rejected{bridge.generate_generic(args)},'completed request retried')
  same=bridge.freeze_direct(base)
  assert(same['state']=='frozen','explicit same-input task preparation failed')
  checks<<'same task cannot repeat; identical new task can be prepared'
  GenerateContentTransport.fail_next=true
  bridge.generate_generic(args_b);failed=terminal(bridge,b['id'])
  assert(failed['state']=='stopped','timeout not stopped')
  assert(GenerateContentTransport.calls==2,'failure auto-retried')
  assert(!failed['outputHash'],'failed task exposed successful output')
  checks<<'failure stops once and exposes no fake result'
  c=bridge.freeze_direct(base.merge('customCopy'=>'See the Road Clearly'))
  bridge.generate_generic({'id'=>c['id'],'requestHash'=>c['requestHash']})
  assert(terminal(bridge,c['id'])['state']=='generated-pending-review','new task blocked after earlier failure')
  checks<<'a new explicit task works after a failed task'
  restored=make.call(true)
  assert(restored.snapshot(a['id'])['outputHash']==done['outputHash'],'history result lost after restart')
  assert(rejected{restored.generate_generic(args)},'restart bypassed completed task guard')
  checks<<'restart retains history and completed-task protection'
  assert(GenerateContentTransport.calls==3,'unexpected transport invocation count')
  repeated=restored.repeat_product_task({'id'=>a['id']});assert(GenerateContentTransport.calls==3,'repeat preparation called model');assert(repeated['requestHash']==a['requestHash'],'same settings changed');restored.generate_generic({'id'=>repeated['id'],'requestHash'=>repeated['requestHash']});assert(terminal(restored,repeated['id'])['state']=='generated-pending-review','explicit repeat failed');assert(rejected{restored.generate_generic({'id'=>repeated['id'],'requestHash'=>repeated['requestHash']})},'repeat task executed twice');checks<<'explicit same-input repeat works once; preparation is free'
  assert(GenerateContentTransport.calls==4,'unexpected repeat call count')
end
report={'passed'=>checks.length,'checks'=>checks,'transportFixtureInvocations'=>GenerateContentTransport.calls,'paidCalls'=>0,'networkCalls'=>0,'credential'=>'fake test value only','browserVerified'=>false}
File.write(File.join(__dir__,'product-profile-report.json'),JSON.pretty_generate(report))
puts JSON.pretty_generate(report)
