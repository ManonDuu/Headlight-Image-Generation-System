require 'webrick'
require 'json'
require 'base64'
require 'digest'
require 'securerandom'
require 'fileutils'
require 'open3'
require 'zlib'
require 'time'
require_relative 'rules-compiler'
require_relative 'visual-analysis'
require_relative 'generic-gc-plan'
require_relative 'analysis-transport'
require_relative 'product-asset-provider'
require_relative 'cumulative-scene-runner'
require 'tempfile'
class Bridge
  ROOT=File.expand_path(__dir__)
  LIMIT=260000
  GENERATION_LIVE_ENABLED=false # Locked after real incomplete response; no live profile bypass.
  ANALYSIS_LIVE_ENABLED=false # New analysis spend awaits parent confirmation; old approval is not reusable.
  JPEG_REPAIR={
    'id'=>'module-one-jpeg-repair-20261017-one-call',
    'requestHash'=>'207e9acea189cdf4ae6f134c422b358882f131dc956975ff92ab589354ecbb93',
    'sourceHash'=>'d8b87596d3ea2218154b03abafd55333a8f46aa7fcdaca0f53fb63239c2d73ef',
    'rulesVersion'=>'recovered-approved-core-20261017.4',
    'budgetMicroUSD'=>260000,'maxRequests'=>1,'retries'=>0,'analysisAllowed'=>false
  }.freeze
  AUDITED_REPAIR={
    'id'=>'module-one-audited-repair-20261017-one-call',
    'requestHash'=>'04ef522c895160a78a7f90134fdabbcf0fa13254a771013e10a4d1699938af78',
    'sourceHash'=>'d8b87596d3ea2218154b03abafd55333a8f46aa7fcdaca0f53fb63239c2d73ef',
    'rulesVersion'=>'recovered-approved-core-20261017.5',
    'budgetMicroUSD'=>260000,'conservativeMicroUSD'=>258560,
    'inputTokenReserve'=>25600,'imageTokenReserve'=>16384,
    'maxRequests'=>1,'retries'=>0,'analysisAllowed'=>false,'stopAfterFailure'=>true
  }.freeze
  def initialize(mock:, data:, scenario: 'success', key: nil, analysis_store: File.join(ROOT,'analysis-cache'), repair_once: false, audited_once: false, supervised: false, gc_once: false, generic_approval:nil, generic_analysis_approval:nil, internal_reference:false, reference_daily:false, product_daily:false, image_proxy:nil)
    raise 'daily reference profile cannot reuse experiment approvals' if reference_daily && (repair_once || audited_once || gc_once || generic_approval || generic_analysis_approval)
    raise 'product daily profile requires daily workbench' if product_daily&&!reference_daily
    @product_daily=product_daily
    @reference_daily=reference_daily
    raise 'analysis approval requires isolated supervised profile' if generic_analysis_approval&&(!supervised||generic_approval||gc_once||repair_once||audited_once)
    @internal_reference=internal_reference
    @generic_analysis_approval=generic_analysis_approval
    raise 'generic approval requires isolated supervised profile' if generic_approval&&(!supervised||gc_once||repair_once||audited_once)
    @generic_approval=generic_approval
    raise 'GC comparison requires its own supervisor startup profile' if gc_once&&((repair_once||audited_once)||(!mock&&!supervised))
    @gc_once=gc_once
    @supervised=supervised; @maintenance=false; @operations=Mutex.new
    @mock,@data,@scenario,@key,@image_proxy=mock,data,scenario,key,image_proxy
    raise 'choose only one repair profile' if repair_once&&audited_once
    @audited_once=audited_once
    @repair_once=repair_once||audited_once
    @approval=audited_once ? AUDITED_REPAIR : JPEG_REPAIR
    raise 'repair requires exact approved rules version and disabled analysis' if @repair_once&&(RulesCompiler::VERSION!=@approval['rulesVersion']||ANALYSIS_LIVE_ENABLED)
    raise 'audited input reserve or budget changed' if audited_once&&(RulesCompiler::INPUT_TOKEN_ALLOWANCE!=AUDITED_REPAIR['inputTokenReserve']||RulesCompiler::INPUT_TOKEN_ALLOWANCE*500+4096*60000>LIMIT*1000)
    @analysis_store=analysis_store
    @analysis=AnalysisStore.new(File.join(data,'analysis-cache-v1'),mock:mock)
    @token=SecureRandom.hex(32); @mutex=Mutex.new
    FileUtils.mkdir_p(@data,mode:0700)
    internal_recover
    @ledger= mock ? File.join(@data,'one-use-approval') : File.join(ROOT,'live-attempts','module-one-single-20261017')
    @ledger=File.join(mock ? @data : File.join(ROOT,'live-attempts'),@approval['id']) if @repair_once
    FileUtils.mkdir_p(File.dirname(@ledger),mode:0700)
    Dir.glob(File.join(@data,'*','state.json')).each do |p|
      s=JSON.parse(File.read(p)); if s['state']=='running'; s['state']='stopped';s['error']='Interrupted; remote outcome unknown; no retry';atomic(p,s);end
    end
  end
  attr_reader :token
  def maintenance_preflight
    Dir[File.join(ROOT,'*.rb')].each do |path|
      _,st=Open3.capture2('/usr/bin/ruby','-c',path,err:File::NULL)
      raise "update rejected: Ruby syntax error in #{File.basename(path)}; current service retained" unless st.success?
    end
    Dir[File.join(ROOT,'*.zsh')].each do |path|
      _,st=Open3.capture2('/bin/zsh','-n',path,err:File::NULL)
      raise "update rejected: shell syntax error in #{File.basename(path)}; current service retained" unless st.success?
    end
    raw,st=Open3.capture2({'GEMINI_API_KEY'=>nil},'/usr/bin/ruby',File.join(ROOT,'bridge-server.rb'),'--maintenance-inspect',err:File::NULL)
    raise 'update inspection failed; current service retained' unless st.success?
    next_boot=JSON.parse(raw)
    raise 'update changes rules/authorization; current service retained' unless next_boot['rulesVersion']==RulesCompiler::VERSION&&next_boot['budget']==LIMIT&&next_boot['generationEnabled']==GENERATION_LIVE_ENABLED&&next_boot['analysisEnabled']==ANALYSIS_LIVE_ENABLED&&(!@repair_once||next_boot['auditedApproval']==@approval)&&(!@gc_once||next_boot['gcApproval']==GC_COMPARISON_APPROVAL)
    {'syntax'=>'passed','authorization'=>'unchanged','automaticModelCalls'=>0}
  end
  def atomic(path,value)
    tmp=path+'.tmp'; File.write(tmp,JSON.pretty_generate(value)); File.rename(tmp,path)
  end
  def job(id)
    raise 'invalid task' unless id.to_s.match?(/\A[0-9a-f]{24}\z/)
    p=File.join(@data,id); raise 'missing task' unless File.directory?(p);p
  end
  def snapshot(id)
    p=job(id);s=JSON.parse(File.read(File.join(p,'state.json')))
    feedback=File.join(p,'user-feedback.json')
    s['userFeedback']=JSON.parse(File.read(feedback)) if File.file?(feedback)
    findings=File.join(p,'manual-findings.json')
    s['manualFindings']=JSON.parse(File.read(findings)) if File.file?(findings)
    s['inputRecovery']=HistoryInputRecovery.inspect(p,s)
    s
  end
  def image_input(d)
    encoded=d['imageBase64'];raise 'invalid image size' unless encoded.is_a?(String)&&encoded.bytesize<=5600000
    bytes=Base64.strict_decode64(encoded);raise 'JPEG required' unless bytes.bytesize<=4*1024*1024&&bytes.start_with?("\xFF\xD8\xFF".b)
    hash=Digest::SHA256.hexdigest(bytes);raise 'source digest mismatch' unless hash==d['sourceHash']
    Tempfile.create(['reference','.jpg']) do |f|
      f.binmode;f.write(bytes);f.flush
      size,st=Open3.capture2(File.expand_path('../deploy/image_probe.py',__dir__),'-g','pixelWidth','-g','pixelHeight',f.path,err:File::NULL)
      w=size[/pixelWidth: (\d+)/,1].to_i;h=size[/pixelHeight: (\d+)/,1].to_i
      raise 'invalid JPEG dimensions' unless st.success?&&w.between?(1,20000)&&h.between?(1,20000)
      return [bytes,hash,w,h]
    end
  end
  def reference_analysis(bytes,hash,w,h)
    cached=@analysis.fetch(hash,w,h);return cached if cached
    seed=File.join(@analysis_store,hash+'.json')
    return nil unless File.file?(seed)
    a=VisualAnalysis.parse_json(File.read(seed))
    VisualAnalysis.validate(a,hash,w,h,allow_mock:@mock)
    @analysis.save(a)
  end
  def public_analysis_plan(plan)
    generic_binding={'requestHash'=>plan['requestHash'],'budgetMicroUSD'=>20000,'sourceHash'=>plan.dig('binding','sourceHash')}
    plan.reject{|k,_|k=='request'}.merge('liveAnalysisEnabled'=>ANALYSIS_LIVE_ENABLED||@generic_analysis_approval==generic_binding,'message'=>'新参考图需要一次视觉分析。计划已准备，尚未发送；不要求填写坐标。')
  end
  def run_analysis(plan,approval=nil)
    if @mock
      transport=lambda do |_request|
        a=VisualAnalysis.mock_contract(plan['binding']['sourceHash'],plan['width'],plan['height'])
        {'model'=>VisualAnalysis::MODEL,'status'=>'completed','steps'=>[{'type'=>'model_output','content'=>[{'type'=>'text','text'=>JSON.generate(a)}]}],'usage'=>{'total_input_tokens'=>0,'total_output_tokens'=>0,'total_thought_tokens'=>0,'total_tokens'=>0}}
      end
      approval={'requestHash'=>plan['requestHash'],'budgetMicroUSD'=>VisualAnalysis::BUDGET}
    else
      raise 'new analysis paid execution disabled pending fresh approval; no request sent' unless ANALYSIS_LIVE_ENABLED
      transport=AnalysisTransport.new(@key)
    end
    @analysis.execute(plan,transport:transport,approval:approval)
  end
  def analyze_task(d)
    raise 'analysis not allowed for JPEG repair' if @repair_once
    raise 'client prompt/analysis rejected' if d.key?('prompt')||d.key?('analysis')
    raise 'unsupported module' unless d['module']=='reference-reconstruction'
    bytes,hash,w,h=image_input(d)
    a=reference_analysis(bytes,hash,w,h)
    return {'state'=>'analysis-cached','sourceHash'=>hash} if a
    plan=@analysis.prepare(bytes,w,h)
    return public_analysis_plan(plan) unless d['approval']
    run_analysis(plan,d['approval'])
    {'state'=>'analysis-ready','sourceHash'=>hash}
  end
  def freeze_task(d)
    return freeze_direct(d) if [DirectImagePlan::SPEC,DirectImagePlan::PRODUCT_SPEC].include?(d['businessSpec'])
    raise '出图模型由后台固定，不能指定模型、端点或fallback' if %w[model endpoint fallbackModel].any?{|k|d.key?(k)}
    return freeze_product(d) if d['module']=='product-replacement'
    raise '参考图重构固定重构场景，不接受产品替换场景或素材字段' if %w[sceneMode sceneChange productImageBase64 productHash targetRegions].any?{|k|d.key?(k)}
    if @repair_once
      raise 'repair is bound to known reference and no-copy 4:5/2K options' unless d['sourceHash']==@approval['sourceHash']&&d['mode']=='no-copy'&&d['layoutTone']=='keep-reference'&&d['output']=={'aspectRatio'=>'4:5','imageSize'=>'2K'}
    end
    raise 'budget must equal 0.26' unless d['budgetMicroUSD']==LIMIT
    raise 'frontend prompt/analysis rejected; analysis belongs to backend' if d.key?('prompt')||d.key?('analysis')
    raise 'product replacement backend not completed; no request sent' unless d['module']=='reference-reconstruction'
    bytes,hash,width,height=image_input(d)
    encoded=d['imageBase64']
    analysis=reference_analysis(bytes,hash,width,height)
    raise 'repair requires existing local analysis; no analysis call allowed' if @repair_once&&!analysis
    unless analysis
      plan=@analysis.prepare(bytes,width,height)
      return public_analysis_plan(plan) unless @mock
      analysis=run_analysis(plan)
    end
    compiled=d.key?('businessSpec') ? BusinessRules.compile(d,analysis,hash) : RulesCompiler.compile(d.merge('analysis'=>analysis,'sceneChange'=>analysis['sceneChange']),hash)
    prompt=compiled['prompt']
    id=SecureRandom.hex(12);p=File.join(@data,id);Dir.mkdir(p,0700)
    File.binwrite(File.join(p,'reference.jpg'),bytes)
    size,st=Open3.capture2(File.expand_path('../deploy/image_probe.py',__dir__),'-g','pixelWidth','-g','pixelHeight',File.join(p,'reference.jpg'),err:File::NULL)
    raise 'invalid JPEG dimensions' unless st.success?&&size.match?(/pixelWidth: [1-9][0-9]*/)&&size.match?(/pixelHeight: [1-9][0-9]*/)
    raise 'analysis dimensions do not match image' unless size[/pixelWidth: (\d+)/,1].to_i==analysis['width']&&size[/pixelHeight: (\d+)/,1].to_i==analysis['height']
    atomic(File.join(p,'input.json'),{prompt:prompt,imageBase64:encoded,mode:d['mode'],sourceHash:hash,output:compiled['output']})
    atomic(File.join(p,'rule-trace.json'),compiled['trace'])
    # Prepare the general GC candidate locally; existing approved request and
    # execution routes remain independent and locked to their original bindings.
    gc_options=d.select{|k,_|%w[businessSpec mode output layoutTone layoutMode layoutInstructions customCopy brandName productParameters color].include?(k)}
    gc_plan=GenericGCPlan.prepare(bytes,analysis,gc_options,allow_mock:@mock)
    atomic(File.join(p,'generic-gc-plan.json'),gc_plan)
    _,st=Open3.capture2('/usr/bin/osascript','-l','JavaScript',File.join(ROOT,'local-io.js'),'bridge-prepare',ROOT,p,err:File::NULL)
    raise 'adapter preparation failed' unless st.success?
    reqhash=Digest::SHA256.file(File.join(p,'request.json')).hexdigest
    raise 'repair request differs from approved JPEG request' if @repair_once&&reqhash!=@approval['requestHash']
    s={'id'=>id,'state'=>'frozen','requestHash'=>reqhash,'inputHash'=>Digest::SHA256.file(File.join(p,'input.json')).hexdigest,'rulesHash'=>Digest::SHA256.file(File.join(p,'rule-trace.json')).hexdigest,'ruleTrace'=>compiled['trace'],'sourceHash'=>hash,'mode'=>d['mode'],'prompt'=>prompt,'budgetMicroUSD'=>LIMIT,'mock'=>@mock,'visualAcceptance'=>'not-evaluated','createdAt'=>Time.now.utc.iso8601}
    s['genericGC']=gc_plan['binding']
    s['module']='reference-reconstruction'
    s['preflight']=gc_plan['trace']['preflight'] if d.key?('businessSpec')
    atomic(File.join(p,'state.json'),s);s
  end
  def generate(id,hash)
    raise 'live generation locked: provider returned incomplete; external diagnostic evidence required' unless @mock||(GENERATION_LIVE_ENABLED&&@audited_once)
    @mutex.synchronize do
      p=job(id);s=snapshot(id)
      raise 'repair request not approved' if @repair_once&&(hash!=@approval['requestHash']||s['sourceHash']!=@approval['sourceHash']||s['budgetMicroUSD']!=@approval['budgetMicroUSD'])
      raise 'task already attempted' unless s['state']=='frozen'
      raise 'frozen request mismatch' unless hash==s['requestHash']&&Digest::SHA256.file(File.join(p,'request.json')).hexdigest==hash&&Digest::SHA256.file(File.join(p,'input.json')).hexdigest==s['inputHash']
      raise 'frozen rule mapping changed' unless Digest::SHA256.file(File.join(p,'rule-trace.json')).hexdigest==s['rulesHash']
      raise 'missing in-memory credential' unless @mock||@key
      # Persistently consume the NEW single-use allowance; never touch the old ledger.
      Dir.mkdir(@ledger,0700);atomic(File.join(@ledger,'binding.json'),{approvalId:@repair_once ? @approval['id'] : 'module-one-single-20261017',task:id,requestHash:hash,budgetMicroUSD:LIMIT,at:Time.now.utc.iso8601,mock:@mock})
      Dir.mkdir(File.join(p,'attempt'),0700)
      s['state']='running';s['startedAt']=Time.now.utc.iso8601;atomic(File.join(p,'state.json'),s)
      Thread.new{perform(id)}
      s
    end
  rescue Errno::EEXIST
    raise 'single-use allowance consumed; no repeat or retry'
  end
  def mock_response(p)
    if @scenario=='recorded-incomplete'
      FileUtils.cp(File.join(ROOT,'fixtures/recorded-incomplete-20261017.json'),File.join(p,'response.json'))
      File.write(File.join(p,'http-status.txt'),'200');File.write(File.join(p,'transport-exit-code.txt'),'0')
      _,st=Open3.capture2('/usr/bin/osascript','-l','JavaScript',File.join(ROOT,'local-io.js'),'parse',ROOT,p,'200',err:File::NULL)
      raise 'recorded incomplete response rejected' unless st.success?
      return
    end
    raise 'simulated timeout; no retry' if @scenario=='timeout'
    if @scenario=='error'
      FileUtils.cp(File.join(ROOT,'fixtures/invalid-output-mime.json'),File.join(p,'response.json'))
      File.write(File.join(p,'http-status.txt'),'400');File.write(File.join(p,'transport-exit-code.txt'),'0')
      raise 'simulated recorded HTTP 400; no retry'
    end

    w,h=JSON.parse(File.read(File.join(p,'rule-trace.json')))['expectedDimensions']
    chunk=lambda{|type,data| [data.bytesize].pack('N')+type+data+[Zlib.crc32(type+data)].pack('N')}
    png="\x89PNG\r\n\x1a\n".b+chunk.call('IHDR',[w,h,8,2,0,0,0].pack('NNCCCCC'))+chunk.call('IDAT',Zlib::Deflate.deflate(("\x00".b+([31,60,78].pack('CCC')*w))*h))+chunk.call('IEND',''.b)
    # Construct a REAL JPEG fixture. Only mock uses conversion; live bytes are untouched.
    File.binwrite(File.join(p,'mock-source.png'),png)
    _,converted=Open3.capture2(File.expand_path('../deploy/image_probe.py',__dir__),'-s','format','jpeg',File.join(p,'mock-source.png'),'--out',File.join(p,'mock-source.jpg'),err:File::NULL)
    raise 'mock JPEG creation failed' unless converted.success?
    image={type:'image',mime_type:'image/jpeg',data:Base64.strict_encode64(File.binread(File.join(p,'mock-source.jpg')))}

    images=@scenario=='multiple' ? [image,image] : [image]
    atomic(File.join(p,'response.json'),{model:'gemini-3.1-flash-image',status:'completed',steps:[{type:'model_output',content:images}],usage:{total_input_tokens:0,total_output_tokens:0,total_thought_tokens:0,total_tokens:0}})
    _,st=Open3.capture2('/usr/bin/osascript','-l','JavaScript',File.join(ROOT,'local-io.js'),'parse',ROOT,p,'200',err:File::NULL)
    raise 'mock response rejected' unless st.success?
  end
  def perform(id)
    p=job(id)
    begin
      if @mock
        mock_response(p)
      else
        r,w=IO.pipe
        # Secret stays in memory/anonymous pipe. Never argv, file, log or response.
        writer=Thread.new{begin;w.write("x-goog-api-key: #{@key}\n");ensure;w.close;end}
        pid=Process.spawn({'GEMINI_API_KEY'=>nil},'/bin/zsh','-f',File.join(ROOT,'bridge-worker.zsh'),p,3=>r,close_others:true,out:File::NULL,err:File::NULL)
        r.close;_,st=Process.wait2(pid);writer.join
        @key=nil
        raise 'transport stopped; see numeric diagnostics; remote cost may be unknown' unless st.success?
      end
      result=JSON.parse(File.read(File.join(p,'result.json')));u=result['usage']
      raise 'missing or invalid usage' unless u.is_a?(Hash)&&%w[total_input_tokens total_output_tokens total_thought_tokens total_tokens].all?{|k|u[k].is_a?(Integer)&&u[k]>=0}
      raise 'generation usage exceeds accounting allowance; stop' unless u['total_input_tokens']<=RulesCompiler::INPUT_TOKEN_ALLOWANCE&&u['total_output_tokens']+u['total_thought_tokens']<=4096
      size,st=Open3.capture2(File.expand_path('../deploy/image_probe.py',__dir__),'-g','pixelWidth','-g','pixelHeight','-g','format',File.join(p,'output.jpg'),err:File::NULL)
      dims=snapshot(id)['ruleTrace']['expectedDimensions']
      raise 'wrong output dimensions' unless st.success?&&size[/pixelWidth: (\d+)/,1].to_i==dims[0]&&size[/pixelHeight: (\d+)/,1].to_i==dims[1]&&size[/format: (\w+)/,1]=='jpeg'
      s=snapshot(id);s['state']=@mock ? 'mock-result' : 'generated-pending-review';s['usage']=u;s['outputMime']='image/jpeg';s['outputFilename']='output.jpg';s['outputHash']=Digest::SHA256.file(File.join(p,'output.jpg')).hexdigest;s['visualAcceptance']='not-evaluated';s['finishedAt']=Time.now.utc.iso8601;atomic(File.join(p,'state.json'),s)
    rescue => e
      @key=nil unless @mock
      s=snapshot(id);s['state']='stopped';s['error']=e.message;s['remoteOutcome']=@mock ? 'mock only; no charge' : 'unknown';s['finishedAt']=Time.now.utc.iso8601
      if File.file?(File.join(p,'response.json'))
        begin
          response=JSON.parse(File.read(File.join(p,'response.json')))
          provider=response['error']
          if response['status']=='incomplete'
            s['providerStatus']='incomplete'
            s['remoteOutcome']=@mock ? 'mock only; no charge' : 'incomplete; billing unconfirmed'
            s['error']='Provider returned incomplete; no accepted image; stopped without retry or fallback'
            s['hasOutputImage']=false
            u=response['usage']
            if u.is_a?(Hash)&&%w[total_input_tokens total_output_tokens total_thought_tokens total_tokens].all?{|k|u[k].is_a?(Integer)&&u[k]>=0}
              s['usage']=u.select{|k,_|%w[total_input_tokens total_output_tokens total_thought_tokens total_tokens].include?(k)}
            end
          end
          if provider.is_a?(Hash)
            s['providerError']=provider.select{|k,_|%w[code status message].include?(k)}
            s['error']="Provider error: #{provider['message'].to_s[0,800]}"
          end
        rescue JSON::ParserError
          # Preserve raw response without inventing a parsed provider error.
        end
      end
      %w[transport-exit-code.txt http-status.txt].each{|f|s[f]=File.read(File.join(p,f)).strip if File.file?(File.join(p,f))};atomic(File.join(p,'state.json'),s)
    end
  end
  def review(id,d)
    @mutex.synchronize do
      s=snapshot(id);raise 'no completed image' unless %w[mock-result generated-pending-review composed-pending-review].include?(s['state'])
      assessment=s.dig('ruleTrace','version').to_s.start_with?('car-light-direct-','car-light-product-') ? DirectReview.assess(s.fetch('ruleTrace'),d['decisions']) : RulesCompiler.review(s.fetch('ruleTrace'),d['decisions'])
      s['visualAcceptance']=@mock ? 'mock-review-only' : assessment['overall'];s['review']=assessment.merge('at'=>Time.now.utc.iso8601)
      atomic(File.join(job(id),'state.json'),s);s
    end
  end
  def serve(port)
    origin="http://127.0.0.1:#{port}"
    ready=lambda do
      approval_id=@reference_daily ? 'reference-daily-per-click' : @gc_once ? GC_COMPARISON_APPROVAL['id'] : @repair_once ? @approval['id'] : 'module-one-single-20261017'
      remaining=@gc_once ? gc_comparison_status['remaining'] : File.exist?(@ledger) ? 0 : 1
      puts "READY #{origin} rules=#{@reference_daily ? DirectImagePlan::SPEC : RulesCompiler::VERSION} mode=#{@mock ? 'MOCK-no-network' : 'LIVE'} approval=#{approval_id} remaining=#{remaining} budget=USD0.26 analysis=disabled"
      STDOUT.flush
      unless @mock
        begin;Process.spawn('/usr/bin/open',origin,out:File::NULL,err:File::NULL)
        rescue SystemCallError;warn "浏览器未自动打开；服务已启动，可手动访问 #{origin}。";end
      end
    end
    server=WEBrick::HTTPServer.new(StartCallback:ready,BindAddress:
'127.0.0.1',Port:port,AccessLog:[],Logger:WEBrick::Log.new(File::NULL,WEBrick::Log::FATAL),RequestTimeout:10,MaxClients:12)
    server.mount_proc('/') do |req,res|
      begin
        raise 'local origin required' unless req.peeraddr[3]=='127.0.0.1'&&req['host']=="127.0.0.1:#{port}"
        top_level_entry=req.request_method=='GET'&&req.path=='/'&&req['sec-fetch-mode']=='navigate'&&req['sec-fetch-dest']=='document'
        raise 'cross-site blocked' if !top_level_entry&&(req['sec-fetch-site']=='cross-site'||(req['origin']&&req['origin']!=origin))
        res['Cache-Control']='no-store';res['X-Content-Type-Options']='nosniff';res['Content-Security-Policy']="default-src 'self'; script-src 'self'; style-src 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'; frame-ancestors 'none'; form-action 'none'"
        path=req.path
        if path=='/api/session'&&req.request_method=='GET'
          out={generationLiveEnabled:@audited_once==true,approval:@repair_once ? @approval : nil,rulesVersion:RulesCompiler::VERSION,analysisModel:VisualAnalysis::MODEL,analysisLiveEnabled:ANALYSIS_LIVE_ENABLED,token:@token,mock:@mock,budgetMicroUSD:LIMIT,remaining:File.exist?(@ledger)?0:1,history:Dir.glob(File.join(@data,'*','state.json')).map{|p|JSON.parse(File.read(p))},previous:{state:'stopped',approval:'consumed',remoteOutcome:'unknown',hasImage:false}}
          out[:generationLiveEnabled]=GENERATION_LIVE_ENABLED&&@audited_once==true
          out[:maintenanceAvailable]=@supervised
          out[:loadedAnalysisRepair]=CurrentInputSession::LOADED_ANALYSIS_REPAIR
          out[:applicationId]='PictureGenerate.LocalWorkbench'
          out[:paidRequestsPaused]=!@mock&&LiveRequestPause.active?
          out[:history]=Dir.glob(File.join(@data,'*','state.json')).map{|p|snapshot(File.basename(File.dirname(p)))}
          out[:offlineReference]={enabled:true,providerVersion:ReferenceProvider::VERSION,outputContractVersion:AnalysisOutputContract::VERSION,history:internal_list}
          out[:internalReference]={enabled:@internal_reference,history:@internal_reference ? internal_list : []}
          out[:gcComparison]=gc_comparison_status
          out[:genericGC]=generic_status
          out[:productDaily]={enabled:@product_daily==true,version:DirectImagePlan::PRODUCT_SPEC,policyVersion:ProductIdentityPolicy::VERSION,requiresGenerateClick:true,maxRequestsPerTask:1,retries:0,analysisCalls:0,budgetMicroUSD:270000}
          out[:referenceDaily]={enabled:@reference_daily,version:DirectImagePlan::SPEC,name:'参考图卖点重构',requiresGenerateClick:true,maxRequestsPerTask:1,retries:0,analysisCalls:0,budgetMicroUSD:260000}
          out[:genericAnalysis]={enabled:@mock||!@generic_analysis_approval.nil?,approval:@generic_analysis_approval}
        elsif path.start_with?('/api/')
          raise 'session token required' unless req['x-session-token']==@token
          if req.request_method=='POST'
            raise 'same origin required' unless req['origin']==origin
            raise 'JSON required' unless req['content-type'].to_s.split(';')[0]=='application/json'
            body_limit=[INTERNAL_REFERENCE_PATH,'/api/local-typography'].include?(path) ? 32000000 : ['/api/freeze','/api/product-assets/prepare'].include?(path) ? 12000000 : 6000000
            raise 'body too large or length absent' unless req['content-length']&&req['content-length'].to_i.between?(1,body_limit)
            d=JSON.parse(req.body)
            @operations.synchronize do
            raise 'maintenance pending; no new operation accepted' if @maintenance
            LiveRequestPause.check! if !@mock&&!%w[/api/freeze /api/review /api/maintenance/restart /api/internal/reference /api/local-typography /api/product-assets/prepare /api/cumulative-scene/execute].include?(path)
            case path
            when '/api/cumulative-scene/execute'
              raise 'hash-only bounded request required' unless d.keys==['requestHash']
              out=CumulativeSceneRunner.run(d['requestHash'],key:@key,supervised:@supervised)
            when '/api/product-assets/prepare'
              reference=Base64.strict_decode64(d.fetch('imageBase64'));product=d['module']=='product-replacement' ? Base64.strict_decode64(d.fetch('productImageBase64')) : nil
              raise 'source hash mismatch' unless Digest::SHA256.hexdigest(reference)==d['sourceHash']&&(product ? Digest::SHA256.hexdigest(product)==d['productHash'] : d['productHash'].nil?)
              opts=d.reject{|k,_|%w[imageBase64 productImageBase64 sourceHash productHash budgetMicroUSD localRendererVersion].include?(k)}
              frozen=DirectImagePlan.prepare(reference,product,DefaultProductFacts.apply(opts),mock:false,input_origin:'user')
              preparation=LocalPreparationRecord.save(@data,frozen,reference,product,raw_options:opts)
              frozen=LocalPreparationRecord.frozen_for(@data,preparation,frozen)
              fresh_mock=@mock&&@scenario=='current-input'
              assistant_file=File.join(@data,'assistant-analysis-inputs.json')
              assistant=fresh_mock&&File.file?(assistant_file) ? JSON.parse(File.read(assistant_file))[frozen.dig('binding','sourceHash')] : nil
              historical_file=File.join(@data,'historical-scene-inputs.json')
              historical=fresh_mock&&File.file?(historical_file) ? JSON.parse(File.read(historical_file))[frozen.dig('binding','sourceHash')] : nil
              session_config=!@mock&&CurrentInputSession.config_for(frozen)
              reviewed_continuation=(!fresh_mock && !session_config && d['localRendererVersion']=='source-geometry-2') ? FreshAnalysisIntake.continue(frozen,exact_only:true) : nil
              current=if reviewed_continuation
                nil
              elsif d['localRendererVersion']!='source-geometry-2'
                {'state'=>'saved-local-input-awaiting-current-renderer','jobHash'=>frozen.dig('binding','requestHash'),'newModelCalls'=>0}
              elsif session_config
                CurrentInputSession.run(frozen,key:@key,supervised:@supervised,config:session_config)
              elsif assistant
                LocalAssistantAnalysis.run(frozen,reference,assistant)
              elsif historical && !product
                LocalHistoricalContinuation.run(frozen,reference,historical)
              elsif fresh_mock
                CurrentInputPipeline.run(frozen,root:File.join(@data,'current-input-jobs'),transport:CurrentInputPipeline.fixture_transport(File.join(@data,'current-input-fixtures.json'),source_hash:frozen.dig('binding','sourceHash')))
              elsif File.directory?(File.join(CurrentInputPipeline::ROOT,frozen.dig('binding','requestHash')))
                CurrentInputPipeline.run(frozen)
              end
              continuation=current&&current['state']=='analysis-ready-for-local-composition' ? current : (reviewed_continuation || (fresh_mock ? nil : FreshAnalysisIntake.continue(frozen,exact_only:true)))
              if continuation&&continuation['state']!='analysis-ready-for-local-composition'
                current=continuation;continuation=nil
              end
              package=(continuation||fresh_mock||current) ? nil : ProductAssetProvider.cache(frozen,File.join(ROOT,'product-asset-cache'),mock:@mock)
              continuation ||= (package||fresh_mock||current) ? nil : FreshAnalysisIntake.continue(frozen)
              if continuation&&continuation['state']!='analysis-ready-for-local-composition'
                current=continuation;continuation=nil
              end
              current ||= CurrentInputPipeline.run(frozen) unless continuation||package
              continuation['localOCR']=LocalReferenceOCR.observe(reference,d['sourceHash']) if continuation&&continuation['proposal']
              out={preparationTaskId:preparation['id'],currentInput:current&&current.reject{|k,_|%w[proposal candidateProposal scenes].include?(k)},analysisContinuation:continuation,sceneInputContract:{version:BackgroundSceneContract::VERSION,deliveryKind:'scene-candidate-only',localDecorationRequired:true,geometryReviewRequired:false,deterministicBindingChecksRequired:true,sceneAssetCount:'determined-by-source-panel-observations',automaticCompositionAllowed:!!continuation},options:frozen['options'],state:package ? 'cached-assets-ready' : continuation ? continuation['state'] : 'awaiting-new-authorization',package:package,analysisPlan:(package||continuation||current) ? nil : (product ? ProductAssetProvider.prepare(frozen) : ReferenceProvider.prepare(frozen,'layout-copy')),maxRequests:2,budgetMicroUSD:280000,analysisCalls:1,backgroundCalls:1,productGenerationCalls:0,retries:0,postGenerationModelCalls:0,liveEnabled:false}
            when '/api/local-typography';out=internal_operation(d,offline:true)
            when INTERNAL_REFERENCE_PATH;out=internal_operation(d)
            when '/api/direct/approved-once';out=execute_approved_direct(d)
            when '/api/analysis-wire/execute';out=execute_wire_analysis(d)
            when '/api/analysis-gc/execute';out=execute_analysis_gc(d)
            when '/api/analysis-gc-enum/execute';out=execute_analysis_gc_enum(d)
            when '/api/generic/analyze';out=analyze_generic(d)
            when '/api/product/repeat';out=repeat_product_task(d)
            when '/api/generic/generate';out=generate_generic(d)
            when '/api/experiment/generate-content';out=generate_gc_comparison(d)
            when '/api/maintenance/restart'
              raise 'restart requires user-started supervisor' unless @supervised
              raise 'empty restart request required' unless d=={}
              running=Dir.glob(File.join(@data,'*','state.json')).any?{|p|JSON.parse(File.read(p))['state']=='running'}
              raise 'task running; restart blocked' if running
              maintenance_preflight
              @maintenance=true
              out={state:'restarting',message:'仅重启本服务；不会发送模型请求或恢复额度。'}
              Thread.new{sleep 0.5;server.shutdown}
            when '/api/analyze';out=analyze_task(d)
            when '/api/freeze';raise '新任务必须使用当前直接生成流程' unless [DirectImagePlan::SPEC,DirectImagePlan::PRODUCT_SPEC].include?(d['businessSpec']);out=freeze_task(d)
            when '/api/generate';out=generate(d['id'],d['requestHash'])
            when '/api/review';out=review(d['id'],d)
            else;raise 'unknown operation'
            end
            end
          elsif req.request_method=='GET'&&path.match(%r{\A/api/internal/reference/([0-9a-f-]+)/image\z})
            raise 'internal reference disabled' unless @internal_reference
            id=path.split('/')[-2];r=internal_read(id)
            raise 'no matching internal output' unless r['output']&&req.query['hash']==r['outputHash']
            res['Content-Type']='image/png';res['Content-Disposition']="attachment; filename=INTERNAL-#{id}.png";res.body=internal_bytes(r['output']);next
          elsif req.request_method=='GET'&&path.match(%r{\A/api/task/([0-9a-f]{24})(?:/(image|reference|product|record|background))?\z})
            m=path.match(%r{\A/api/task/([0-9a-f]{24})(?:/(image|reference|product|record|background))?\z});id=m[1];kind=m[2];s=snapshot(id)
            if kind=='image'
              raise 'no completed image' unless %w[mock-result generated-pending-review composed-pending-review].include?(s['state'])
              filename=s['outputFilename']||'output.jpg';raise 'invalid output filename' unless %w[output.jpg output.png].include?(filename)
              bytes=File.binread(File.join(job(id),filename))
              raise 'output hash mismatch; original download blocked' unless s['outputHash']&&Digest::SHA256.hexdigest(bytes)==s['outputHash']
              res['Content-Type']=s['outputMime']||'image/jpeg';res.body=bytes;next
            elsif kind=='background'
              raise 'not a composite task' unless s['workflow']=='reference-layer-composite'
              bytes=File.binread(File.join(job(id),'background.jpg'))
              raise 'background hash mismatch' unless Digest::SHA256.hexdigest(bytes)==s['backgroundHash']
              res['Content-Type']='image/jpeg';res.body=bytes;next
            elsif kind=='product'
              raise 'not a product task' unless s['module']=='product-replacement'
              filename,mime=input_asset(s,'product');res['Content-Type']=mime;res.body=File.binread(File.join(job(id),filename));next
            elsif kind=='reference'
              filename,mime=input_asset(s,'reference');res['Content-Type']=mime;res.body=File.binread(File.join(job(id),filename));next
            else;out=s
            end
          else;raise 'unknown operation'
          end
        elsif req.request_method=='GET'
          files={'/'=>'bridge.html','/composite-history-ui.js'=>'composite-history-ui.js','/bridge.js'=>'bridge.js','/original-ui.js'=>'original-ui.js','/business-ui.js'=>'business-ui.js','/frozen-draft.js'=>'frozen-draft.js'}
          if true # Local offline composition assets; model routes retain their gates.
            %w[product-workbench-ui.js reference-inspired-ui.js automatic-analysis-compose.js quality-layout.js text-presentation.js copy-layout-contract.js deterministic-decoration.js reference-layout-anchors.js product-auto-compose.js product-local-compose.js product-local-ui.js ink-review-ui.js internal-product-canvas.js internal-inter-text.js internal-reference-workflow.js internal-reference-server.js reference-type-scale.js reference-ink-evidence.js].each{|f|files['/'+f]=f}
          end
          fonts={'/fonts/InterVariable.ttf'=>'InterVariable.ttf','/fonts/InterVariable-Italic.ttf'=>'InterVariable-Italic.ttf'}
          if fonts[path];res['Content-Type']='font/ttf';res.body=File.binread(File.join(ROOT,'assets/fonts/inter-4.1',fonts[path]));next;end
          file=files[path];raise 'not found' unless file
          res['Content-Type']=file.end_with?('.js')?'application/javascript; charset=utf-8':'text/html; charset=utf-8';res.body=File.read(File.join(ROOT,file));next
        else;raise 'method blocked'
        end
        res['Content-Type']='application/json';res.body=JSON.generate(out)
      rescue => e
        res.status=400;res['Content-Type']='application/json';res.body=JSON.generate(error:e.message)
      end
    end
    trap('INT'){server.shutdown};trap('TERM'){server.shutdown}
    begin
      server.start
    ensure
      puts "STOPPED #{origin} rules=#{RulesCompiler::VERSION}；监听已关闭。已发请求不会因退出而退还额度，请按保存状态核对。"
      STDOUT.flush
    end
    @maintenance ? 75 : 0
  end
