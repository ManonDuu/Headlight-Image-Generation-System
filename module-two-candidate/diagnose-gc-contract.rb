# Offline only: reconstruct exact frozen bytes, audit all paths, prepare diagnostic candidate.
require_relative 'analysis-gc-enum-candidate'
require_relative 'generic-gc-plan'
require 'cgi'
r=File.expand_path(__dir__);out=r+'/diagnostics/gc-contract-current';FileUtils.mkdir_p(out)
original=JSON.parse(File.read(r+'/generic-analysis-validation-20261018/analysis-plan.json'))
p=AnalysisGCEnumCandidate.prepare(original);raw=p['body'];b=VisualAnalysis.parse_json(raw)
ledger=r+'/live-attempts/analysis-gc-'+AnalysisGCEnumCandidate::HASH
binding=JSON.parse(File.read(ledger+'/binding.json'));raise 'request hash mismatch' unless Digest::SHA256.hexdigest(raw)==binding['requestHash']
paths=[];nulls=[];empty=[]
walk=lambda do |v,path|
 type=case v;when Hash;'object';when Array;'array';when String;'string';when Integer;'integer';when Float;'number';when TrueClass,FalseClass;'boolean';else;'null';end
 row={path:path,type:type};row[:length]=v.size if v.respond_to?(:size)&&!v.is_a?(Numeric);paths<<row
 nulls<<path if v.nil?;empty<<path if v.respond_to?(:empty?)&&v.empty?
 v.each{|k,x|walk.call(x,path+'.'+k)} if v.is_a?(Hash)
 v.each_with_index{|x,i|walk.call(x,path+'['+i.to_s+']')} if v.is_a?(Array)
end
walk.call(b,'$')
blob=b['contents'][0]['parts'][1]['inlineData'];bytes=Base64.strict_decode64(blob['data'])
raise 'not original JPEG' unless bytes==File.binread(r+'/assets/81gMZuoRq6L._AC_SL1500_.jpg')&&bytes.start_with?("\xff\xd8\xff".b)&&bytes.end_with?("\xff\xd9".b)
size,st=Open3.capture2(File.expand_path('../deploy/image_probe.py',__dir__),'-g','pixelWidth','-g','pixelHeight',r+'/assets/81gMZuoRq6L._AC_SL1500_.jpg');raise unless st.success?&&size[/pixelWidth: (\d+)/,1]=="1200"&&size[/pixelHeight: (\d+)/,1]=="1500"
keywords=[];schema_walk=lambda{|s|keywords+=s.keys;(s['properties']||{}).each_value{|v|schema_walk.call(v)};schema_walk.call(s['items']) if s['items']};schema_walk.call(b.dig('generationConfig','responseFormat','text','schema'))
known=%w[type properties required additionalProperties enum items minItems maxItems minimum maximum]
audit={endpoint:binding['endpoint'],model:binding['model'],reconstructedRequestSHA256:Digest::SHA256.hexdigest(raw),matchesConsumedBinding:true,wireCaptureAvailable:false,fieldPaths:paths,nullPaths:nulls,emptyPaths:empty,schemaKeywords:keywords.uniq.sort,unlistedSchemaKeywords:keywords.uniq-known,unknownRequestFields:[],image:{mime:blob['mimeType'],bytes:bytes.bytesize,signature:bytes[0,3].unpack1('H*'),endSignature:bytes[-2,2].unpack1('H*'),width:1200,height:1500,strictBase64:true,dataURLPrefix:false,sha256:Digest::SHA256.hexdigest(bytes)},maxOutputTokens:4096,documentedModelOutputLimit:65536,budgetFieldsInRequest:false,localContractValid:AnalysisGCEnumCandidate.contract(b),newModelCalls:0}
File.write(out+'/failed-request-contract.json',JSON.pretty_generate(audit))
minimal={'contents'=>[{'role'=>'user','parts'=>[{'text'=>'Describe the visible scene in one short sentence. If unclear, say uncertain. Do not infer product claims. Return JSON with scene only.'},{'inlineData'=>blob}]}],'generationConfig'=>{'maxOutputTokens'=>512,'thinkingConfig'=>{'thinkingLevel'=>'MINIMAL'},'responseFormat'=>{'text'=>{'mimeType'=>'APPLICATION_JSON','schema'=>{'type'=>'object','properties'=>{'scene'=>{'type'=>'string'}},'required'=>['scene']}}}}}
minraw=JSON.generate(minimal);raise unless VisualAnalysis.parse_json(minraw)==minimal&&Base64.strict_decode64(minimal['contents'][0]['parts'][1]['inlineData']['data'])==bytes
min_schema=minimal.dig('generationConfig','responseFormat','text','schema')
raise unless min_schema['required']==min_schema['properties'].keys&&min_schema['properties']['scene']['type']=='string'
File.write(out+'/minimal-candidate-local.json',JSON.pretty_generate({body:minimal,requestHash:Digest::SHA256.hexdigest(minraw),authorized:false,liveEnabled:false,diagnosticOnly:true,productionAnalysisCompatible:false}))
redacted=JSON.parse(JSON.generate(minimal));redacted['contents'][0]['parts'][1]['inlineData']['data']='[REMOVED: unchanged original JPEG]'
File.write(out+'/minimal-candidate-redacted.json',JSON.pretty_generate({request:redacted,requestHash:Digest::SHA256.hexdigest(minraw),changes:['prompt replaced with one-scene diagnostic','full business schema replaced with one required string','candidateCount omitted (documented default 1)','mediaResolution omitted (provider default)','maxOutputTokens reduced 4096 to512'],unchanged:['endpoint','model','original JPEG bytes','MINIMAL','APPLICATION_JSON'],authorized:false,liveEnabled:false,diagnosticOnly:true,productionAnalysisCompatible:false}))
a=JSON.parse(File.read(r+'/analysis-cache/'+AnalysisGCAdapter::SOURCE+'.json'));raise unless a['origin']=='manual'
VisualAnalysis.validate(a,AnalysisGCAdapter::SOURCE,1200,1500)
compiled=[]
%w[remove-all-copy ai-rewrite custom].product(%w[keep-reference auto-layout]).each do |mode,layout|
 options={'businessSpec'=>BusinessRules::CURRENT,'mode'=>mode,'layoutMode'=>layout,'layoutTone'=>'keep-reference','output'=>{'aspectRatio'=>'12:15','imageSize'=>'2K'}};options['customCopy']='Weather scenes' if mode=='custom'
 plan=GenericGCPlan.prepare(bytes,a,options);GenericGCPlan.validate(plan)
 prompt=JSON.parse(plan['body'])['contents'][0]['parts'][0]['text']
 compiled<<{origin:'manual',mode:mode,layout:layout,requestHash:plan['binding']['requestHash'],prompt:prompt,ruleBindings:plan['trace']['ruleBindings'],visualAcceptance:'not-evaluated',sent:false}
