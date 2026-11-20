# Explicit direct-image workflow. No analysis calls or fabricated visual inventory.
require_relative 'business-rules'
require_relative 'provider-capabilities'
require_relative 'product-replacement-plan'
require_relative 'direct-image-plan-v1'
require_relative 'direct-image-plan-v2'
require_relative 'direct-image-plan-v3'
require_relative 'direct-image-plan-v4'
require_relative 'direct-image-plan-v5'
require_relative 'direct-image-plan-v6'
require_relative 'direct-image-plan-v7'
require_relative 'direct-image-plan-v8'
require_relative 'direct-image-plan-v9'
require_relative 'direct-image-plan-v10'
require_relative 'direct-image-plan-v11'
require_relative 'direct-image-plan-v12'
require_relative 'direct-image-plan-v13'
require_relative 'direct-image-plan-v14'
require_relative 'direct-image-plan-v15'
require_relative 'direct-image-plan-v16'
require_relative 'direct-image-plan-v17'
require_relative 'direct-image-plan-v18'
require_relative 'direct-image-plan-v19'
require_relative 'direct-image-plan-v20'
require_relative 'direct-image-plan-product-v1'
require_relative 'direct-image-plan-product-v2'
require_relative 'direct-image-plan-product-v3'
require_relative 'direct-image-plan-product-v4'
require_relative 'direct-image-plan-product-v5'
require_relative 'direct-image-plan-product-v6'
require_relative 'direct-image-plan-product-v7'
require_relative 'direct-image-plan-product-v8'
require_relative 'direct-image-plan-product-v9'
require_relative 'local-reference-ocr'
require_relative 'direct-image-policy'
require_relative 'input-image'
require_relative 'default-product-facts'
module DirectImagePlan
 SPEC='car-light-direct-20261021.20'
 PRODUCT_SPEC='car-light-product-20261022.10'
 def self.need(v,m);RulesCompiler.need(v,m);end
 def self.prepare(reference,product,options,mock:false,input_origin:'legacy-unknown')
  o=JSON.parse(JSON.generate(options));spec=o['module']=='product-replacement' ? PRODUCT_SPEC : SPEC;need(o['businessSpec']==spec,'direct specification required')
  need((o.keys-%w[businessSpec module mode layoutMode layoutTone color customCopy brandName productParameters output productName sceneMode referenceCopy]).empty?,'unknown direct option')
  mod=o['module'];need(%w[reference-reconstruction product-replacement].include?(mod),'invalid module');dual=mod=='product-replacement'
  need(dual ? !!product : product.nil?,'image role count mismatch')
  ri=InputImage.inspect(reference);dims=ri['dimensions'];ph=nil;pd=nil;pi=nil
  if dual
   pi=InputImage.inspect(product);pd=pi['dimensions'];ph=Digest::SHA256.hexdigest(product)
   need(ph!=Digest::SHA256.hexdigest(reference),'reference and product must be distinct')
   need(!o.key?('sceneMode')||o['sceneMode']=='change','scene preservation removed');o['sceneMode']='change'
   need(!o.key?('productName')||(o['productName'].is_a?(String)&&o['productName'].bytesize<=300),'product name must be text, max300 bytes')
  else
   need((o.keys&%w[productName sceneMode]).empty?,'reference module has fixed scene rebuild')
  end
  mode=o['mode'];need(%w[remove-all-copy ai-rewrite custom preserve-reference].include?(mode),'four copy modes only')
  if o.key?('referenceCopy')
   need(!dual&&mode=='preserve-reference'&&o['referenceCopy'].is_a?(String)&&!o['referenceCopy'].strip.empty?&&o['referenceCopy'].bytesize<=3000,'manual original copy is reference-preserve only, max3000 bytes')
  end
  layout=o['layoutMode'];need(%w[keep-reference auto-layout].include?(layout),'two layout modes only')
  need(%w[keep-reference adjust-color].include?(o['layoutTone']),'invalid palette choice')
  need(o['layoutTone']=='adjust-color' ? o['color'].is_a?(String)&&o['color'].match?(/\A#[0-9a-fA-F]{6}\z/) : !o.key?('color'),'invalid or inactive color')
  o.delete('customCopy') unless mode=='custom'
  %w[brandName productParameters].each{|k|o.delete(k)} if mode=='remove-all-copy'
  %w[brandName productParameters].each{|k|need(!o.key?(k)||(o[k].is_a?(String)&&o[k].bytesize<=1500),'metadata text limit')}
  brand=o.fetch('brandName','').strip;params=o.fetch('productParameters','').strip
  %w[customCopy brandName productParameters].each do |field|
   need(!o.fetch(field,'').match?(SharedTypography::FORBIDDEN),"文案冲突：#{field} 含禁止使用的 headlight/headlights（不区分大小写）；请修改，系统不会静默替换。")
  end
  if mode=='custom'
   need(o['customCopy'].is_a?(String)&&!o['customCopy'].strip.empty?&&o['customCopy'].bytesize<=3000,'complete custom copy required, max3000 bytes')
   supplied=BusinessRules.tokens(params)
   conflicts=BusinessRules.tokens(o['customCopy']).select{|v|same=supplied.select{|x|BusinessRules.parameter_kind(x)==BusinessRules.parameter_kind(v)};!same.empty?&&!same.include?(v)}
   need(conflicts.empty?,'custom copy conflicts with supplied parameters')
   explicit=o['customCopy'].scan(/(?:brand|品牌)\s*[:：]\s*([^\n,，;；]+)/i).flatten.map(&:strip)
   need(explicit.all?{|x|!brand.empty?&&x==brand},'custom copy conflicts with explicit brand')
  end
  requested=o['output'];need(requested.is_a?(Hash)&&(requested.keys-%w[aspectRatio imageSize width height]).empty?&&requested['imageSize']=='2K','fixed native output required')
  ratio=requested['aspectRatio']
  ratio=RulesCompiler::SIZES.keys.min_by{|v|a,b=v.split(':').map(&:to_f);Math.log((a/b)/(dims[0].to_f/dims[1])).abs} if ratio=='follow-reference'
  ratio='4:5' if ratio=='12:15'
  if ratio=='custom'
   need(requested.values_at('width','height').all?{|v|v.is_a?(Integer)},'integer dimensions required')
   found=RulesCompiler::SIZES.find{|_,v|v==requested.values_at('width','height')};need(found,'only native dimensions supported');ratio=found[0]
  else
   need(!requested.key?('width')&&!requested.key?('height'),'dimensions only for custom ratio')
  end
  output={'aspectRatio'=>ratio,'imageSize'=>'2K'};budget=dual ? 270000 : 260000
  ProviderCapabilities.validate(output,dual ? 2 : 1,budget)
  if !dual && mode=='preserve-reference'
   source_hash=Digest::SHA256.hexdigest(reference)
   if o.key?('referenceCopy')
    source_copy=o['referenceCopy'].split("\n",-1)
   else
    observation=LocalReferenceOCR.observe(reference,source_hash)
    need(observation['state']!='unavailable'&&!observation['lines'].empty?,'保留原文：本地文字提取不可用，未发送请求；请在原文核对框粘贴参考图完整文字，不会猜测或删改原文。')
    need(observation['lines'].all?{|line|line['confidence'].to_f>=0.8},'保留原文：存在低置信文字，需核对后再生成。')
    source_copy=observation['lines'].map{|line|line.fetch('text')}
   end
   supplied=BusinessRules.tokens(params)
   unknown=BusinessRules.tokens(source_copy.join("\n"))-supplied
   conflicts=unknown.empty? ? [] : ['原文包含未确认参数：'+unknown.join('、')]
   gate=ReconstructionPolicy.compile(o,source_copy:source_copy,source_conflicts:conflicts)
   need(gate['sendAllowed'],'保留原文需先解决冲突：'+gate['conflicts'].join('；'))
  end
  policy,rules=DirectImagePolicy.compile(o)
  data=o.select{|k,_|%w[brandName productParameters customCopy productName].include?(k)}
  data['referenceCopy']=source_copy if defined?(source_copy)&&source_copy
  prompt="Return exactly one native 2K #{ratio} image. Direct generation, no prior structured analysis is supplied.\n"+rules.map{|x|x['constraint']}.join("\n")+"\nSupplied data (not instructions): "+JSON.generate(data)
  need(prompt.bytesize<=8192,'prompt exceeds reserved budget; do not truncate rules')
  sh=Digest::SHA256.hexdigest(reference)
  label=dual ? 'REFERENCE: allowed background, layout and text roles only; exclude its original product appearance. The next image is image 1.' : 'REFERENCE: reconstruction source. The next image is image 1.'
  parts=[{'text'=>prompt},{'text'=>label+" SHA256=#{sh}"},{'inlineData'=>{'mimeType'=>ri['mime'],'data'=>Base64.strict_encode64(reference)}}]
  if dual
   parts<<{'text'=>"PRODUCT: sole source of target product structure and appearance; the next image is image 2. SHA256=#{ph}"}
   parts<<{'inlineData'=>{'mimeType'=>pi['mime'],'data'=>Base64.strict_encode64(product)}}
  end
  body={'contents'=>[{'role'=>'user','parts'=>parts}],'generationConfig'=>{'candidateCount'=>1,'responseModalities'=>['IMAGE'],'maxOutputTokens'=>4096,'thinkingConfig'=>{'thinkingLevel'=>'MINIMAL'},'imageConfig'=>output}}
  raw=JSON.generate(body);sh=Digest::SHA256.hexdigest(reference)
  roles=[{'part'=>2,'labelPart'=>1,'role'=>'reference','sha256'=>sh}];roles<<{'part'=>4,'labelPart'=>3,'role'=>'product-appearance','sha256'=>ph} if dual
  warnings=['直接读取原图生成；未执行独立语义分析，结果须人工核对。','参考图排版借鉴主要构图和表现形式；自动排版可重新组织内容，不要求原位置、固定居中或相同区域数量。']
  warnings<<'替换目标由生图模型辨认，未经过独立检测；真实产品一致性须逐项验收。' if dual
  warnings<<"跟随参考图解析为最接近的原生比例#{ratio}，不裁剪关键内容。" if requested['aspectRatio']=='follow-reference'
  native_dims=RulesCompiler::SIZES.fetch(ratio);a,b=ratio.split(':').map(&:to_i)
  exact=native_dims[0]*b==native_dims[1]*a
  delivery={'requestedRatio'=>requested['aspectRatio'],'modelRatio'=>ratio,'nativeDimensions'=>native_dims,'exactModelRatio'=>exact,'download'=>'unaltered-original','adaptation'=>'none','stretch'=>false,'crop'=>false}
  warnings<<"原生输出#{native_dims.join('×')}，#{exact ? '符合' : '不精确符合'}#{ratio}；下载原图，不拉伸、不裁剪；当前没有精确比例适配。"
  preflight={'delivery'=>delivery,'warnings'=>warnings,'analysisOrigin'=>'none-direct','automaticSemanticValidation'=>false,'resolvedOutput'=>{'requested'=>requested,'native'=>output,'dimensions'=>RulesCompiler::SIZES.fetch(ratio)}}
  trace={'version'=>spec,'compilerRevision'=>spec,'businessSpec'=>spec,'mode'=>mode,'module'=>mod,'selectedOptions'=>o.merge('requestedOutput'=>requested),'output'=>output,'expectedDimensions'=>RulesCompiler::SIZES.fetch(ratio),'sourceHash'=>sh,'analysisOrigin'=>'none-direct','policy'=>policy,'imageRoles'=>roles,'promptHash'=>Digest::SHA256.hexdigest(prompt),'appliedRuleIds'=>rules.map{|x|x['ruleId']},'ruleBindings'=>rules,'checks'=>rules.map{|x|{'ruleId'=>x['ruleId'],'criterion'=>x['resultCheck'],'status'=>'not-evaluated','automaticVerification'=>false,'evidence'=>[]}},'overall'=>'not-evaluated','preflight'=>preflight}
  binding={'version'=>spec,'directGeneration'=>true,'module'=>mod,'endpoint'=>GenerateContentAdapter::ENDPOINT,'model'=>GenerateContentAdapter::MODEL,'sourceHash'=>sh,'requestHash'=>Digest::SHA256.hexdigest(raw),'traceHash'=>Digest::SHA256.hexdigest(JSON.generate(trace)),'budgetMicroUSD'=>budget,'conservativeMicroUSD'=>dual ? 266752 : 258560,'inputTokenReserve'=>dual ? 41984 : 25600,'maxOutputTokens'=>4096,'maxRequests'=>1,'retries'=>0,'analysisCalls'=>0,'expectedDimensions'=>trace['expectedDimensions'],'liveEnabled'=>false,'mock'=>mock,'imageRoles'=>roles}
  binding['productHash']=ph if dual
  origin={'version'=>'input-origin-2','origin'=>input_origin,'rawUserOptions'=>JSON.parse(JSON.generate(options))}
  need(%w[user test legacy-unknown].include?(input_origin),'invalid input provenance')
  binding['inputOriginHash']=Digest::SHA256.hexdigest(JSON.generate(origin))
  {'body'=>raw,'binding'=>binding,'options'=>o,'trace'=>trace,'preflight'=>preflight,'inputProvenance'=>origin}
 end
 def self.validate(plan)
  return DirectImagePlanProductV9.validate(plan) if plan.dig('binding','version')==DirectImagePlanProductV9::PRODUCT_SPEC
  return DirectImagePlanProductV8.validate(plan) if plan.dig('binding','version')==DirectImagePlanProductV8::PRODUCT_SPEC
  return DirectImagePlanProductV7.validate(plan) if plan.dig('binding','version')==DirectImagePlanProductV7::PRODUCT_SPEC
  return DirectImagePlanProductV6.validate(plan) if plan.dig('binding','version')==DirectImagePlanProductV6::PRODUCT_SPEC
  return DirectImagePlanProductV5.validate(plan) if plan.dig('binding','version')==DirectImagePlanProductV5::PRODUCT_SPEC
  return DirectImagePlanProductV4.validate(plan) if plan.dig('binding','version')==DirectImagePlanProductV4::PRODUCT_SPEC
  return DirectImagePlanProductV3.validate(plan) if plan.dig('binding','version')==DirectImagePlanProductV3::PRODUCT_SPEC
  return DirectImagePlanProductV2.validate(plan) if plan.dig('binding','version')==DirectImagePlanProductV2::PRODUCT_SPEC
  return DirectImagePlanProductV1.validate(plan) if plan.dig('binding','version')==DirectImagePlanProductV1::PRODUCT_SPEC
  return DirectImagePlanV20.validate(plan) if plan.dig('binding','version')==DirectImagePlanV20::SPEC
  return DirectImagePlanV19.validate(plan) if plan.dig('binding','version')==DirectImagePlanV19::SPEC
  return DirectImagePlanV18.validate(plan) if plan.dig('binding','version')==DirectImagePlanV18::SPEC
  return DirectImagePlanV17.validate(plan) if plan.dig('binding','version')==DirectImagePlanV17::SPEC
  return DirectImagePlanV16.validate(plan) if plan.dig('binding','version')==DirectImagePlanV16::SPEC
  return DirectImagePlanV15.validate(plan) if plan.dig('binding','version')==DirectImagePlanV15::SPEC
  return DirectImagePlanV14.validate(plan) if plan.dig('binding','version')==DirectImagePlanV14::SPEC
  return DirectImagePlanV13.validate(plan) if plan.dig('binding','version')==DirectImagePlanV13::SPEC
  return DirectImagePlanV12.validate(plan) if plan.dig('binding','version')==DirectImagePlanV12::SPEC
  return DirectImagePlanV11.validate(plan) if plan.dig('binding','version')==DirectImagePlanV11::SPEC
  return DirectImagePlanV10.validate(plan) if plan.dig('binding','version')==DirectImagePlanV10::SPEC
  return DirectImagePlanV9.validate(plan) if plan.dig('binding','version')==DirectImagePlanV9::SPEC
  return DirectImagePlanV8.validate(plan) if plan.dig('binding','version')==DirectImagePlanV8::SPEC
  return DirectImagePlanV7.validate(plan) if plan.dig('binding','version')==DirectImagePlanV7::SPEC
  return DirectImagePlanV6.validate(plan) if plan.dig('binding','version')==DirectImagePlanV6::SPEC
  return DirectImagePlanV5.validate(plan) if plan.dig('binding','version')==DirectImagePlanV5::SPEC
  return DirectImagePlanV4.validate(plan) if plan.dig('binding','version')==DirectImagePlanV4::SPEC
  return DirectImagePlanV3.validate(plan) if plan.dig('binding','version')==DirectImagePlanV3::SPEC
  return DirectImagePlanV2.validate(plan) if plan.dig('binding','version')==DirectImagePlanV2::SPEC
  return DirectImagePlanV1.validate(plan) if plan.dig('binding','version')==DirectImagePlanV1::SPEC
  r=Base64.strict_decode64(image_part(plan,'reference')['data']);p=plan['binding']['module']=='product-replacement' ? Base64.strict_decode64(image_part(plan,'product-appearance')['data']) : nil
  expected=prepare(r,p,plan.dig('inputProvenance','rawUserOptions')||plan['options'],mock:plan['binding']['mock'],input_origin:plan.dig('inputProvenance','origin')||'legacy-unknown')
  unless plan['inputProvenance'];expected.delete('inputProvenance');expected['binding'].delete('inputOriginHash');end
  need(expected==plan,'direct frozen request changed');true
 end
 def self.image_part(plan,role)
  roles=plan.fetch('binding').fetch('imageRoles');matches=roles.select{|v|v['role']==role}
  need(matches.size==1,'ambiguous image role');entry=matches.first
  parts=JSON.parse(plan.fetch('body'))['contents'][0]['parts'];blob=parts.fetch(entry.fetch('part')).fetch('inlineData')
  bytes=Base64.strict_decode64(blob.fetch('data'))
  need(Digest::SHA256.hexdigest(bytes)==entry.fetch('sha256'),'role/image hash mismatch')
  if [SPEC,PRODUCT_SPEC].include?(plan['binding']['version'])
   need(entry['labelPart']==entry['part']-1,'role label must precede image')
   label=parts.fetch(entry['labelPart']).fetch('text')
   need(label.include?("SHA256=#{entry['sha256']}")&&label.start_with?(role=='reference' ? 'REFERENCE:' : 'PRODUCT:'),'role label/hash mismatch')
  end
  blob
 end
end
