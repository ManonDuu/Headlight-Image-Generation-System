require_relative 'generic-gc-plan'
require_relative 'image-proxy-client'
require_relative 'product-replacement-plan'
require_relative 'generate-content-transport'
require_relative 'authorized-analysis-20261018'
module BridgeGenericGC
  include AuthorizedAnalysis20261018
  def freeze_product(d)
    raise 'product replacement unavailable in repair profile' if @repair_once
    raise 'frontend analysis, prompt or target IDs rejected' if %w[analysis prompt targetRegions].any?{|k|d.key?(k)}
    raise 'product budget must equal 0.27' unless d['budgetMicroUSD']==ProductReplacementPlan::BUDGET_MICRO_USD
    reference,hash,w,h=image_input(d)
    product,product_hash,_,_=image_input({'imageBase64'=>d['productImageBase64'],'sourceHash'=>d['productHash']})
    analysis=reference_analysis(reference,hash,w,h)
    unless analysis
      plan=@analysis.prepare(reference,w,h)
      return public_analysis_plan(plan) unless @mock
      analysis=run_analysis(plan)
    end
    # A reviewed local target binding is separate from client options. Never infer
    # a product from a weather carrier or treat user coordinates as analysis.
    target_path=File.join(@analysis_store,'product-targets',hash+'.json')
    raise 'reviewed product target missing; no request sent' unless File.file?(target_path)
    targets=JSON.parse(File.read(target_path))
    raise 'reviewed target binding mismatch' unless targets.keys.sort==%w[analysisHash sourceHash targetRegions]&&targets['sourceHash']==hash&&targets['analysisHash']==Digest::SHA256.hexdigest(JSON.generate(analysis))
    options=d.select{|k,_|%w[businessSpec mode output layoutTone layoutMode layoutInstructions customCopy color sceneMode productName brandName productParameters].include?(k)}
    options['targetRegions']=targets.fetch('targetRegions')
    plan=ProductReplacementPlan.prepare(reference,product,analysis,options,allow_mock:@mock)
    id=SecureRandom.hex(12);p=File.join(@data,id);Dir.mkdir(p,0700)
    File.binwrite(File.join(p,'reference.jpg'),reference);File.binwrite(File.join(p,'product.jpg'),product)
    atomic(File.join(p,'generic-gc-plan.json'),plan);atomic(File.join(p,'rule-trace.json'),plan['trace'])
    binding=plan['binding'];prompt=JSON.parse(plan['body'])['contents'][0]['parts'][0]['text']
    s={'id'=>id,'module'=>'product-replacement','state'=>'frozen','requestHash'=>binding['requestHash'],'genericGC'=>binding,
      'rulesHash'=>Digest::SHA256.file(File.join(p,'rule-trace.json')).hexdigest,'ruleTrace'=>plan['trace'],'sourceHash'=>hash,
      'productHash'=>product_hash,'mode'=>d['mode'],'prompt'=>prompt,'budgetMicroUSD'=>binding['budgetMicroUSD'],'mock'=>@mock,
      'visualAcceptance'=>'not-evaluated','createdAt'=>Time.now.utc.iso8601}
    s['preflight']=plan['trace']['preflight'] if d.key?('businessSpec')
    atomic(File.join(p,'state.json'),s);s
  end
  def analyze_generic(d)
    raise 'frontend analysis/prompt rejected' if d.key?('analysis')||d.key?('prompt')
    bytes,hash,w,h=image_input(d)
    store=AnalysisStore.new(File.join(@data,'generic-analysis-v1'),mock:@mock)
    plan=store.prepare(bytes,w,h)
    return {'state'=>'analysis-cached','analysis'=>plan['analysis']} if plan['state']=='analysis-cached'
    binding={'requestHash'=>plan['requestHash'],'budgetMicroUSD'=>20000,'sourceHash'=>hash}
    exact_authorized=authorized_analysis_binding==binding
    return public_analysis_plan(plan).merge('liveAnalysisEnabled'=>@mock||@generic_analysis_approval==binding||exact_authorized) unless d['approval']
    raise 'exact analysis approval required' unless d['approval']==binding
    raise 'fresh server-side analysis approval required' unless @mock||((@generic_analysis_approval==binding||exact_authorized)&&@key)
    ledger=reserve_authorized_analysis(binding) if exact_authorized
    transport=if @mock
      lambda do |_|
        raise 'simulated analysis timeout' if @scenario=='timeout'
        {'model'=>VisualAnalysis::MODEL,'status'=>'completed','steps'=>[{'type'=>'model_output','content'=>[{'type'=>'text','text'=>JSON.generate(VisualAnalysis.mock_contract(hash,w,h))}]}],'usage'=>{'total_input_tokens'=>0,'total_output_tokens'=>0,'total_thought_tokens'=>0,'total_tokens'=>0}}
      end
    else
      AnalysisTransport.new(@key,record_dir:ledger)
    end
    begin
      a=store.execute(plan,transport:transport,approval:binding.reject{|k,_|k=='sourceHash'})
      atomic(File.join(ledger,'result.json'),{'state'=>'completed','at'=>Time.now.utc.iso8601}) if ledger
    rescue => e
      atomic(File.join(ledger,'result.json'),{'state'=>'stopped','error'=>e.message,'at'=>Time.now.utc.iso8601}) if ledger
      raise
    end
    @analysis.save(a)
    {'state'=>'analysis-ready','analysis'=>a,'visualAcceptance'=>'requires-human-review','automaticGeneration'=>false}
  end
  def generic_ledger(binding)
    File.join(@mock ? @data : File.join(Bridge::ROOT,'live-attempts'),'generic-gc-'+binding.fetch('requestHash'))
  end
  def generic_status
    {'implemented'=>true,'businessSpec'=>DirectImagePlan::SPEC,'supportedInputMimeTypes'=>['image/jpeg','image/png'],'workflow'=>'direct-generation','preAnalysisEnabled'=>false,'generationModel'=>(@image_proxy ? @image_proxy['model'] : GenerateContentAdapter::MODEL),'automaticFallback'=>false,'enabled'=>@mock||!@generic_approval.nil?||(@reference_daily&&!(@key.nil?&&@image_proxy.nil?)),'approval'=>@generic_approval,'referenceDaily'=>@reference_daily==true,
      'productReplacement'=>{'implemented'=>true,'version'=>ProductIdentityPolicy::VERSION,'businessSpec'=>DirectImagePlan::PRODUCT_SPEC,'dailyEnabled'=>@product_daily==true,'liveEnabled'=>!@mock&&((@reference_daily&&@product_daily&&(@key||@image_proxy))||(@generic_approval&&@generic_approval['module']=='product-replacement')) ? true : false,'requiresReviewedTarget'=>false,'targetIdentification'=>'image-model-unverified','budgetMicroUSD'=>ProductReplacementPlan::BUDGET_MICRO_USD},
      'remaining'=>@generic_approval ? (File.exist?(generic_ledger(@generic_approval)) ? 0 : 1) : ((@mock||@reference_daily) ? 1 : 0)}
  end
  def generate_generic(d)
    raise 'exact task and GC request hash required' unless d.keys.sort==%w[id requestHash]
    @mutex.synchronize do
      p=job(d['id']);s=snapshot(d['id'])
      raise 'task already attempted' unless s['state']=='frozen'
      plan=JSON.parse(File.read(File.join(p,'generic-gc-plan.json')))
      product=plan.dig('binding','module')=='product-replacement'
      plan.dig('binding','directGeneration') ? DirectImagePlan.validate(plan) : (product ? ProductReplacementPlan : GenericGCPlan).validate(plan)
      binding=plan.fetch('binding')
      raise 'frozen GC request mismatch' unless d['requestHash']==binding['requestHash']&&s.dig('genericGC','requestHash')==binding['requestHash']
      parts=JSON.parse(plan['body'])['contents'][0]['parts']
      ref_blob=binding['directGeneration'] ? DirectImagePlan.image_part(plan,'reference') : parts[1]['inlineData']
      product_blob=product ? (binding['directGeneration'] ? DirectImagePlan.image_part(plan,'product-appearance') : parts[2]['inlineData']) : nil
      reference_name=InputImage.filename('reference',ref_blob['mimeType'])
      raise 'frozen evidence changed' unless Digest::SHA256.file(File.join(p,reference_name)).hexdigest==binding['sourceHash']&&Digest::SHA256.file(File.join(p,'rule-trace.json')).hexdigest==s['rulesHash']
      raise 'frozen product changed' if product&&Digest::SHA256.file(File.join(p,InputImage.filename('product',product_blob['mimeType']))).hexdigest!=binding['productHash']
      daily_request=@reference_daily && binding['directGeneration'] && (product ? @product_daily&&binding['version']==DirectImagePlan::PRODUCT_SPEC : binding['version']==DirectImagePlan::SPEC) && !binding['mock'] && (@key || @image_proxy)
      if @reference_daily
        raise 'daily profile accepts current enabled modules only' unless binding['directGeneration'] && (product ? @product_daily&&binding['version']==DirectImagePlan::PRODUCT_SPEC : binding['version']==DirectImagePlan::SPEC)
        raise 'another task is running; wait for its result' if Dir.glob(File.join(@data,'*','state.json')).any?{|f|JSON.parse(File.read(f))['state']=='running'}
      end
      raise 'fresh server-side GC approval required; no request sent' unless @mock||daily_request||(@generic_approval==binding&&!binding['mock']&&@key)
      raise 'budget reservation exceeds allowance' unless binding['conservativeMicroUSD']<=binding['budgetMicroUSD']&&binding['budgetMicroUSD']==(product ? ProductReplacementPlan::BUDGET_MICRO_USD : 260000)
      # Atomic global hash reservation survives task recreation, failures and restart.
      ledger=generic_ledger(binding);ledger+='-task-'+s.fetch('id') if product&&binding['version']==DirectImagePlan::PRODUCT_SPEC
      Dir.mkdir(ledger,0700)
      atomic(File.join(ledger,'binding.json'),binding)
      s.merge!('state'=>'running','startedAt'=>Time.now.utc.iso8601,'execution'=>'generic-generateContent','generationRequestHash'=>binding['requestHash'])
      atomic(File.join(p,'state.json'),s)
      File.binwrite(File.join(p,'generic-request.json'),plan['body'])
      Thread.new do
        begin
          if !@mock && @image_proxy
            result=ImageProxyClient.generate(plan['body'],@image_proxy,product ? 'replacement' : 'reference')
            s['transport']=result.delete('diagnostic') if result['diagnostic']
            s['httpStatus']=s.dig('transport','httpStatus')
            bytes=result.delete('bytes');File.binwrite(File.join(p,result.fetch('outputFilename')),bytes)
            s.merge!(result)
          else
          transport=@mock ? method(:generic_mock_transport).to_proc.curry[p] : GenerateContentTransport.new(@key,authorized_once:true,meter_module:product ? 'replacement' : 'reference')
          http,raw,diagnostics=transport.call(GenerateContentAdapter::ENDPOINT,plan['body'],{retries:0,timeoutSeconds:180})
          File.binwrite(File.join(p,'generic-response.json'),raw)
          s['httpStatus']=http;s['transport']=diagnostics if diagnostics
          result=GenerateContentAdapter.parse(http,raw,expected_dimensions:binding['expectedDimensions'],input_token_reserve:binding['inputTokenReserve'])
          bytes=result.delete('bytes');File.binwrite(File.join(p,result['outputFilename']),bytes)
          s.merge!(result);s['state']='mock-result' if @mock
          end
        rescue => e
          s.merge!('state'=>'stopped','error'=>e.message)
          %w[output.jpg output.png].each{|name|FileUtils.rm_f(File.join(p,name))} if @mock
        ensure
          s['finishedAt']=Time.now.utc.iso8601;atomic(File.join(p,'state.json'),s)
          @key=nil unless @mock || @reference_daily
        end
      end
      s.dup
    end
  rescue Errno::EEXIST
    raise 'generic GC request already consumed; no repeat or retry'
  end
  def generic_mock_transport(p,endpoint,body,options)
    raise 'simulated timeout' if @scenario=='timeout'
    return [400,'{"error":{"code":400}}'] if @scenario=='error'
    return [200,''] if @scenario=='empty'
    mock_response(p)
    bytes=File.binread(File.join(p,'output.jpg'))
    FileUtils.rm_f(File.join(p,'output.jpg'))
    image={'inlineData'=>{'mimeType'=>'image/jpeg','data'=>Base64.strict_encode64(bytes)}}
    parts=@scenario=='multiple' ? [image,image] : [image]
    reserve=JSON.parse(File.read(File.join(p,'generic-gc-plan.json'))).fetch('binding').fetch('inputTokenReserve')
    [200,JSON.generate({'modelVersion'=>GenerateContentAdapter::MODEL,'candidates'=>[{'finishReason'=>'STOP','content'=>{'parts'=>parts}}],
      'usageMetadata'=>{'promptTokenCount'=>@scenario=='over-budget' ? reserve+1 : 0,'candidatesTokenCount'=>0,'thoughtsTokenCount'=>0,'totalTokenCount'=>@scenario=='over-budget' ? reserve+1 : 0}})]
  end
end
