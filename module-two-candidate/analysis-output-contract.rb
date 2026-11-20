# Pure, deterministic post-processing; never fabricates semantic rewrites or coordinate units.
require_relative 'shared-typography'
require_relative 'default-product-facts'
require_relative 'render-association-resolution'
module AnalysisOutputContract
 VERSION='analysis-output-contract-3'
 ROLES=%w[title subtitle body brand].freeze
 CATEGORY_LABEL=/\b(?:LED|Halogen|HID)(?: Light(?:s)?)?\z/i
 ROLE_ALIASES={'label'=>'body','badge'=>'body','badge-subtitle'=>'subtitle'}.freeze
 def self.validate_render!(texts,options)
  texts.each do |t|
   copy=t.fetch('text');raise 'forbidden final wording' if copy.match?(SharedTypography::FORBIDDEN)
   next unless options['mode']=='ai-rewrite'
   if t['role']=='brand'
    own=options.fetch('brandName','').strip
    raise 'unconfirmed final brand' if own.empty?||copy.strip.casecmp(own)!=0
   end
   supplied=options.fetch('productParameters','')
   raise 'unconfirmed final numeric text' if copy.scan(/\d+(?:\.\d+)?\s*(?:%|[[:alpha:]°]+)?/).map(&:strip).any?{|n|!supplied.match?(/(?<![[:alnum:]])#{Regexp.escape(n)}(?![[:alnum:]])/)}
  end
  true
 end
 def self.process(value,options,source_dimensions,output_dimensions)
  association=RenderAssociationResolution.process(value,options,source_dimensions,output_dimensions)
  v=association['candidate'];changes=association['changes'];pending=[];removed=[]
  texts=v.fetch('text');e=v.fetch('evidence',{});blocks=e.fetch('sourceBlocks',[]);facts=e.fetch('facts',[])
  facts.each{|f|if f['origin']=='source';f['origin']='reference';changes<<{'field'=>'fact.origin','id'=>f['id'],'from'=>'source','to'=>'reference','reason'=>'Untrusted source remains untrusted; no authority promotion'};end}
  geometry=v['sourceGeometry'];source_valid=geometry.is_a?(Hash)&&geometry['width']==source_dimensions[0]&&geometry['height']==source_dimensions[1]
  space=geometry&&geometry['coordinateSpace']
  if source_valid&&space=='normalized-0-1'
   blocks.each do |b|
    box=b['sourceBox'];next unless box.is_a?(Hash)
    if box.values_at('x','y','width','height').all?{|n|n.is_a?(Numeric)&&n.finite?&&n.between?(0,1)}&&box['x']+box['width']<=1&&box['y']+box['height']<=1
     %w[x width].each{|k|box[k]*=source_dimensions[0]};%w[y height].each{|k|box[k]*=source_dimensions[1]}
    else
     pending<<{'code'=>'INVALID_NORMALIZED_BOX','blockId'=>b['id']}
    end
   end
   geometry['coordinateSpace']='source-pixels';space='source-pixels';changes<<{'field'=>'sourceBox','reason'=>'Explicit normalized-0-1 units and exact source dimensions','conversion'=>'multiply x/width by source width, y/height by source height'}
  elsif !source_valid||space!='source-pixels'
   pending<<{'code'=>'UNKNOWN_COORDINATE_UNITS','reason'=>'No exact source dimensions/unit declaration; no inferred scaling or clipping'}
  end
  blocks.each do |b|
   box=b['sourceBox'];valid=box.is_a?(Hash)&&%w[x y width height].all?{|k|box[k].is_a?(Numeric)&&box[k].finite?}&&box['x']>=0&&box['y']>=0&&box['width']>0&&box['height']>0&&box['x']+box['width']<=source_dimensions[0]&&box['y']+box['height']<=source_dimensions[1]
   pending<<{'code'=>'SOURCE_BOX_OUTSIDE_IMAGE','blockId'=>b['id']} unless valid
  end
  rendered=[];allowed_indices=[]
  texts.each_with_index do |t,i|
   matches=e.fetch('rewrites',[]).select{|w|w['action']=='render'&&w['renderIndex']==i}
   raise 'ambiguous render association' if matches.size>1
   rw=matches.first||(options['module']=='product-replacement' ? {} : e.fetch('rewrites',[])[i])||{}
   source_block=blocks.find{|b|b['id']==rw['blockId']}
   if options['mode']=='ai-rewrite'&&source_block&&source_block['sourceText'].to_s.strip.match?(/\ACAN[ -]?BUS(?:\s+READY)?\z/i)&&DefaultProductFacts.canbus_ready?(options)
    # Restore only the explicitly confirmed function, never compatibility rates
    # or promises. Reuse the unambiguous existing block and its typography.
    t['text']=source_block['sourceText'].strip
    fact_id='confirmed-canbus-'+source_block['id']
    value=options.fetch('productParameters')[DefaultProductFacts::CANBUS]
    facts<<{'id'=>fact_id,'value'=>value,'origin'=>'user','userField'=>'productParameters','kind'=>'specification'} unless facts.any?{|f|f['id']==fact_id}
    rw['usedFactIds']=[fact_id]
    changes<<{'field'=>'text','index'=>i,'reason'=>'User-confirmed CANBUS function restored from associated source block'}
   end
   original_role=t['role']
   # Retain only a source-backed lighting-category suffix while removing the actual overlay brand.
   source_label_retained=false
   source_label=source_block&&source_block['sourceText'].to_s[CATEGORY_LABEL]
   if options['mode']=='ai-rewrite'&&source_label&&t['text'].to_s.match?(CATEGORY_LABEL)
    if t['text'].strip.casecmp(source_label)==0||original_role=='brand'
     changes<<{'field'=>'source-backed-label','index'=>i,'from'=>t['text'],'to'=>source_label,'reason'=>'Preserve existing category label; remove source brand prefix, no new product claim'} if t['text']!=source_label||original_role=='brand'
     t['text']=source_label;t['role']='body';original_role='body';source_label_retained=true
    end
   end
   source_label_retained=!!source_label_retained
   if ROLE_ALIASES.key?(original_role);t['role']=ROLE_ALIASES[original_role];changes<<{'field'=>'role','index'=>i,'from'=>original_role,'to'=>t['role'],'reason'=>'Rendering-role alias only; semantic/source role remains in evidence'};end
   unless ROLES.include?(t['role']);pending<<{'code'=>'UNKNOWN_ROLE','index'=>i};next;end
   reasons=[];copy=t['text'].to_s
   reasons<<'UNASSOCIATED_RENDER_BLOCK' if options['mode']=='ai-rewrite'&&options['module']=='product-replacement'&&matches.empty?
   reasons<<'EMPTY_RENDER_BLOCK' if options['mode']=='ai-rewrite'&&copy.strip.empty?
   reasons<<'FORBIDDEN_WORD' if copy.match?(SharedTypography::FORBIDDEN)
   mode=options['mode']
   if mode=='ai-rewrite'
    reasons<<'UNCONFIRMED_BRAND_ROLE' if original_role=='brand'&&(options.fetch('brandName','').strip.empty?||copy.strip.casecmp(options.fetch('brandName','').strip)!=0)
    numeric=copy.scan(/\d+(?:\.\d+)?\s*(?:%|[[:alpha:]°]+)?/).map(&:strip)
    supplied=options.fetch('productParameters','')
    reasons<<'UNCONFIRMED_NUMERIC_TEXT' if numeric.any?{|n|!supplied.match?(/(?<![[:alnum:]])#{Regexp.escape(n)}(?![[:alnum:]])/)}
    used=rw.fetch('usedFactIds',[])
    refs=facts.select{|f|used.include?(f['id'])&&f['origin']!='user'}
    if options['module']=='product-replacement'&&!source_label_retained
     # Reference claims describe a different product. Qualitative classification
     # alone does not establish authority to transfer capabilities to this one.
     supplied_fact=facts.any?{|f|used.include?(f['id'])&&f['origin']=='user'&&%w[brandName productParameters].include?(f['userField'])&&options.fetch(f['userField'],'').include?(f['value'].to_s)&&!f['value'].to_s.empty?}
     reasons<<'UNSUPPORTED_REPLACEMENT_CLAIM' unless supplied_fact
    end
    reasons<<'UNCONFIRMED_TYPED_CLAIM' if !source_label_retained&&refs.any?{|f|%w[brand specification certification].include?(f['kind'])}
    pending<<{'code'=>'FACT_REVIEW','index'=>i,'factIds'=>refs.map{|f|f['id']}} if !source_label_retained&&refs.any?{|f|f['kind']!='qualitative'}
   end
   if reasons.any?
    removed<<{'index'=>i,'sourceBlockId'=>source_block&&source_block['id'],'reasons'=>reasons,'text'=>copy}
    pending<<{'code'=>'COPY_REMOVAL_REQUIRES_MEANING_REVIEW','index'=>i,'reason'=>'Unsupported fragment removed, but eligible meaning must still be checked; no placeholder invented'}
   else
    rendered<<t;allowed_indices<<i
   end
  end
  normalize=lambda{|s|s.downcase.scan(/[[:alnum:]]+/).join(' ')}
  unchanged=normalize.call(rendered.map{|t|t['text']}.join(' '))==normalize.call(blocks.map{|b|b['sourceText']}.join(' '))
  pending<<{'code'=>'NATURAL_REWRITE_MISSING','reason'=>'Whole image copy is unchanged; review a small change without requiring every block to differ'} if options['mode']=='ai-rewrite'&&unchanged
  # Rebind source-to-render indices after safe omissions; keep full source observations.
  e.fetch('rewrites',[]).each do |rw|
   next unless rw['action']=='render'
   old=rw['renderIndex'];next unless old.is_a?(Integer)
   if allowed_indices.include?(old);rw['renderIndex']=allowed_indices.index(old)
   else;rw.merge!('action'=>'omit','renderIndex'=>-1,'omissionReason'=>'Removed by deterministic hard-copy policy','usedFactIds'=>[])
   end
  end
  # Final deterministic gate also runs after omissions. No forbidden words or unconfirmed brand-role text can escape.
  raise 'unsafe render output' if rendered.any?{|t|t['text'].match?(SharedTypography::FORBIDDEN)||(options['mode']=='ai-rewrite'&&options.fetch('brandName','').strip.empty?&&t['role']=='brand')}
  validate_render!(rendered,options)
  {'associationAudit'=>association.reject{|k,_|k=='candidate'},'version'=>VERSION,'state'=>pending.any?{|x|%w[UNKNOWN_COORDINATE_UNITS INVALID_NORMALIZED_BOX SOURCE_BOX_OUTSIDE_IMAGE UNKNOWN_ROLE NATURAL_REWRITE_MISSING].include?(x['code'])} ? 'awaiting-contract-review' : 'candidate-with-warnings','candidate'=>v.merge('text'=>rendered),'retainedSourceIndices'=>allowed_indices,'changes'=>changes,'removed'=>removed,'pending'=>pending,'coordinateEvidenceVerified'=>false,'coordinateUnitsAndBoundsVerified'=>source_valid&&space=='source-pixels'&&!pending.any?{|p|p['code'].include?('BOX')},'sourceLocalizationVerified'=>false,'wholeImageNaturalRewriteVerified'=>false,'automaticSemanticAcceptance'=>false}
 end
end
