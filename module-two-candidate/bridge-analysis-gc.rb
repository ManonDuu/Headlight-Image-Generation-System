require_relative 'analysis-gc-transport'
require_relative 'analysis-gc-enum-candidate'
module BridgeAnalysisGC
  def analysis_gc_enum_plan
    original=JSON.parse(File.read(File.join(Bridge::ROOT,'generic-analysis-validation-20261018/analysis-plan.json')))
    AnalysisGCEnumCandidate.prepare(original)
  end
  def execute_analysis_gc_enum(d)
    plan=analysis_gc_enum_plan
    raise 'exact corrected enum authorization required' unless d==plan['binding']&&d['budgetMicroUSD']==20000&&d['conservativeMicroUSD']<=20000
    raise 'maintained authorized session required' unless @supervised&&@gc_once&&@key
    ledger=File.join(Bridge::ROOT,'live-attempts','analysis-gc-'+d['requestHash'])
    begin;Dir.mkdir(ledger,0700);rescue Errno::EEXIST;raise 'corrected enum attempt consumed; no retry';end
    atomic(File.join(ledger,'binding.json'),d)
    begin
      http,raw,meta=AnalysisGCTransport.new(@key,authorized_once:true).call(AnalysisGCAdapter::ENDPOINT,plan['body'],{retries:0,timeoutSeconds:120})
      File.binwrite(File.join(ledger,'response.raw.json'),raw)
      atomic(File.join(ledger,'transport.json'),meta)
      result=AnalysisGCAdapter.parse(http,raw,d)
      @analysis.save(result['analysis'],result['usage'])
    rescue => e
      result={'state'=>'stopped','error'=>e.message,'generationCalls'=>0,'retries'=>0,'actualCost'=>'unknown'}
    ensure
      @key=nil
    end
    atomic(File.join(ledger,'result.json'),result)
    result
  end
  def analysis_gc_plan
    original=JSON.parse(File.read(File.join(Bridge::ROOT,'generic-analysis-validation-20261018/analysis-plan.json')))
    plan=AnalysisGCAdapter.prepare(original)
    raise 'authorized GC request changed' unless plan['binding']['requestHash']=='7438347102048d2e70ebeec577e62cd6f6e3b16b1e6c3da859352e3424898099'
    plan
  end
  def execute_analysis_gc(d)
    plan=analysis_gc_plan
    raise 'exact GC analysis authorization required' unless d==plan['binding']
    raise 'maintained authorized session required' unless @supervised&&@gc_once&&@key
    root=File.join(Bridge::ROOT,'live-attempts')
    transport=AnalysisGCTransport.new(@key,authorized_once:true)
    result=AnalysisGCAdapter.execute(plan,root,approval:d,authorized_once:true,transport:lambda{|endpoint,body,opts|
      http,raw,meta=transport.call(endpoint,body,opts)
      atomic(File.join(root,'analysis-gc-'+d['requestHash'],'transport.json'),meta)
      [http,raw]
    })
    @analysis.save(result['analysis'],result['usage']) if result['state']=='analysis-ready'
    result
  ensure
    @key=nil
  end
end