end
require_relative 'bridge-gc-experiment'
Bridge.include(BridgeGCExperiment)
require_relative 'bridge-generic-gc'
Bridge.include(BridgeGenericGC)
require_relative 'bridge-wire-analysis'
Bridge.include(BridgeWireAnalysis)
require_relative 'bridge-analysis-gc'
Bridge.include(BridgeAnalysisGC)
require_relative 'bridge-direct-image'
Bridge.include(BridgeDirectImage)
require_relative 'bridge-internal-reference'
require_relative 'fresh-analysis-intake'
require_relative 'current-input-pipeline'
require_relative 'current-input-session'
require_relative 'local-preparation-record'
require_relative 'local-historical-continuation'
require_relative 'local-assistant-analysis'
require_relative 'local-reference-ocr'
require_relative 'history-input-recovery'
if __FILE__==$0
  if ARGV==['--maintenance-inspect']
    puts JSON.generate(rulesVersion:RulesCompiler::VERSION,budget:Bridge::LIMIT,generationEnabled:Bridge::GENERATION_LIVE_ENABLED,analysisEnabled:Bridge::ANALYSIS_LIVE_ENABLED,auditedApproval:Bridge::AUDITED_REPAIR,gcApproval:Bridge::GC_COMPARISON_APPROVAL)
    exit
  end
  mock=ARGV.include?('--mock'); port=ARGV.include?('--port') ? Integer(ARGV[ARGV.index('--port')+1]) : 8773
  raise 'invalid port' unless port.between?(1024,65535)
  data=mock&&ARGV.include?('--data') ? File.expand_path(ARGV[ARGV.index('--data')+1]) : File.join(Bridge::ROOT,mock ? 'mock-bridge-jobs' : 'bridge-jobs')
  scenario=mock&&ARGV.include?('--scenario') ? ARGV[ARGV.index('--scenario')+1] : 'success'
  boot=nil
  if ARGV.include?('--supervised-fd')
    fd=Integer(ARGV[ARGV.index('--supervised-fd')+1]);raise 'invalid boot descriptor' unless fd==3
    io=IO.for_fd(fd);boot=JSON.parse(io.read(16384));io.close
    expected=ARGV.include?('--gc-comparison-once') ? Bridge::GC_COMPARISON_APPROVAL : ARGV.include?('--audited-repair-once') ? Bridge::AUDITED_REPAIR : nil
    raise 'supervised approval/rules binding changed; manual authorization required' unless boot['approval']==expected&&boot['rulesVersion']==RulesCompiler::VERSION
  end
  daily=ARGV.include?('--reference-daily-stdin')
  image_proxy=nil
  if daily
    raise 'daily profile cannot combine startup profiles' if boot || ARGV.any?{|a|%w[--jpeg-repair-once --audited-repair-once --gc-comparison-once].include?(a)}
    daily_boot=JSON.parse(STDIN.read(16384))
    image_proxy=daily_boot['imageProxy']
    raise '这是反代版本，启动需要 imageProxy 配置。请先运行 python3 scripts/setup-proxy.py，再用 python3 scripts/run-proxy.py 或 compose.proxy.yaml。未调用模型。' unless image_proxy.is_a?(Hash)
    raise 'daily startup binding changed' unless daily_boot.keys.sort==%w[imageProxy rulesVersion] && daily_boot['rulesVersion']==DirectImagePlan::SPEC
    script=File.expand_path('../deploy/image_proxy.py',__dir__)
    parsed,err,checked=Open3.capture3('python3',script,'check','--config',image_proxy.fetch('configPath'))
    raise(err.strip.empty? ? '反代配置无效，未调用模型。' : err.strip) unless checked.success?
    checked_proxy=JSON.parse(parsed)
    image_proxy={'configPath'=>image_proxy.fetch('configPath'),'baseUrl'=>checked_proxy.fetch('baseUrl'),'model'=>checked_proxy.fetch('model')}
  end
  key=mock ? nil : (daily ? nil : (boot ? boot.delete('key') : ENV.delete('GEMINI_API_KEY')))
  abort('STOP: launch from the existing manually configured session; no request made') unless mock||daily||(key&&key.match?(/\A[A-Za-z0-9._-]+\z/))
  bridge=Bridge.new(mock:mock,data:data,scenario:scenario,key:key,internal_reference:ARGV.include?('--internal-reference'),repair_once:ARGV.include?('--jpeg-repair-once'),audited_once:ARGV.include?('--audited-repair-once'),supervised:!boot.nil?,gc_once:ARGV.include?('--gc-comparison-once'),generic_approval:boot&&boot['genericApproval'],generic_analysis_approval:boot&&boot['genericAnalysisApproval'],reference_daily:daily,product_daily:ARGV.include?('--product-daily'),image_proxy:image_proxy)
  key=nil
  begin
    exit bridge.serve(port)
  rescue Errno::EADDRINUSE
    warn "START FAILED: 127.0.0.1:#{port} 已被占用。本次服务未启动，也未自动打开网页；仍打开的页面可能连接旧服务。请先核对实际运行服务的终端。未改端口、未调用模型。"
    exit 78
  rescue Errno::EACCES, Errno::EPERM
    warn "START FAILED: 无权监听 127.0.0.1:#{port}。本次未启动服务、未调用模型。"
    exit 77
  end
end