end
File.write(out+'/manual-compilation.json',JSON.pretty_generate({sourceHash:AnalysisGCAdapter::SOURCE,analysisOrigin:'manual',automaticAnalysisSucceeded:false,sourceWarnings:a['uncertainties'],cases:compiled}))
svg=a['regions'].map{|x|box=x['box'];"<rect x='#{box[0]}' y='#{box[1]}' width='#{box[2]}' height='#{box[3]}' fill='none' stroke='#ff6600' stroke-width='4'/><text x='#{box[0]+8}' y='#{box[1]+24}' fill='#ff6600' font-size='24'>#{CGI.escapeHTML(x['id'])}</text>"}.join
html="<!doctype html><meta charset='utf-8'><title>人工结构化记录 · 本地规则预览</title><style>body{font:16px system-ui;max-width:1100px;margin:32px auto;padding:16px}pre{white-space:pre-wrap;background:#f4f4f4;padding:16px}.image{position:relative;width:480px}.image img{width:100%}.image svg{position:absolute;inset:0;width:100%;height:100%}</style><h1>人工结构化记录 · 仅本地规则预览</h1><p>不是自动分析成功，不是新生成结果。框线来自既有人工估计；字体与坐标仍需复核。不能用于产品替换目标。</p><div class='image'><img src='../../assets/81gMZuoRq6L._AC_SL1500_.jpg' alt='既有原始参考图'><svg viewBox='0 0 1200 1500'>#{svg}</svg></div>"
compiled.each{|x|html+="<details><summary>#{CGI.escapeHTML(x[:mode]+' / '+x[:layout])} — 未发送</summary><p>请求SHA256 #{x[:requestHash]}</p><pre>#{CGI.escapeHTML(x[:prompt])}</pre></details>"}
File.write(out+'/manual-preview.html',html)
puts JSON.generate({requestHash:audit[:reconstructedRequestSHA256],paths:paths.size,nulls:nulls.size,empty:empty.size,schemaKeywords:keywords.uniq.sort,imageBytes:bytes.bytesize,minimalCandidateHash:Digest::SHA256.hexdigest(minraw),manualCompiledCases:compiled.size,newModelCalls:0})
