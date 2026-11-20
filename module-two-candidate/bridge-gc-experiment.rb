require_relative 'generate-content-adapter'
require_relative 'generate-content-transport'
module BridgeGCExperiment
  GC_COMPARISON_APPROVAL={
    'id'=>'generate-content-comparison-20261018-one-call',
    'endpoint'=>GenerateContentAdapter::ENDPOINT,'model'=>GenerateContentAdapter::MODEL,
    'requestHash'=>GenerateContentAdapter::REQUEST_HASH,'sourceHash'=>GenerateContentAdapter::SOURCE,
    'promptHash'=>'20144bb869497f1ce69bf294be38ec49a000962dd67de1a1a8c592280cfb15d9',
    'rulesVersion'=>'recovered-approved-core-20261017.5','budgetMicroUSD'=>260000,
    'conservativeMicroUSD'=>258560,'maxRequests'=>1,'retries'=>0,'analysisCalls'=>0
  }.freeze
  GC_TASK_ID=Digest::SHA256.hexdigest(GC_COMPARISON_APPROVAL['id'])[0,24]
  def gc_ledger
    File.join(@mock ? @data : File.join(Bridge::ROOT,'live-attempts'),GC_COMPARISON_APPROVAL['id'])
  end
  def gc_comparison_status
    {'enabled'=>@gc_once==true,'approval'=>GC_COMPARISON_APPROVAL,
     'remaining'=>(File.exist?(gc_ledger)||File.exist?(File.join(@data,GC_TASK_ID,'state.json'))) ? 0 : 1}
  end
  def generate_gc_comparison(d)
    raise 'GC comparison startup profile not selected' unless @gc_once
    raise 'fixed experiment request required' unless d=={'requestHash'=>GenerateContentAdapter::REQUEST_HASH}
    @mutex.synchronize do
      raise 'GC comparison already reserved; no repeat' unless gc_comparison_status['remaining']==1
      raise 'missing normally supplied credential' unless @mock||@key
      raise 'rules changed' unless RulesCompiler::VERSION==GC_COMPARISON_APPROVAL['rulesVersion']
      source=File.join(Bridge::ROOT,'bridge-jobs','3bdaaef4bf062f158e862cab')
      plan=GenerateContentAdapter.prepare(File.binread(File.join(source,'request.json')))
      trace=JSON.parse(File.read(File.join(source,'rule-trace.json')))
      raise 'frozen prompt or reference changed' unless trace['promptHash']==GC_COMPARISON_APPROVAL['promptHash']&&Digest::SHA256.file(File.join(source,'reference.jpg')).hexdigest==GC_COMPARISON_APPROVAL['sourceHash']
      # Reserve before starting the background thread; repeated HTTP submissions cannot race.
      p=File.join(@data,GC_TASK_ID);Dir.mkdir(p,0700)
      FileUtils.cp(File.join(source,'reference.jpg'),File.join(p,'reference.jpg'))
      atomic(File.join(p,'rule-trace.json'),trace)
      s={'id'=>GC_TASK_ID,'state'=>'running','mock'=>@mock,'mode'=>'no-copy','sourceHash'=>GenerateContentAdapter::SOURCE,
        'requestHash'=>GenerateContentAdapter::REQUEST_HASH,'prompt'=>JSON.parse(plan['body'])['contents'][0]['parts'][0]['text'],
        'ruleTrace'=>trace,'budgetMicroUSD'=>260000,'visualAcceptance'=>'not-evaluated','createdAt'=>Time.now.utc.iso8601,
        'startedAt'=>Time.now.utc.iso8601,'experiment'=>'generateContent comparison','analysisCalls'=>0}
      atomic(File.join(p,'state.json'),s)
      Thread.new do
        begin
          if @mock
            # Use the normal decoded-image mock fixture; no external transport is created.
            transport=lambda do |*args|
              raise 'simulated GC timeout' if @scenario=='timeout'
              mock_response(p)
              bytes=File.binread(File.join(p,'output.jpg'))
              [200,JSON.generate({'modelVersion'=>GenerateContentAdapter::MODEL,'candidates'=>[{'finishReason'=>'STOP','content'=>{'parts'=>[{'inlineData'=>{'mimeType'=>'image/jpeg','data'=>Base64.strict_encode64(bytes)}}]}}],'usageMetadata'=>{'promptTokenCount'=>0,'candidatesTokenCount'=>0,'thoughtsTokenCount'=>0,'totalTokenCount'=>0}})]
            end
          else
            transport=GenerateContentTransport.new(@key,authorized_once:true)
          end
          # Adapter owns the persistent real ledger; mock adapter's attempt is local to task.
          result=GenerateContentAdapter.execute(plan,p,approval:plan['binding'],transport:transport,mock:@mock,authorized_once:@gc_once)
          atomic(File.join(p,'state.json'),s.merge(result))
        rescue => e
          atomic(File.join(p,'state.json'),s.merge('state'=>'stopped','error'=>e.message,'finishedAt'=>Time.now.utc.iso8601))
        ensure
          @key=nil unless @mock
        end
      end
      s
    end
  rescue Errno::EEXIST
    raise 'GC comparison already reserved; no repeat'
  end
end
