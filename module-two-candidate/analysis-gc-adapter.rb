# Offline endpoint-specific request/response adapter; never acquires credentials.
require_relative 'analysis-wire-candidate'
require 'time'
module AnalysisGCAdapter
  VERSION='analysis-generateContent-20261018.1'
  MODEL=VisualAnalysis::MODEL
  ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/#{MODEL}:generateContent"
  SOURCE='d8b87596d3ea2218154b03abafd55333a8f46aa7fcdaca0f53fb63239c2d73ef'
  PURPOSE='Analyze the frozen reference into the full visual evidence contract; never generate images.'
  def self.need(ok,msg);VisualAnalysis.need(ok,msg);end
  def self.prepare(original)
    need(original.keys.sort==%w[state binding width height requestHash request analysisBudgetMicroUSD combinedBudgetMicroUSD].sort,'original plan fields changed')
    need(original['binding']==VisualAnalysis.binding(SOURCE)&&original['analysisBudgetMicroUSD']==20000&&original['combinedBudgetMicroUSD']==280000&&original['state']=='analysis-awaiting-approval','original plan binding changed')
    request=original.fetch('request');image=request.fetch('input')[1]
    bytes=Base64.strict_decode64(image.fetch('data'));w=original.fetch('width');h=original.fetch('height')
    need(w==1200&&h==1500&&original['requestHash']=='e40147c2533608e8170a56f98331e0a86253c9a601a336f53d93ed230f30bb4a','frozen original contract changed')
    need(Digest::SHA256.hexdigest(bytes)==SOURCE,'only frozen authorized source may be planned')
    need(request==VisualAnalysis.request(bytes,w,h)&&Digest::SHA256.hexdigest(JSON.generate(request))==original['requestHash'],'original request changed')
    wire=AnalysisWireCandidate.project(VisualAnalysis::SCHEMA)
    body={'contents'=>[{'role'=>'user','parts'=>[{'text'=>request['input'][0]['text']},{'inlineData'=>{'mimeType'=>'image/jpeg','data'=>image['data']}}]}],
      'generationConfig'=>{'candidateCount'=>1,'maxOutputTokens'=>4096,'thinkingConfig'=>{'thinkingLevel'=>'MINIMAL'},
        'mediaResolution'=>'MEDIA_RESOLUTION_HIGH','responseFormat'=>{'text'=>{'mimeType'=>'application/json','schema'=>wire}}}}
    raw=JSON.generate(body)
    binding={'version'=>VERSION,'model'=>MODEL,'endpoint'=>ENDPOINT,'sourceHash'=>SOURCE,'requestHash'=>Digest::SHA256.hexdigest(raw),
      'purpose'=>PURPOSE,'width'=>w,'height'=>h,'budgetMicroUSD'=>20000,'conservativeMicroUSD'=>15156,
      'inputTokenReserve'=>16384,'maxOutputTokens'=>4096,'maxRequests'=>1,'retries'=>0,'generationCalls'=>0,
      'localSchemaHash'=>Digest::SHA256.hexdigest(JSON.generate(VisualAnalysis::SCHEMA)),'wireSchemaHash'=>Digest::SHA256.hexdigest(JSON.generate(wire))}
    {'body'=>raw,'binding'=>binding,'original'=>original,'liveEnabled'=>false}
  end
  def self.validate(plan)
    need(prepare(plan.fetch('original'))==plan,'GC analysis frozen plan changed')
    need(plan['binding']['conservativeMicroUSD']<=plan['binding']['budgetMicroUSD'],'budget exceeded')
    true
  end
  def self.parse(http,raw,binding,allow_mock:false)
    need(http==200,"analysis HTTP #{http}; no retry")
    need(raw.is_a?(String)&&raw.bytesize<=1048576,'invalid response size')
    r=VisualAnalysis.parse_json(raw)
    need(!r['error']&&!r.dig('promptFeedback','blockReason'),'provider error/block')
    need(r['modelVersion'].is_a?(String)&&(r['modelVersion']==MODEL||r['modelVersion'].start_with?(MODEL+'-')),'unexpected analysis model')
    cs=r['candidates'];need(cs.is_a?(Array)&&cs.size==1&&cs[0]['finishReason']=='STOP','analysis incomplete or multiple candidates')
    parts=cs[0].dig('content','parts');need(parts.is_a?(Array),'missing analysis parts')
    need(parts.all?{|p|p.is_a?(Hash)&&p.key?('text')&&(p.keys-%w[text thought thoughtSignature]).empty?},'non-text analysis output rejected')
    final=parts.reject{|p|p['thought']};need(final.size==1&&final[0]['text'].is_a?(String),'exactly one final JSON text required')
    u=r['usageMetadata'];need(u.is_a?(Hash),'usage required')
    %w[promptTokenCount candidatesTokenCount totalTokenCount].each{|k|need(u[k].is_a?(Integer)&&u[k]>=0,'invalid usage '+k)}
    thoughts=u['thoughtsTokenCount']
    thoughts=0 if thoughts.nil?&&u['totalTokenCount']==u['promptTokenCount']+u['candidatesTokenCount']&&u.fetch('toolUsePromptTokenCount',0)==0
    need(thoughts.is_a?(Integer)&&thoughts>=0&&u.fetch('toolUsePromptTokenCount',0)==0,'unknown thought/tool usage')
    need(u['totalTokenCount']==u['promptTokenCount']+u['candidatesTokenCount']+thoughts,'inconsistent usage totals')
    need(u['promptTokenCount']<=16384&&u['candidatesTokenCount']+thoughts<=4096,'analysis budget reserve exceeded')
    a=VisualAnalysis.parse_json(final[0]['text']);need(a['origin']==(allow_mock ? 'mock' : 'model'),'analysis provenance mismatch')
    VisualAnalysis.validate(a,binding['sourceHash'],binding['width'],binding['height'],allow_mock:allow_mock)
    {'state'=>'analysis-ready','analysis'=>a,'usage'=>u,'generationCalls'=>0,'automaticGeneration'=>false,'visualAcceptance'=>'requires-human-review'}
  rescue JSON::ParserError
    raise VisualAnalysis::Invalid,'malformed analysis JSON'
  end
  def self.execute(plan,root,approval:,transport:,mock:false,authorized_once:false)
    validate(plan);need(mock||authorized_once,'GC analysis requires a fresh exact one-call authorization')
    need(approval==plan['binding'],'GC analysis approval mismatch')
    FileUtils.mkdir_p(root,mode:0700)
    ledger=File.join(root,'analysis-gc-'+approval.fetch('requestHash'))
    begin;Dir.mkdir(ledger,0700);rescue Errno::EEXIST;raise VisualAnalysis::Invalid,'GC analysis already consumed; no retry';end
    File.write(File.join(ledger,'binding.json'),JSON.pretty_generate(approval))
    begin
      http,raw=transport.call(ENDPOINT,plan['body'],{retries:0,timeoutSeconds:120})
      File.binwrite(File.join(ledger,'response.raw.json'),raw)
      result=parse(http,raw,approval,allow_mock:mock)
    rescue => e
      result={'state'=>'stopped','error'=>e.message,'generationCalls'=>0,'retries'=>0,'actualCost'=>'unknown'}
    end
    File.write(File.join(ledger,'result.json'),JSON.pretty_generate(result));result
  end
end
