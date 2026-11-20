# Independent endpoint experiment. Preparation/parsing are offline; live execution is locked.
require 'json';require 'digest';require 'base64';require 'fileutils';require 'tempfile';require 'open3';require 'time'
module GenerateContentAdapter
  MODEL='gemini-3.1-flash-image'
  ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/#{MODEL}:generateContent"
  OLD_REQUEST='04ef522c895160a78a7f90134fdabbcf0fa13254a771013e10a4d1699938af78'
  SOURCE='d8b87596d3ea2218154b03abafd55333a8f46aa7fcdaca0f53fb63239c2d73ef'
  REQUEST_HASH='837836981ba27897661bc0b4f7246e6a74c9548725c52a5da132a2170156f606'
  LIVE_ENABLED=false
  BUDGET=260000
  def self.check(ok,message);raise ArgumentError,message unless ok;end
  def self.prepare(raw)
    check(Digest::SHA256.hexdigest(raw)==OLD_REQUEST,'frozen original request changed')
    old=JSON.parse(raw);image=old.fetch('input')[1]
    check(Digest::SHA256.hexdigest(Base64.strict_decode64(image.fetch('data')))==SOURCE,'reference changed')
    body={'contents'=>[{'role'=>'user','parts'=>[{'text'=>old['input'][0]['text']},{'inlineData'=>{'mimeType'=>'image/jpeg','data'=>image['data']}}]}],
      'generationConfig'=>{'candidateCount'=>1,'responseModalities'=>['IMAGE'],'maxOutputTokens'=>4096,
      'thinkingConfig'=>{'thinkingLevel'=>'MINIMAL'},'imageConfig'=>{'aspectRatio'=>'4:5','imageSize'=>'2K'}}}
    encoded=JSON.generate(body)
    check(Digest::SHA256.hexdigest(encoded)==REQUEST_HASH,'comparison request drift')
    {'body'=>encoded,'binding'=>{'endpoint'=>ENDPOINT,'model'=>MODEL,'requestHash'=>Digest::SHA256.hexdigest(encoded),
      'sourceHash'=>SOURCE,'originalRequestHash'=>OLD_REQUEST,'promptHash'=>Digest::SHA256.hexdigest(old['input'][0]['text']),
      'budgetMicroUSD'=>BUDGET,'conservativeMicroUSD'=>258560,'inputTokenReserve'=>25600,'outputTokenLimit'=>4096,
      'maxRequests'=>1,'retries'=>0,'analysisCalls'=>0,'liveEnabled'=>false}}
  end
  def self.parse(http,raw,expected_dimensions:[1856,2304],input_token_reserve:25600)
    check([25600,41984].include?(input_token_reserve),'invalid input reserve')
    check(expected_dimensions.is_a?(Array)&&expected_dimensions.size==2&&expected_dimensions.all?{|x|x.is_a?(Integer)&&x>0},'invalid expected dimensions')
    check(http==200,"HTTP #{http}; stop")
    r=JSON.parse(raw);check(!r['error']&&!r.dig('promptFeedback','blockReason'),'provider error or prompt block')
    check(r['modelVersion'].is_a?(String)&&(r['modelVersion']==MODEL||r['modelVersion'].start_with?(MODEL+'-')),'unexpected model version')
    cs=r['candidates'];check(cs.is_a?(Array)&&cs.size==1,'expected one candidate')
    c=cs.first;check(c['finishReason']=='STOP',"generation not complete: #{c['finishReason']}")
    parts=c.dig('content','parts');check(parts.is_a?(Array),'missing content parts')
    check(parts.none?{|p|p.key?('fileData')||p.key?('functionCall')},'external output or tool call rejected')
    images=parts.select{|p|p.key?('inlineData')&&!p['thought']};check(images.size==1,'expected exactly one final inline image')
    img=images.first['inlineData'];mime=img['mimeType'];check(%w[image/jpeg image/png].include?(mime),'unsupported original image format')
    bytes=Base64.strict_decode64(img.fetch('data'));check(bytes.bytesize<=20*1024*1024,'output too large')
    magic=mime=='image/jpeg' ? bytes.start_with?("\xff\xd8\xff".b) : bytes.start_with?("\x89PNG\r\n\x1a\n".b)
    check(magic,'MIME does not match original bytes')
    Tempfile.create(['gc-original',mime=='image/jpeg' ? '.jpg' : '.png']) do |f|
      f.binmode;f.write(bytes);f.flush
      out,st=Open3.capture2(File.expand_path('../deploy/image_probe.py',__dir__),'-g','pixelWidth','-g','pixelHeight','-g','format',f.path,err:File::NULL)
      check(st.success?&&[out[/pixelWidth: (\d+)/,1].to_i,out[/pixelHeight: (\d+)/,1].to_i]==expected_dimensions&&out[/format: (\w+)/,1]==mime.split('/')[1],'invalid original native 2K dimensions or format')
    end
    u=r['usageMetadata'];check(u.is_a?(Hash),'missing usage')
    check(%w[promptTokenCount candidatesTokenCount totalTokenCount].all?{|k|u[k].is_a?(Integer)&&u[k]>=0},'invalid usage')
    # Protobuf omits zero scalar fields. Infer thoughts only when totals prove zero.
    thoughts=u['thoughtsTokenCount']
    thoughts=0 if thoughts.nil?&&u['totalTokenCount']==u['promptTokenCount']+u['candidatesTokenCount']&&u.fetch('toolUsePromptTokenCount',0)==0
    check(thoughts.is_a?(Integer)&&thoughts>=0,'unknown thought usage')
    check(u['promptTokenCount']<=input_token_reserve&&u['candidatesTokenCount']+thoughts<=4096,'usage exceeds reserved budget')
    {'state'=>'generated-pending-review','visualAcceptance'=>'not-evaluated','usage'=>u,'outputMime'=>mime,
      'outputFilename'=>mime=='image/jpeg' ? 'output.jpg' : 'output.png','outputHash'=>Digest::SHA256.hexdigest(bytes),'bytes'=>bytes}
  end
  def self.execute(plan,folder,approval:,transport:,mock:true,authorized_once:false)
    check(mock||authorized_once,'generateContent live experiment locked; explicit one-call startup required')
    check(approval==plan.fetch('binding'),'approval binding mismatch')
    check(Digest::SHA256.hexdigest(plan.fetch('body'))==REQUEST_HASH&&approval['requestHash']==REQUEST_HASH&&approval['endpoint']==ENDPOINT&&approval['budgetMicroUSD']==BUDGET&&approval['conservativeMicroUSD']==258560&&approval['maxRequests']==1&&approval['retries']==0,'altered experiment')
    FileUtils.mkdir_p(folder,mode:0700)
    # One ledger per experiment folder, independent of all existing approvals.
    ledger=mock ? File.join(folder,'attempt') : File.join(__dir__,'live-attempts','generate-content-comparison-20261018-one-call')
    Dir.mkdir(ledger,0700)
    File.write(File.join(ledger,'binding.json'),JSON.pretty_generate(approval))
    File.write(File.join(folder,'binding.json'),JSON.pretty_generate(approval))
    File.write(File.join(folder,'request.json'),plan['body'])
    state={'state'=>'running','mock'=>mock,'analysisCalls'=>0,'submissions'=>1,'visualAcceptance'=>'not-evaluated','startedAt'=>Time.now.utc.iso8601}
    File.write(File.join(folder,'result.json'),JSON.pretty_generate(state))
    begin
      http,raw,diagnostics=transport.call(ENDPOINT,plan['body'],{retries:0,timeoutSeconds:180})
      state['transport']=diagnostics if diagnostics
      File.binwrite(File.join(folder,'response.json'),raw)
      state['httpStatus']=http
      result=parse(http,raw);bytes=result.delete('bytes')
      File.binwrite(File.join(folder,result['outputFilename']),bytes)
      state.merge!(result);state['state']='mock-result' if mock
    rescue => e
      state['state']='stopped';state['error']=e.message
    ensure
      state['finishedAt']=Time.now.utc.iso8601
      File.write(File.join(folder,'result.json'),JSON.pretty_generate(state))
    end
    state
  end
end
