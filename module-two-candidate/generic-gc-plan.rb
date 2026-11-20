# Offline candidate v1. No transport, credential access, or live execution method.
require_relative 'visual-analysis'
require_relative 'generate-content-adapter'
require_relative 'business-rules'
require_relative 'provider-capabilities'
module GenericGCPlan
  VERSION='generic-gc-offline-20261018.1'
  def self.prepare(bytes,analysis,options,allow_mock:false)
    VisualAnalysis.need(bytes.bytesize<=4*1024*1024&&bytes.start_with?("\xff\xd8\xff".b),'original JPEG <=4MiB required')
    Tempfile.create(['generic-source','.jpg']) do |f|
      f.binmode;f.write(bytes);f.flush
      size,status=Open3.capture2(File.expand_path('../deploy/image_probe.py',__dir__),'-g','pixelWidth','-g','pixelHeight',f.path,err:File::NULL)
      VisualAnalysis.need(status.success?,'invalid JPEG')
      w=size[/pixelWidth: (\d+)/,1].to_i;h=size[/pixelHeight: (\d+)/,1].to_i
      hash=Digest::SHA256.hexdigest(bytes)
      VisualAnalysis.validate(analysis,hash,w,h,allow_mock:allow_mock)
      allowed=options.key?('businessSpec') ? %w[businessSpec mode output layoutTone layoutMode layoutInstructions customCopy brandName productParameters color] : %w[mode output layoutTone customCopy]
      VisualAnalysis.need((options.keys-allowed).empty?,'unknown frontend option')
      c=options.key?('businessSpec') ? BusinessRules.compile(options,analysis,hash) : RulesCompiler.compile(options.merge('analysis'=>analysis,'sceneChange'=>analysis['sceneChange']),hash)
      ProviderCapabilities.validate(c['output'],1,260000) if options['businessSpec']==BusinessRules::CURRENT
      body={'contents'=>[{'role'=>'user','parts'=>[{'text'=>c['prompt']},{'inlineData'=>{'mimeType'=>'image/jpeg','data'=>Base64.strict_encode64(bytes)}}]}],
        'generationConfig'=>{'candidateCount'=>1,'responseModalities'=>['IMAGE'],'maxOutputTokens'=>4096,
        'thinkingConfig'=>{'thinkingLevel'=>'MINIMAL'},'imageConfig'=>{'aspectRatio'=>c['output']['aspectRatio'],'imageSize'=>'2K'}}}
      raw=JSON.generate(body)
      binding={'version'=>VERSION,'endpoint'=>GenerateContentAdapter::ENDPOINT,'model'=>GenerateContentAdapter::MODEL,
        'sourceHash'=>hash,'requestHash'=>Digest::SHA256.hexdigest(raw),'analysisHash'=>Digest::SHA256.hexdigest(JSON.generate(analysis)),
        'traceHash'=>Digest::SHA256.hexdigest(JSON.generate(c['trace'])),'budgetMicroUSD'=>260000,'conservativeMicroUSD'=>258560,
        'inputTokenReserve'=>25600,'maxOutputTokens'=>4096,'maxRequests'=>1,'retries'=>0,'analysisCalls'=>0,
        'expectedDimensions'=>c['trace']['expectedDimensions'],'liveEnabled'=>false,'mock'=>analysis['origin']=='mock'}
      {'body'=>raw,'binding'=>binding,'analysis'=>analysis,'options'=>options,'trace'=>c['trace']}
    end
  end
  def self.validate(plan)
    bytes=Base64.strict_decode64(JSON.parse(plan.fetch('body')).fetch('contents')[0].fetch('parts')[1].fetch('inlineData').fetch('data'))
    expected=prepare(bytes,plan.fetch('analysis'),plan.fetch('options'),allow_mock:plan.dig('binding','mock')==true)
    VisualAnalysis.need(expected==plan,'frozen generic plan changed')
    true
  end
  # Exercises the same pre-dispatch atomic reservation needed by a future live
  # adapter. Explicitly simulation only; never creates a production allowance.
  def self.reserve_simulation(plan,root,approval)
    validate(plan)
    VisualAnalysis.need(approval==plan['binding'],'exact plan approval required')
    FileUtils.mkdir_p(root,mode:0700)
    ledger=File.join(root,'simulation-'+approval.fetch('requestHash'))
    begin;Dir.mkdir(ledger,0700);rescue Errno::EEXIST;raise VisualAnalysis::Invalid,'already reserved; no retry';end
    File.write(File.join(ledger,'binding.json'),JSON.pretty_generate(approval))
    {'state'=>'simulation-reserved','networkRequests'=>0,'ledger'=>ledger}
  end
end
