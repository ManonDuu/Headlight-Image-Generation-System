require_relative 'direct-image-plan'
require_relative 'direct-review'
module BridgeDirectImage
  def direct_input(d)
    encoded=d['imageBase64'];raise 'invalid image size' unless encoded.is_a?(String)&&encoded.bytesize<=5600000
    bytes=Base64.strict_decode64(encoded);info=InputImage.inspect(bytes)
    hash=Digest::SHA256.hexdigest(bytes);raise 'source digest mismatch' unless hash==d['sourceHash']
    [bytes,hash,info]
  end
  def input_asset(s,role)
    mime=s[role=='reference' ? 'sourceMime' : 'productMime']||'image/jpeg'
    [InputImage.filename(role,mime),mime]
  end
  # User approval 2026-10-18 06:24:35 UTC; exactly the already-reviewed request.
  # No general allowance, credential access, retry or analysis is enabled.
  def execute_approved_direct(d)
    raise 'exact task/hash required' unless d.keys.sort==%w[id requestHash]
    # First authority is already consumed. Second is the user's one replacement
    # example test, restricted by latest user instruction to an Amazon supplement.
    sources={
      '92c580d0b2ce4156a3d22db05dcbb19ac0a4c9f6a1572954b1c74878384d1e67'=>'d8b87596d3ea2218154b03abafd55333a8f46aa7fcdaca0f53fb63239c2d73ef',
      'e950a67ec718b79d2dbb487ced2b9dbe3d3873f1868bb076c66bcd73fe524238'=>'28399cad8a8e136d5cad8dbd88bb3d46763448e73755beb45a083a8f0b261814',
      '8ec0af2ce7c0dad555fd1a91226cd4ca68cc5f584819d2ea8b3ef2c57ce51ebc'=>'c8ecbd2ab205bc9cdd8f877f0edc5d2366e4197e4f5ce08b3cbbde9f05eba9a3'}
    raise 'wrong approved request' unless sources.key?(d['requestHash'])
    raise 'existing supervised session required' unless @mock||(@supervised&&@gc_once&&@key)
    plan=JSON.parse(File.read(File.join(job(d['id']),'generic-gc-plan.json')))
    DirectImagePlan.validate(plan)
    b=plan.fetch('binding')
    product_once=d['requestHash']=='8ec0af2ce7c0dad555fd1a91226cd4ca68cc5f584819d2ea8b3ef2c57ce51ebc'
    raise 'product test paused for shared rule reconciliation' if product_once&&File.exist?(File.join(__dir__,'assets/module-two-history/PAUSED'))
    raise 'approved product changed' if product_once&&b['productHash']!='9aa07d8850e99e2cf3326d62d060a63151d38ba4a7c5998d9d058f6cb1ffb6c5'
    raise 'approved binding changed' unless b['requestHash']==d['requestHash']&&b['sourceHash']==sources[d['requestHash']]&&b['budgetMicroUSD']==(product_once ? 270000 : 260000)&&b['maxRequests']==1&&b['retries']==0&&b['analysisCalls']==0&&b['module']==(product_once ? 'product-replacement' : 'reference-reconstruction')
    raise 'already attempted; no retry' if File.exist?(generic_ledger(b))
    begin
      @generic_approval=b
      generate_generic(d)
    ensure
      @generic_approval=nil
    end
  end
  def repeat_product_task(d)
    raise 'exact prior task required' unless d.keys==['id']
    prior=snapshot(d['id'])
    raise 'completed product task required' unless prior['module']=='product-replacement'&&prior['workflow']=='direct-generation'&&%w[generated-pending-review mock-result].include?(prior['state'])
    raise 'another task is running' if Dir.glob(File.join(@data,'*','state.json')).any?{|f|JSON.parse(File.read(f))['state']=='running'}
    req=Marshal.load(Marshal.dump(prior.fetch('rawUserOptions')))
    req['businessSpec']=DirectImagePlan::PRODUCT_SPEC;req['budgetMicroUSD']=270000
    %w[reference product].each do |role|
      name,_=input_asset(prior,role);bytes=File.binread(File.join(job(d['id']),name))
      expected=prior.fetch(role=='reference' ? 'sourceHash' : 'productHash')
      raise 'saved input digest mismatch' unless Digest::SHA256.hexdigest(bytes)==expected
      req[role=='reference' ? 'imageBase64' : 'productImageBase64']=Base64.strict_encode64(bytes)
      req[role=='reference' ? 'sourceHash' : 'productHash']=expected
    end
    freeze_direct(req) # Preparation only. A separate explicit generate click spends.
  end
  def freeze_direct(d)
    raise 'direct workflow unavailable in repair profile' if @repair_once
    allowed=%w[businessSpec module mode layoutMode layoutTone color customCopy brandName productParameters output productName sceneMode referenceCopy imageBase64 sourceHash productImageBase64 productHash budgetMicroUSD]
    raise 'unknown direct input; analysis/prompt/model overrides forbidden' unless (d.keys-allowed).empty?
    dual=d['module']=='product-replacement'
    raise 'reference module cannot include product or scene fields' if !dual&&%w[productImageBase64 productHash productName sceneMode].any?{|k|d.key?(k)}
    raise 'exact module budget required' unless d['budgetMicroUSD']==(dual ? 270000 : 260000)
    reference,hash,ri=direct_input(d)
    product,_,pi=dual ? direct_input({'imageBase64'=>d['productImageBase64'],'sourceHash'=>d['productHash']}) : [nil,nil,nil]
    options=d.reject{|k,_|%w[imageBase64 sourceHash productImageBase64 productHash budgetMicroUSD].include?(k)}
    plan=DirectImagePlan.prepare(reference,product,DefaultProductFacts.apply(options),mock:@mock,input_origin:'user')
    id=SecureRandom.hex(12);p=File.join(@data,id);Dir.mkdir(p,0700)
    File.binwrite(File.join(p,InputImage.filename('reference',ri['mime'])),reference)
    File.binwrite(File.join(p,InputImage.filename('product',pi['mime'])),product) if product
    atomic(File.join(p,'generic-gc-plan.json'),plan);atomic(File.join(p,'rule-trace.json'),plan['trace'])
    s={'id'=>id,'module'=>d['module'],'state'=>'frozen','workflow'=>'direct-generation','requestHash'=>plan['binding']['requestHash'],'genericGC'=>plan['binding'],'rulesHash'=>Digest::SHA256.file(File.join(p,'rule-trace.json')).hexdigest,'ruleTrace'=>plan['trace'],'sourceHash'=>hash,'mode'=>d['mode'],'prompt'=>JSON.parse(plan['body'])['contents'][0]['parts'][0]['text'],'budgetMicroUSD'=>d['budgetMicroUSD'],'mock'=>@mock,'visualAcceptance'=>'not-evaluated','preflight'=>plan['preflight'],'createdAt'=>Time.now.utc.iso8601}
    s['rawUserOptions']=options;s['inputProvenance']={'version'=>'input-origin-2','origin'=>'user','effectiveOptionsAreUserInput'=>false}
    s['productHash']=plan['binding']['productHash'] if dual
    s['sourceMime']=ri['mime'];s['sourceDimensions']=ri['dimensions']
    if dual;s['productMime']=pi['mime'];s['productDimensions']=pi['dimensions'];end
    atomic(File.join(p,'state.json'),s);s
  end
end
