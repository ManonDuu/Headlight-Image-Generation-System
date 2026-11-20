# Explicit single corrected-schema analysis authorized 2026-10-18.
# No generation authority, no retries, no reuse of the original analysis ledger.
require_relative 'analysis-wire-candidate'
module BridgeWireAnalysis
  WIRE_BINDING={'requestHash'=>'2aee2e17ee08048fc5fb17a4b0dc47d5fc3ec0bdce50acda7d030c062e0aeafe',
    'sourceHash'=>'d8b87596d3ea2218154b03abafd55333a8f46aa7fcdaca0f53fb63239c2d73ef','budgetMicroUSD'=>20000}.freeze
  def wire_analysis_plan
    original=JSON.parse(File.read(File.join(Bridge::ROOT,'generic-analysis-validation-20261018/analysis-plan.json')))
    request=original.fetch('request');bytes=Base64.strict_decode64(request.fetch('input')[1].fetch('data'))
    raise 'original source changed' unless Digest::SHA256.hexdigest(bytes)==WIRE_BINDING['sourceHash']
    raise 'original request changed' unless request==VisualAnalysis.request(bytes,original['width'],original['height'])&&Digest::SHA256.hexdigest(JSON.generate(request))==AuthorizedAnalysis20261018::BINDING['requestHash']
    candidate=AnalysisWireCandidate.prepare(request)
    raise 'candidate changed' unless candidate['requestHash']==WIRE_BINDING['requestHash']
    # Current verified standard prices: input .30/M, output including thought2.50/M.
    conservative=(VisualAnalysis::INPUT_ALLOWANCE*0.30+VisualAnalysis::OUTPUT_LIMIT*2.50).ceil
    raise 'budget or limits changed' unless conservative==15156&&conservative<=WIRE_BINDING['budgetMicroUSD']&&VisualAnalysis::OUTPUT_LIMIT==4096
    candidate.merge('width'=>original['width'],'height'=>original['height'],'binding'=>WIRE_BINDING,'conservativeMicroUSD'=>conservative)
  end
  def wire_analysis_ledger
    File.join(@mock ? @data : File.join(Bridge::ROOT,'live-attempts'),'schema-projection-analysis-20261018-one-call')
  end
  def execute_wire_analysis(d)
    raise 'exact corrected-schema approval required' unless d==WIRE_BINDING
    plan=wire_analysis_plan
    raise 'existing maintained authorized session required' unless @mock||(@supervised&&@gc_once&&@key)
    ledger=wire_analysis_ledger
    begin;Dir.mkdir(ledger,0700);rescue Errno::EEXIST;raise 'corrected-schema analysis already consumed; no retry';end
    atomic(File.join(ledger,'binding.json'),WIRE_BINDING.merge('purpose'=>'One explicitly authorized corrected-schema validation; no generation',
      'model'=>VisualAnalysis::MODEL,'maxRequests'=>1,'retries'=>0,'generationCalls'=>0,'conservativeMicroUSD'=>plan['conservativeMicroUSD'],'at'=>Time.now.utc.iso8601))
    begin
      response=if @mock
        raise 'simulated transport failure; no retry' if @scenario=='error'
        a=VisualAnalysis.mock_contract(WIRE_BINDING['sourceHash'],plan['width'],plan['height'])
        a.delete('readingOrder') if @scenario=='invalid-schema'
        {'model'=>VisualAnalysis::MODEL,'status'=>'completed','steps'=>[{'type'=>'model_output','content'=>[{'type'=>'text','text'=>JSON.generate(a)}]}],
          'usage'=>{'total_input_tokens'=>0,'total_output_tokens'=>0,'total_thought_tokens'=>0,'total_tokens'=>0}}
      else
        AnalysisTransport.new(@key,record_dir:ledger).call(plan['body'])
      end
      a,usage=VisualAnalysis.response(response,WIRE_BINDING['sourceHash'],plan['width'],plan['height'],allow_mock:@mock)
      # New schema transport still uses the FULL original local validation.
      @analysis.save(a,usage)
      result={'state'=>'analysis-ready','sourceHash'=>WIRE_BINDING['sourceHash'],'requestHash'=>WIRE_BINDING['requestHash'],'analysis'=>a,'usage'=>usage,
        'automaticGeneration'=>false,'generationCalls'=>0,'retries'=>0,'visualAcceptance'=>'requires-human-review'}
      atomic(File.join(ledger,'result.json'),result);result
    rescue => e
      atomic(File.join(ledger,'result.json'),{'state'=>'stopped','error'=>e.message,'generationCalls'=>0,'retries'=>0,'actualCost'=>'unknown','finishedAt'=>Time.now.utc.iso8601})
      raise
    ensure
      @key=nil unless @mock
    end
  end
end
