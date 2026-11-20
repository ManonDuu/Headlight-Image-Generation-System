# Automatic asset proposal adapter. Offline preparation/parsing; live gates stay closed.
require_relative 'direct-image-plan'
require_relative 'generate-content-adapter'
require_relative 'live-request-pause'
require_relative 'copy-evidence-policy'
require_relative 'analysis-output-contract'
require_relative 'preserve-reference-copy'
require_relative 'reference-anchor-review'
require_relative 'background-scene-contract'
require_relative 'source-structure'
module ReferenceProvider
 VERSION='reference-assets-20261018.7-scene-only'
 LAYOUT_VERSION='reference-layout-px-1'
 ANALYSIS_MODEL='gemini-3.5-flash-lite'
 def self.need(v,m);raise ArgumentError,m unless v;end
 def self.hash(v);Digest::SHA256.hexdigest(JSON.generate(v));end
 def self.schema
  number={'type'=>'number'};string={'type'=>'string'}
  fields={'text'=>string,'role'=>{'type'=>'string','enum'=>%w[title subtitle body brand],'description'=>'Canonical final render role. Preserve original badge/label role only in evidence marketingFunction.'},'fontSize'=>{'type'=>'number','description'=>'Font size in absolute output pixels, greater than zero and at most 512.'},'weight'=>{'type'=>'number','description'=>'Unitless Inter font weight, 100 through 900.'},'style'=>{'type'=>'string','enum'=>%w[normal italic]},'lineHeightPx'=>{'type'=>'number','description'=>'Absolute baseline-to-baseline distance in output pixels. Never a multiplier; e.g. 86.4 pixels for 72px font with 1.2 spacing.'},'align'=>{'type'=>'string','enum'=>%w[left center right]},'color'=>string,'box'=>{'type'=>'object','properties'=>%w[x y width height].map{|k|[k,{'type'=>'number','description'=>k+' in absolute native output pixels; origin is top-left.'}]}.to_h,'required'=>%w[x y width height]}}
  {'type'=>'object','properties'=>{'sourceStructure'=>SourceStructure.schema,'sourceGeometry'=>{'type'=>'object','properties'=>{'width'=>{'type'=>'integer'},'height'=>{'type'=>'integer'},'coordinateSpace'=>{'type'=>'string','enum'=>['source-pixels']}},'required'=>%w[width height coordinateSpace]},'evidence'=>CopyEvidencePolicy.schema,'layoutVersion'=>{'type'=>'string','description'=>LAYOUT_VERSION},'text'=>{'type'=>'array','description'=>'Final eligible copy with every source role accounted for. Resolve unsupported tokens individually; never silently delete a whole title, subtitle, specification line or label. Keep unresolved evidence explicit for host review.','items'=>{'type'=>'object','properties'=>fields,'required'=>fields.keys}}},'required'=>['layoutVersion','sourceGeometry','text','evidence','sourceStructure']}
 end
 def self.layout(value,frozen)
  need(value.is_a?(Hash)&&(value.keys-%w[layoutVersion text evidence sourceGeometry]).empty?&&value.key?('layoutVersion')&&value.key?('text')&&value['layoutVersion']==LAYOUT_VERSION&&value['text'].is_a?(Array)&&value['text'].size<=24,'invalid layout root/count')
  mode=frozen['options']['mode'];w,h=frozen['trace']['expectedDimensions']
  result=Marshal.load(Marshal.dump(value))
  result['text'].each do |t|
   need((t.keys-['presentation']).sort==schema['properties']['text']['items']['required'].sort,'layout fields changed')
   need(t['text'].is_a?(String)&&t['text'].bytesize<=3000&&!t['text'].match?(SharedTypography::FORBIDDEN),'invalid/forbidden copy')
   need(%w[title subtitle body brand].include?(t['role'])&&%w[normal italic].include?(t['style'])&&%w[left center right].include?(t['align']),'invalid layout enum')
   need(t['color'].is_a?(String)&&t['color'].match?(/\A#[0-9a-fA-F]{6}\z/),'invalid text color')
   need(%w[fontSize weight lineHeightPx].all?{|k|t[k].is_a?(Numeric)&&t[k].finite?}&&t['fontSize']>0&&t['fontSize']<=512&&t['weight'].between?(100,900)&&t['lineHeightPx']>0,'invalid font metrics')
   b=t['box'];need(b.is_a?(Hash)&&b.keys.sort==%w[height width x y]&&b.values.all?{|v|v.is_a?(Numeric)&&v.finite?}&&b['x']>=0&&b['y']>=0&&b['width']>0&&b['height']>0&&b['x']+b['width']<=w&&b['y']+b['height']<=h,'layout outside native output')
   # Normalize subpixel precision for identical Ruby/browser JSON fingerprints.
   [t,b].each do |fields|
    fields.each{|k,v|if v.is_a?(Numeric);n=v.round(3);fields[k]=n==n.to_i ? n.to_i : n;end}
   end
   need(t['fontSize']>0&&t['lineHeightPx']>0&&b['width']>0&&b['height']>0&&b['x']+b['width']<=w&&b['y']+b['height']<=h,'rounded geometry invalid')
   t['mode']=mode
  end
  need(result['text'].empty?,'no-copy has text') if mode=='remove-all-copy'
  need(result['text'].map{|t|t['text']}.join==frozen['options']['customCopy'],'custom copy altered') if mode=='custom'
  omissions=result.dig('evidence','rewrites')
  all_omitted=omissions.is_a?(Array)&&!omissions.empty?&&omissions.all?{|rw|rw['action']=='omit'&&!rw['omissionReason'].to_s.empty?}
  need(!result['text'].empty?||all_omitted,'missing rewritten copy') if mode=='ai-rewrite'
  result
 end
 def self.prepare(frozen,stage,layout_result=nil)
  DirectImagePlan.validate(frozen);need(frozen['binding']['module']=='reference-reconstruction','first module only');need(%w[layout-copy background].include?(stage),'unknown asset stage')
  image=DirectImagePlan.image_part(frozen,'reference');source_dimensions=InputImage.inspect(Base64.strict_decode64(image['data']))['dimensions'];mode=frozen['options']['mode']
  if stage=='layout-copy'
   need(layout_result.nil?,'analysis must not borrow prior geometry');model=ANALYSIS_MODEL;budget=20000;reserve=16384;estimate=15156
   instruction="Return sourceStructure as original-source observations: visible physical product bounds excluding transparent padding; every source block in one text group with source-pixel bounds, convex perspective quad, italic/weight/palette/color; all actual panels and label rectangles. Each text group must declare owner=canvas or a panel id, and placement=free/header/label/detail. Panel labels must have matching owner and placement=label; supplementary panel claims use detail. These observations determine local text ownership; do not leave blank decorative labels or place a panel label over scene evidence. Empty panels means truly unframed. productVisibleBounds is zero rect only when productPresent=false. Do not invent missing source evidence. SOURCE IMAGE: #{source_dimensions[0]}x#{source_dimensions[1]} pixels. sourceGeometry must report those exact dimensions and coordinateSpace=source-pixels. OUTPUT CANVAS: #{frozen['trace']['expectedDimensions'].join('x')} pixels; this separate space is used only by text[].box. First record source observations exclusively in evidence.sourceBlocks/facts. Then produce FINAL eligible copy in text[]; never copy the evidence inventory into the rendering list. Canonical role is title/subtitle/body/brand only; origin is reference/user only. Preserve all source evidence even when omitted from final copy. Each rewrite declares action render or omit, renderIndex (zero-based index in text[], -1 for omission) and omissionReason. Omitting unconfirmed claims is allowed and does not require preserving the omitted claim as marketing meaning; preserve the eligible remaining selling intent. Analyze the reference and produce only the requested JSON text layout for native output #{frozen['trace']['expectedDimensions'].join('x')}. Infer actual roles and coordinates; never ask the user to enter coordinates. Obey selected layout mode. layoutVersion must be reference-layout-px-1. box x/y/width/height and fontSize are absolute output pixels; lineHeightPx is an absolute pixel baseline distance, NEVER a multiplier. weight is a unitless 100-900 weight. Reference-visible glyph height and title/subtitle group proportions take priority over guessed font size or bounding-box height. Host measurement of visible glyphs is required before final layout; do not claim a default small font preserves reference proportions. Boxes use absolute output pixels. Supply Inter normal/italic, weight, size, line height, alignment and hex color. Rewrite marketing text only in ai-rewrite, preserving factual limits. preserve-reference must copy original source wording and case into evidence/source text without rewriting; host applies disclosed brand and parameter handling. custom must concatenate exactly to supplied customCopy; remove-all-copy returns empty text. Do not invent numeric facts/brands. Preserve source core intent, each semantic role and marketing function. AI rewrite applies to the whole image copy collection: most original sentences may remain unchanged; a small whole-image difference suffices, including required removal of a source brand or unsupported numeric claim; unchanged remaining sentences are allowed. Never require each block to differ or a lexical-difference percentage. Case/wrapping/punctuation alone do not count. custom is verbatim and exempt. Each sourceBlocks entry must preserve original sourceText with explicit line breaks and sourceBox in ORIGINAL source-image pixels, not output pixels. These boxes only locate local segmentation; never claim their height is glyph height. Separate reference-only facts, explicitly supplied user facts, and safely paraphrasable qualitative meaning in evidence. Remove only unsupported brand/numeric/classification claims, never replace the whole message with empty neutral labels. Report unresolved fact conflicts for confirmation; do not invent performance claims or call source facts user-confirmed. Stage-specific clarification: for this local candidate workflow, required brand/parameter removal counts as whole-image difference; source-backed LED/Halogen category labels are permitted. This clarification overrides stricter generic wording in the frozen shared policies without rewriting the historical freeze. Supplied options: #{JSON.generate(frozen['options'])}. Shared policies: #{JSON.generate(frozen['trace']['ruleBindings'])}"
   config={'candidateCount'=>1,'maxOutputTokens'=>4096,'thinkingConfig'=>{'thinkingLevel'=>'MINIMAL'},'responseFormat'=>{'text'=>{'mimeType'=>'APPLICATION_JSON','schema'=>schema}}}
  else
   need(layout_result.is_a?(Hash),'validated layout required before background');# Scene-only generation does not consume glyph anchors; final composition keeps its independent geometry gate.
   raw_layout=Marshal.load(Marshal.dump(layout_result));raw_layout.fetch('text').each{|t|t.delete('mode')};validated=layout(raw_layout,frozen);need(validated==layout_result,'layout mode binding changed')
   AnalysisOutputContract.validate_render!(layout_result['text'],frozen['options'])
   model=GenerateContentAdapter::MODEL;budget=260000;reserve=25600;estimate=258560
   instruction=BackgroundSceneContract.compile(frozen,layout_result)['instruction']
   config={'candidateCount'=>1,'maxOutputTokens'=>4096,'thinkingConfig'=>{'thinkingLevel'=>'MINIMAL'},'responseModalities'=>['IMAGE'],'imageConfig'=>frozen['trace']['output']}
  end
  need(instruction.bytesize<=24000,'prompt too large; no silent truncation')
  body=JSON.generate({'contents'=>[{'role'=>'user','parts'=>[{'text'=>instruction},{'inlineData'=>image}]}],'generationConfig'=>config})
  binding={'version'=>VERSION,'stage'=>stage,'model'=>model,'endpoint'=>"https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent",'sourceHash'=>frozen['binding']['sourceHash'],'frozenRequestHash'=>frozen['binding']['requestHash'],'layoutHash'=>layout_result&&hash(layout_result),'requestHash'=>Digest::SHA256.hexdigest(body),'budgetMicroUSD'=>budget,'conservativeMicroUSD'=>estimate,'inputTokenReserve'=>reserve,'maxOutputTokens'=>4096,'maxRequests'=>1,'retries'=>0}
  {'body'=>body,'binding'=>binding,'frozen'=>frozen,'layout'=>layout_result,'sceneInputContract'=>stage=='background' ? BackgroundSceneContract.compile(frozen,layout_result)['contract'] : nil,'liveEnabled'=>false}
 end
 def self.analysis_envelope(http,raw)
  need(http==200,"HTTP #{http}; stop, no retry")
  need(raw.bytesize<=1048576,'analysis response too large');r=JSON.parse(raw);need(r.is_a?(Hash),'analysis envelope must be an object');need(!r['error']&&!r.dig('promptFeedback','blockReason'),'provider blocked')
  need(r['modelVersion'].is_a?(String)&&(r['modelVersion']==ANALYSIS_MODEL||r['modelVersion'].start_with?(ANALYSIS_MODEL+'-')),'wrong model')
  cs=r['candidates'];need(cs.is_a?(Array)&&cs.size==1&&cs[0].is_a?(Hash),'multiple/missing analysis candidates')
  finish=cs[0]['finishReason'];need(finish=='STOP',finish=='MAX_TOKENS' ? 'Analysis output truncated (MAX_TOKENS); no composition, no retry. 分析输出达到上限，已停止，未生成场景。' : "incomplete analysis (#{finish}); stop, no retry")
  parts=cs[0].dig('content','parts');need(parts.is_a?(Array)&&parts.all?{|p|p.is_a?(Hash)&&p['text'].is_a?(String)&&(p.keys-%w[text thought thoughtSignature]).empty?},'non-text analysis')
  final=parts.reject{|p|p['thought']};need(final.size==1,'ambiguous final analysis')
  u=r['usageMetadata'];need(u.is_a?(Hash)&&%w[promptTokenCount candidatesTokenCount totalTokenCount].all?{|k|u[k].is_a?(Integer)&&u[k]>=0},'usage missing');thoughts=u.fetch('thoughtsTokenCount',0)
  need(thoughts.is_a?(Integer)&&thoughts>=0&&u.fetch('toolUsePromptTokenCount',0)==0&&u['totalTokenCount']==u['promptTokenCount']+u['candidatesTokenCount']+thoughts&&u['promptTokenCount']<=16384&&u['candidatesTokenCount']+thoughts<=4096,'usage outside reserve')
  [r,final[0],u]
 rescue JSON::ParserError
  raise ArgumentError,'Analysis response envelope is invalid JSON; no composition, no retry.'
 end
 def self.decode_analysis(part)
  value=JSON.parse(part.fetch('text'));need(value.is_a?(Hash),'analysis JSON root must be an object');value
 rescue JSON::ParserError
  raise ArgumentError,'Analysis returned invalid JSON despite STOP; no composition, no retry.'
 end
 def self.parse(plan,http,raw)
  b=plan['binding'];need(http==200,"HTTP #{http}; stop, no retry")
  if b['stage']=='background'
   out=GenerateContentAdapter.parse(http,raw,expected_dimensions:plan['frozen']['trace']['expectedDimensions']);return {'sceneCandidate'=>{'base64'=>Base64.strict_encode64(out['bytes']),'mime'=>out['outputMime'],'sha256'=>out['outputHash'],'dimensions'=>plan['frozen']['trace']['expectedDimensions']},'sceneInputContract'=>plan['sceneInputContract'],'plan'=>plan['layout'],'usage'=>out['usage'],'reviewRequired'=>true,'compositionAllowed'=>false,'localDecorationRequired'=>true}
  end
  r,part,u=analysis_envelope(http,raw)
  decoded=decode_analysis(part);structure=decoded.delete('sourceStructure');contract=nil;association_audit=nil
  if plan['frozen']['options']['mode']=='ai-rewrite'
   source=InputImage.inspect(Base64.strict_decode64(DirectImagePlan.image_part(plan['frozen'],'reference')['data']))['dimensions']
   contract=AnalysisOutputContract.process(decoded,plan['frozen']['options'],source,plan['frozen']['trace']['expectedDimensions'])
   association_audit=contract['associationAudit']
   return {'contractAudit'=>contract,'usage'=>u,'reviewRequired'=>true,'compositionAllowed'=>false} if contract['state']=='awaiting-contract-review'
   decoded=contract['candidate']
  end
  if %w[ai-rewrite preserve-reference].include?(plan['frozen']['options']['mode'])
   completeness=CopyElementResolution.process(decoded,plan['frozen']['options'],plan['frozen']['trace']['expectedDimensions'],source_structure:structure,input_context:plan['frozen']['inputProvenance'])
   completeness['associationAudit']=association_audit if association_audit
   return {'contractAudit'=>completeness,'usage'=>u,'reviewRequired'=>true,'compositionAllowed'=>false} unless completeness['pending'].empty?
   decoded=completeness['candidate'];contract=completeness
  end
  normalized=layout(decoded,plan['frozen']);audit=plan['frozen']['options']['mode']=='preserve-reference' ? {'state'=>'preserved-with-disclosed-fact-policy','changes'=>contract['changes']} : CopyEvidencePolicy.audit(decoded['evidence'],plan['frozen']['options'],normalized['text']);{'plan'=>normalized,'semanticAudit'=>audit,'contractAudit'=>contract,'copyDecisions'=>contract&&contract['decisions'],'sourceStructure'=>structure,'usage'=>u,'reviewRequired'=>true}
 end
 def self.read_cached(plan,root,mock:false)
  folder=File.join(root,mock ? 'mock-reference-assets' : 'live-reference-assets',plan['binding']['requestHash'])
  path=File.join(folder,'result.json');need(File.file?(path),'prior attempt interrupted; remote outcome unknown; no retry')
  result=JSON.parse(File.read(path));need(result['resultHash']==hash(result.reject{|k,_|k=='resultHash'})&&result['binding']==plan['binding'],'cache corrupt/binding mismatch; no retry');result.merge('cacheHit'=>true)
 end
 def self.execute(plan,root,approval:,transport:,mock:false,authorized_once:false)
  need(prepare(plan['frozen'],plan.dig('binding','stage'),plan['layout'])==plan,'provider frozen plan changed')
  b=plan['binding'];need(approval==b,'exact new step approval required')
  unless mock;LiveRequestPause.check!;need(authorized_once,'live step disabled; fresh approval required');end
  folder=File.join(root,mock ? 'mock-reference-assets' : 'live-reference-assets',b['requestHash']);FileUtils.mkdir_p(File.dirname(folder),mode:0700)
  if File.directory?(folder)
   return read_cached(plan,root,mock:mock)
  end
  begin;Dir.mkdir(folder,0700);rescue Errno::EEXIST;raise 'concurrent attempt; no retry';end
  File.write(File.join(folder,'binding.json'),JSON.pretty_generate(b))
  begin
   http,raw=transport.call(b['endpoint'],plan['body'],{retries:0,timeoutSeconds:b['stage']=='background' ? 180 : 120});File.binwrite(File.join(folder,'response.raw.json'),raw)
   result={'state'=>'provider-proposal','stage'=>b['stage'],'binding'=>b,'mock'=>mock,'payload'=>parse(plan,http,raw),'automaticAcceptance'=>false}
  rescue=>e
   result={'state'=>'stopped','stage'=>b['stage'],'binding'=>b,'mock'=>mock,'error'=>e.message,'remoteBilling'=>'unknown','retries'=>0}
  end
  result['resultHash']=hash(result);File.write(File.join(folder,'result.json.tmp'),JSON.pretty_generate(result));File.rename(File.join(folder,'result.json.tmp'),File.join(folder,'result.json'));result
 end
 def self.propose(frozen,root,approval_for:,transport_for:,mock:false,authorized_once:false)
  first=prepare(frozen,'layout-copy')
  approval=approval_for.call(first['binding']);need(approval==first['binding'],'fresh analysis approval required before transport setup')
  a=execute(first,root,approval:approval,transport:transport_for.call('layout-copy'),mock:mock,authorized_once:authorized_once)
  return {'state'=>'stopped','failedStage'=>'layout-copy','steps'=>[a]} unless a['state']=='provider-proposal'
  return {'state'=>'awaiting-contract-review','steps'=>[a],'contractAudit'=>a['payload']['contractAudit'],'backgroundCalls'=>0} if a.dig('payload','contractAudit','state')=='awaiting-contract-review'
  return {'state'=>'awaiting-meaning-review','steps'=>[a],'semanticAudit'=>a['payload']['semanticAudit'],'backgroundCalls'=>0} if %w[awaiting-meaning-review candidate-with-warnings].include?(a.dig('payload','semanticAudit','state'))
  return {'state'=>'awaiting-copy-resolution','steps'=>[a],'contractAudit'=>a['payload']['contractAudit'],'backgroundCalls'=>0,'compositionAllowed'=>false} unless a.dig('payload','plan')
  second=prepare(frozen,'background',a['payload']['plan'])
  approval=approval_for.call(second['binding']);need(approval==second['binding'],'fresh background approval required before transport setup')
  b=execute(second,root,approval:approval,transport:transport_for.call('background'),mock:mock,authorized_once:authorized_once)
  return {'state'=>'stopped','failedStage'=>'background','steps'=>[a,b]} unless b['state']=='provider-proposal'
  {'state'=>'scene-candidate-awaiting-local-decoration','steps'=>[a,b],'sceneIntake'=>b['payload'].merge('copyDecisions'=>a['payload']['copyDecisions'],'sourceHash'=>frozen['binding']['sourceHash'],'planHash'=>hash(b['payload']['plan'])),'automaticAcceptance'=>false,'compositionAllowed'=>false,'mock'=>mock}
 end
 def self.propose_live(frozen,root,approval_for:,key_for:,authorized_once:false)
  LiveRequestPause.check!;need(authorized_once,'live pipeline not authorized')
  require_relative 'analysis-gc-transport'
  require_relative 'generate-content-transport'
  factory=lambda do |stage|
   klass=stage=='layout-copy' ? AnalysisGCTransport : GenerateContentTransport
   klass.new(key_for.call(stage),authorized_once:true)
  end
  propose(frozen,root,approval_for:approval_for,transport_for:factory,mock:false,authorized_once:true)
 end
end
