require 'json'
require 'digest'
module RulesCompiler
  VERSION='recovered-approved-core-20261017.5'
  SOURCE='approved-rules.txt'
  MAX_PROMPT_BYTES=8192
  INPUT_TOKEN_ALLOWANCE=25600 # 8192 text-byte reserve + 16384 image-token reserve + 1024 framing reserve; estimate, not provider cap
  SIZES={'1:1'=>[2048,2048],'4:5'=>[1856,2304],'5:4'=>[2304,1856],'3:4'=>[1792,2400],'4:3'=>[2400,1792],'9:16'=>[1536,2752],'16:9'=>[2752,1536],'2:3'=>[1696,2528],'3:2'=>[2528,1696]}.freeze
  RULES=[
    ['structure','Preserve composition, viewpoint, subject category, partitions, reading order, focal hierarchy, region functions and original overall color tone.','Compare reference and output at reduced size; verify region roles and viewpoint.'],
    ['visual-reference','Use the attached original as visual evidence; never redraw from text alone.','Verify request contains the hashed original and compare its evidence with output.'],
    ['layout-freeze','Keep frozen region and label positions; never arbitrarily move them.','Compare output geometry to frozen input; record deviations.'],
    ['scene-difference','Change concrete same-type scene details visibly at first glance, not a few stones or leaves. Do not remake the topic.','Side-by-side comparison must show obvious concrete scene/object differences.'],
    ['role-boundary','Never force subject or camera changes for originality. Weather carriers may vary; installation/fit/structure categories must remain. If subject cannot change, reconstruct environment/materials.','Verify changes respect each subject role and relevant category.'],
    ['proof','Preserve selling-point relationships, weather, light direction/range and contrast conditions. Paired comparisons must use the same new scene.','Inspect proof relationships and paired comparison consistency.'],
    ['typography','Preserve font appearance, weight, spacing, hierarchy and placement. Ordinary text uses one fixed visually matching font; perspective text retains angle/weight/perspective.','Compare typography and perspective to reference; exact font identity remains separately unverified.'],
    ['readability','Only minimal fixes for tiny/low-contrast text. Stop if a major layout change is needed.','Record necessary minimal fixes; reject substantial layout changes.'],
    ['brightness','No post-brightening rescue, invented beams, invented advantage or subjective label moves. Bad brightness/proof fails.','Inspect raw image lighting, beams and proof; reject altered comparisons.'],
    ['joint-acceptance','Require BOTH structural/selling-point similarity and obvious scene difference. No invented similarity percentages.','Both independent visual criteria must pass; software tests are not image acceptance.']
  ].freeze
  class Invalid < StandardError;end
  def self.need(ok,msg);raise Invalid,msg unless ok;end
  def self.compile(d,source_hash)
    need(!d.key?('prompt'),'client prompt rejected; structured options and analysis required')
    need(d['output'].is_a?(Hash),'explicit output choice required; historical default not assumed')
    output=d['output'].dup
    if output['aspectRatio']=='custom'
      ratio=SIZES.find{|_,dims|dims==[output['width'],output['height']]}
      need(ratio,'custom dimensions are not native 2K dimensions; no silent crop/resize');output['aspectRatio']=ratio[0]
    end
    need(SIZES.key?(output['aspectRatio'])&&output['imageSize']=='2K','unsupported output choice; no fallback')
    need(d['layoutTone']=='keep-reference','layout/tone option mapping not recovered; do not invent a style')
    mode=d['mode'];need(%w[keep-layout no-copy custom ai-rewrite].include?(mode),'unknown copy mode')
    need(mode=='custom'||!d.key?('customCopy'),'custom copy conflicts with selected mode')
    custom=d['customCopy'];need(mode!='custom'||(custom.is_a?(String)&&!custom.strip.empty?),'custom mode requires exact copy')
    a=d['analysis'];need(a.is_a?(Hash),'per-image structured analysis required; no sample fallback')
    need(a['sourceHash']==source_hash,'analysis belongs to another reference')
    need(a['rulesVersion']==VERSION,'analysis rules version mismatch')
    need(a['readingOrder'].is_a?(Array)&&a['proof'].is_a?(Array)&&!a['proof'].empty?&&a['mutableScene'].is_a?(Array)&&!a['mutableScene'].empty?,'visual evidence inventory missing')
    need(a['uncertainties'].is_a?(Array)&&a['uncertainties'].none?{|u|u['severity']=='blocking'},'blocking or missing uncertainty inventory')
    need(a['labels'].is_a?(Array)&&a['labels'].all?{|l|l['certainty']=='certain'},'uncertain text cannot be compiled')

    need(a['width'].is_a?(Integer)&&a['height'].is_a?(Integer)&&a['width']>0&&a['height']>0,'analysis dimensions missing')
    need(%w[manual model mock].include?(a['origin']),'analysis provenance required')
    need(a['regions'].is_a?(Array)&&a['regions'].size.between?(1,30),'regions required')
    ids=[]
    a['regions'].each do |r|
      need(r.is_a?(Hash)&&r['id'].is_a?(String)&&!r['id'].empty?&&!ids.include?(r['id']),'unique region ID required');ids<<r['id']
      need(%w[weather-carrier installation fit structure comparison scene].include?(r['role']),'region role required')
      b=r['box'];need(b.is_a?(Array)&&b.size==4&&b.all?{|v|v.is_a?(Numeric)&&v.finite?}&&b[0]>=0&&b[1]>=0&&b[2]>0&&b[3]>0&&b[0]+b[2]<=a['width']&&b[1]+b[3]<=a['height'],'invalid region geometry')
    end
    need(a['labels'].is_a?(Array),'label inventory required, even when empty')
    a['labels'].each do |l|
      need(l.is_a?(Hash)&&l['text'].is_a?(String)&&!l['text'].empty?&&%w[marketing functional].include?(l['role'])&&ids.include?(l['region']),'invalid label inventory')
    end
    need(a['comparisons'].is_a?(Array),'comparison inventory required, even when empty')
    a['comparisons'].each{|pair|need(pair.is_a?(Array)&&pair.size>=2&&pair.all?{|id|ids.include?(id)},'invalid comparison mapping')}
    need(a['regions'].none?{|r|r['role']=='comparison'}||!a['comparisons'].empty?,'comparison regions need paired conditions')
    need(d['sceneChange'].is_a?(String)&&!d['sceneChange'].strip.empty?,'concrete scene change plan required')
    need(a['fontPlan'].is_a?(String)&&!a['fontPlan'].strip.empty?,'font plan missing; do not invent exact font identity')
    mode_rule=case mode
    when 'no-copy';['copy-no-marketing','Remove marketing headings/brands/watermarks; retain verified necessary functional labels/scales/axes verbatim including case and explicitly retained H1/HV. Keep the vacated layout space; no reflow.','Check removed marketing and preserved exact functional labels.']
    when 'keep-layout';['copy-keep-layout','Keep reference text content and its layout; do not silently remove or rewrite it.','Compare original text and layout, including functional labels.']
    when 'ai-rewrite';['copy-ai-rewrite','Rewrite marketing prose only, retaining the original capitalization STYLE of each heading/body region (explicit current default, not a recovered historical convention). Preserve every functional label verbatim and every product parameter, number, unit, model identifier, performance and compatibility fact. Keep any label containing digits entirely verbatim. Never add, remove or strengthen product claims; when uncertain retain the original wording. Keep text regions and hierarchy; no reflow.','Review rewritten marketing for unchanged facts and original capitalization style; compare all functional and parameter labels verbatim. Real model compliance is unverified.']
    else;['copy-verbatim','Replace the original marketing copy with the supplied custom copy EXACTLY including case; only necessary line breaks. Do not append the old marketing copy or rewrite the replacement. Retain all verified functional labels verbatim. Keep the original marketing text regions and hierarchy; if the replacement cannot fit with minimal readability changes, do not reflow the whole layout.','Compare every custom character and capitalization, removed original marketing, retained functional labels and text placement.']
    end
    rules=RULES+[mode_rule]
    # Whitelist analysis fields. Untrusted assertions such as verified:true do not
    # become verification evidence or pass any acceptance gate.
    analysis={'sourceHash'=>source_hash,'width'=>a['width'],'height'=>a['height'],'origin'=>a['origin'],'regions'=>a['regions'].map{|r|r.select{|k,_|%w[id role box].include?(k)}},'labels'=>a['labels'].map{|l|l.select{|k,_|%w[text role region box certainty].include?(k)}},'comparisons'=>a['comparisons'],'fontPlan'=>a['fontPlan'],'verification'=>'unverified-candidate','readingOrder'=>a['readingOrder'],'viewpoint'=>a['viewpoint'],'proof'=>a['proof'],'mutableScene'=>a['mutableScene'],'uncertainties'=>a['uncertainties']}
    semantic={'canvas'=>[a['width'],a['height']],'regions'=>analysis['regions'].map{|r|[r['id'],r['role'],r['box']]},'labels'=>analysis['labels'].map{|l|[l['text'],l['role'],l['region'],l['box']]},'order'=>a['readingOrder'],'view'=>a['viewpoint'],'proof'=>a['proof'],'mutable'=>a['mutableScene'],'pairs'=>a['comparisons'],'font'=>a['fontPlan'],'changes'=>d['sceneChange'],'copy'=>mode=='custom' ? custom : nil}
    prompt="Return one 2K #{output['aspectRatio']} JPEG. Rules:\n"+rules.map{|r|r[1]}.join("\n")+"\nCandidate frozen data: regions=[id,role,[x,y,w,h]], labels=[text,role,region,box]; "+JSON.generate(semantic)
    need(prompt.bytesize<=MAX_PROMPT_BYTES,'compiled request exceeds current 8192-byte input allowance; block, do not omit approved rules')
    catalog_hash=Digest::SHA256.hexdigest(JSON.generate(rules))
    trace={'version'=>VERSION,'source'=>SOURCE,'sourceDocumentHash'=>Digest::SHA256.file(File.join(__dir__,SOURCE)).hexdigest,'selectedOptions'=>{'layoutTone'=>d['layoutTone'],'mode'=>mode},'catalogHash'=>catalog_hash,'mode'=>mode,'appliedRuleIds'=>rules.map(&:first),'promptHash'=>Digest::SHA256.hexdigest(prompt),'sourceHash'=>source_hash,'analysis'=>analysis,'checks'=>rules.map{|id,_,criterion|{'ruleId'=>id,'criterion'=>criterion,'status'=>'not-evaluated','automaticVerification'=>false,'evidence'=>[]}},'overall'=>'not-evaluated'}
    trace['inputAccounting']={'maxTextBytes'=>MAX_PROMPT_BYTES,'inputTokenAllowance'=>INPUT_TOKEN_ALLOWANCE,'outputTokenLimit'=>4096,'conservativeMicroUSD'=>258560,'providerDollarCap'=>false};trace['output']=output;trace['expectedDimensions']=SIZES.fetch(output['aspectRatio'])
    trace['selectedOptions']['requestedOutput']=d['output'].dup
    trace['selectedOptions']['customCopy']=custom if mode=='custom'
    trace['compilerRevision']='20261018-options-1'
    if mode=='ai-rewrite'
      trace['compilerRevision']='20261018-ai-default-1'
      trace['copyPolicy']={'default'=>'preserve-original-capitalization-style','historicalConventionRecovered'=>false,'realVerified'=>false,
        'protectedLabels'=>a['labels'].select{|l|l['role']=='functional'||l['text'].match?(/[0-9]/)}.map{|l|l['text']}}
    end
    {'prompt'=>prompt,'trace'=>trace,'output'=>output}
  end
  def self.review(trace,decisions)
    need(decisions.is_a?(Array),'structured per-rule review required; free text cannot pass gates')
    ids=trace['appliedRuleIds'];need(decisions.map{|d|d['ruleId']}.sort==ids.sort,'all and only applied rules must be reviewed once')
    decisions.each do |d|
      need(%w[pass fail unverified].include?(d['verdict']),'invalid gate verdict')
      need(d['note'].is_a?(String)&&!d['note'].strip.empty?,'gate observation required')
      need(d['evidence'].is_a?(Array)&&!d['evidence'].empty?&&d['evidence'].all?{|e|e.is_a?(Hash)&&e['kind']=='visual-observation'&&e['location'].is_a?(String)&&!e['location'].strip.empty?},'located visual observation required')
    end
    # This is an operator assessment record, never automatic/independent proof.
    {'overall'=>decisions.any?{|d|d['verdict']=='fail'} ? 'manual-rejected' : decisions.all?{|d|d['verdict']=='pass'} ? 'manual-passed-not-independently-verified' : 'unverified','automaticVerification'=>false,'decisions'=>decisions}
  end
end
