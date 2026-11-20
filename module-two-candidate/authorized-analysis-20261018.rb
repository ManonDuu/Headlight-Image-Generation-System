# Explicitly authorized 2026-10-18: one analysis of the already Google-authorized
# reference, zero generation, USD .02, zero retries. No credential in this file.
module AuthorizedAnalysis20261018
  BINDING={'requestHash'=>'e40147c2533608e8170a56f98331e0a86253c9a601a336f53d93ed230f30bb4a',
    'sourceHash'=>'d8b87596d3ea2218154b03abafd55333a8f46aa7fcdaca0f53fb63239c2d73ef','budgetMicroUSD'=>20000}.freeze
  PURPOSE='Validate real structured visual analysis and frozen-rule binding, bypassing manual seed; no image generation.'
  def authorized_analysis_binding
    return nil unless @supervised&&@gc_once&&!@mock
    BINDING
  end
  def reserve_authorized_analysis(binding)
    raise 'specific analysis binding changed' unless binding==BINDING
    ledger=File.join(Bridge::ROOT,'live-attempts','generic-analysis-20261018-one-call')
    begin;Dir.mkdir(ledger,0700);rescue Errno::EEXIST;raise 'authorized analysis already consumed; no retry';end
    atomic(File.join(ledger,'binding.json'),binding.merge('purpose'=>PURPOSE,'maxRequests'=>1,'generationCalls'=>0,'retries'=>0,'model'=>VisualAnalysis::MODEL,'at'=>Time.now.utc.iso8601))
    ledger
  end
end
