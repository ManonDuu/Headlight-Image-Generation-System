require_relative 'default-product-facts'
require_relative 'content-selection'
# Source text is evidence; decisions are explicit and never turn one unknown token into a deleted block.
module CopyElementResolution
 def self.process(value,options,dimensions,resolutions:{},source_structure:nil,input_context:nil)
  return ContentSelection.process(value,options,dimensions,resolutions:resolutions,source_structure:source_structure,input_context:input_context) if options['mode']=='ai-rewrite'
  v=Marshal.load(Marshal.dump(value));e=v.fetch('evidence');w,h=dimensions;g=v.fetch('sourceGeometry');texts=[];decisions=[];rewrites=[]
  canbus_required=options['mode']=='ai-rewrite'&&DefaultProductFacts.canbus_ready?(options)
  canbus_existing=v['text'].any?{|t|t['text'].to_s.strip.match?(/\ACAN[ -]?BUS(?:\s+READY|\s+Functionality)?\z/i)}||e['sourceBlocks'].any?{|b|b['sourceText'].match?(DefaultProductFacts::CANBUS)}
  # Reuse an explicitly unsupported numeric feature slot; never invent a location.
  canbus_slots=canbus_required&&!canbus_existing ? e['sourceBlocks'].select{|b|b['sourceText'].strip.match?(/\A\d+(?:\.\d+)?\s*%\z/)&&!options.fetch('productParameters','').include?(b['sourceText'].strip)} : []
  canbus_slot=canbus_slots.size==1 ? canbus_slots.first : nil
  e.fetch('sourceBlocks').each do |b|
   old=e.fetch('rewrites',[]).find{|r|r['blockId']==b['id']};original=old&&old['renderIndex'].is_a?(Integer)&&old['renderIndex']>=0 ? v['text'][old['renderIndex']] : nil
   text=options['mode']=='preserve-reference' ? b['sourceText'] : original&&original['text'];action='retain';reason='Selected source wording';authorization=options['mode']=='preserve-reference' ? 'selected preserve-reference mode' : 'selected AI rewrite and source role retention policy'
   linked_ids=b.fetch('meaningUnitIds',[])+((old||{})['usedFactIds']||[])+((old||{})['omittedFactIds']||[]);linked=e.fetch('facts').select{|f|linked_ids.include?(f['id'])};brand=linked.find{|f|f['kind']=='brand'}
   if brand
    own=options.fetch('brandName','').strip
    descriptor=brand['value'].match(/\b(?:LED|HID|Halogen|CANBUS)(?:\s+Light(?:s)?)?\b/i)&.to_s
    if descriptor&&brand['value'].strip!=descriptor
     text=[own,descriptor].reject(&:empty?).join(' ')
    else;text=(text||b['sourceText']).gsub(/#{Regexp.escape(brand['value'])}/i,own).strip;end
    action=text.empty? ? 'remove' : 'replace';reason='Third-party brand removed without deleting source technology descriptor';authorization='user brand policy'
   end
   # Preserve qualitative wording. A token such as generation is not a reason to delete a subtitle.
   if b['sourceText'].match?(/99\s*%/)&&!options.fetch('productParameters','').include?('99%')
    if DefaultProductFacts.canbus_ready?(options)&&e['sourceBlocks'].any?{|x|x['sourceText'].match?(/CAN[ -]?BUS/i)}
     text="BUILT-IN";action='replace';reason='Remove unsupported percentage, retain confirmed CANBUS function as a complementary built-in feature label';authorization='confirmed CANBUS default and nonnumeric replacement instruction'
    else;text=b['sourceText'];action='pending';reason='Percentage requires evidence, never silently discard role';end
   elsif b['sourceText'].match?(/\d/)&&!b['sourceText'].scan(/\d+(?:\.\d+)?\s*(?:%|[[:alpha:]]+)?/).all?{|n|options.fetch('productParameters','').include?(n.strip)}
    if b['marketingFunction']=='badge' && b['coreIntent'].to_s.match?(/numerical|percentage/i)
     text='';action='remove';reason='Remove unsupported numerical badge together with its dependent qualifier; no standalone performance claim is established';authorization='user parameters only; dependent claim completeness policy'
    elsif options['mode']=='ai-rewrite'&&text&& !text.match?(/\d/) && !text.strip.empty?;action='replace';reason='Retain qualitative source role while removing unsupported numerical claim';authorization='selected AI rewrite and numeric-claim filtering policy';else;clean=b['sourceText'].gsub(/\d+(?:\.\d+)?\s*%/,'').strip;if b['sourceText'].match?(/\d+\s*%/) && !clean.match?(/\d/);text=clean;action=clean.empty? ? 'remove' : 'replace';reason='Remove unsupported percentage token; retain remaining qualitative source wording';authorization='unsupported percentage filtering policy';else;text||=b['sourceText'];action='pending';reason='Resolve numeric elements separately, preserve role';authorization=nil;end;end
   elsif text.nil?||text.strip.empty?
    if action!='remove';text=b['sourceText'];action=text.match?(/\d|headlights?/i) ? 'pending' : 'retain';reason='Restore omitted qualitative source role without inventing wording';authorization=action=='retain' ? 'source qualitative wording retention policy' : nil;end
   end
   if %w[preserve-reference ai-rewrite].include?(options['mode'])&&b['sourceText'].match?(/ensure[\s\S]*compatib|guarantee[\s\S]*compatib/i)&&!options.fetch('productParameters','').include?(b['sourceText'])
    if DefaultProductFacts.canbus_ready?(options)&&e['sourceBlocks'].any?{|x|x['sourceText'].match?(/CAN[ -]?BUS/i)}
     text=b['sourceText'].match?(/99\s*%/) ? "BUILT-IN\nCANBUS Functionality" : 'CANBUS Functionality';action='replace';reason='Explicit dependent-claim exception: preserve built-in feature and function explanation separately when one source block contains both claims';authorization='confirmed CANBUS and explicit complementary explanation instruction'
    else;action='pending';reason='Dependent compatibility guarantee is not established';authorization=nil;end
   end
   # Preserve mode never silently paraphrases unsupported source claims.
   if options['mode']=='preserve-reference'
    unsupported_number=b['sourceText'].match?(/\d/)&&!b['sourceText'].scan(/\d+(?:\.\d+)?\s*(?:%|[[:alpha:]]+)?/).all?{|n|options.fetch('productParameters','').include?(n.strip)}
    unsupported_guarantee=b['sourceText'].match?(/ensure[\s\S]*compatib|guarantee[\s\S]*compatib/i)&&!options.fetch('productParameters','').include?(b['sourceText'])
    if unsupported_number||unsupported_guarantee
     text='';action='remove';reason='Preserve-reference exception: omit unsupported claim block without paraphrasing; disclose omission';authorization='preserve-reference copy policy and supplied parameter authority'
    end
   end
   if %w[ai-rewrite preserve-reference].include?(options['mode'])&&b['sourceText'].match?(DefaultProductFacts::CANBUS)&&options.fetch('productParameters','').match?(DefaultProductFacts::CANBUS)&&!DefaultProductFacts.canbus_ready?(options)
    text='';action='remove';reason='Explicit negative CANBUS input overrides source function claim';authorization='user productParameters override default/reference'
   end
   if canbus_slot&&b['id']!=canbus_slot['id']&&old&&old['action']=='omit'&&old.fetch('omissionReason','').match?(/companion|dependent|qualifier|associated/i)&&old.fetch('omissionReason','').match?(/numeric|percent/i)
    anchor=canbus_slot['sourceBox'];box=b['sourceBox']
    adjoining=box['x']<anchor['x']+anchor['width']&&box['x']+box['width']>anchor['x']&&box['y']>=anchor['y']+anchor['height']&&box['y']-anchor['y']-anchor['height']<=anchor['height']
    if adjoining&&%w[explanation qualifier detail].include?(b['marketingFunction'])
     text='';action='remove';reason='Explicit adjacent numeric-claim qualifier cannot become a claim about replacement CANBUS function';authorization='unsupported dependent-claim filtering and confirmed function only'
    end
   end
   confirmed_fact=nil
   if canbus_slot&&b['id']==canbus_slot['id']
    text=options.fetch('productParameters')[/\bCAN[ -]?BUS(?:\s+READY)?\b/i]
    action='replace';reason='Replace unsupported numeric feature with explicitly confirmed CANBUS function only';authorization='selected AI rewrite and confirmed productParameters; no compatibility rate or guarantee'
    confirmed_fact={'id'=>'confirmed-canbus-'+b['id'],'value'=>text,'origin'=>'user','userField'=>'productParameters','kind'=>'specification'}
    e['facts']<<confirmed_fact unless e['facts'].any?{|f|f['id']==confirmed_fact['id']}
   end
   if (r=resolutions[b['id']]);raise 'resolution evidence missing' unless r['authorization'].is_a?(String)&&!r['authorization'].empty?;text=r.fetch('text');action=r.fetch('action','replace');reason=r.fetch('reason');authorization=r['authorization'];end
   d={'id'=>b['id'],'sourceText'=>b['sourceText'],'action'=>action,'text'=>text,'reason'=>reason,'authorization'=>authorization};d['semanticRoles']=[{'role'=>'feature','text'=>'BUILT-IN'},{'role'=>'explanation','text'=>'CANBUS Functionality'}] if text=="BUILT-IN\nCANBUS Functionality";decisions<<d
   if action=='remove';rewrites<<{'blockId'=>b['id'],'coreIntent'=>b['coreIntent'],'marketingFunction'=>b['marketingFunction'],'action'=>'omit','renderIndex'=>-1,'omissionReason'=>reason,'preservedMeaningUnitIds'=>[],'usedFactIds'=>[],'omittedFactIds'=>linked.map{|f|f['id']}};next;end
   if original;t=Marshal.load(Marshal.dump(original));t.delete('mode')
   else
    b0=b.fetch('sourceBox');scale=[w.to_f/g['width'],h.to_f/g['height']].min;box={'x'=>(w-g['width']*scale)/2+b0['x']*scale,'y'=>(h-g['height']*scale)/2+b0['y']*scale,'width'=>b0['width']*scale,'height'=>b0['height']*scale};size=[box['height']*0.6,200].min
    t={'role'=>%w[title subtitle body brand].include?(b['marketingFunction']) ? b['marketingFunction'] : 'body','fontSize'=>size,'weight'=>700,'style'=>'normal','lineHeightPx'=>size*1.2,'align'=>'left','color'=>'#FFFFFF','box'=>box}
   end
   t['role']='body' if %w[label badge badge-subtitle].include?(b['marketingFunction'])||(brand&&descriptor)
   group=source_structure&&source_structure.fetch('textGroups',[]).find{|a|a['blockIds']==[b['id']]}
   if group
    t['color']=group['color'];t['weight']=group['weight'];t['style']=group['italic'] ? 'italic' : 'normal'
    if source_structure['observationEvidence']
     b0=group['bounds'];scale=[w.to_f/g['width'],h.to_f/g['height']].min
     t['box']={'x'=>(w-g['width']*scale)/2+b0['x']*scale,'y'=>(h-g['height']*scale)/2+b0['y']*scale,'width'=>b0['width']*scale,'height'=>b0['height']*scale}
    end
   end
   t['role']='body' if confirmed_fact
   t['text']=text;d['renderIndex']=texts.size;rewrites<<{'blockId'=>b['id'],'coreIntent'=>b['coreIntent'],'marketingFunction'=>b['marketingFunction'],'action'=>'render','renderIndex'=>texts.size,'omissionReason'=>'','preservedMeaningUnitIds'=>b.fetch('meaningUnitIds',[]),'usedFactIds'=>confirmed_fact ? [confirmed_fact['id']] : (old||{}).fetch('usedFactIds',[]),'omittedFactIds'=>linked.map{|f|f['id']}.reject{|id|(old||{}).fetch('usedFactIds',[]).include?(id)}};texts<<t
  end
  if canbus_required&&!texts.any?{|t|t['text'].match?(DefaultProductFacts::CANBUS)}
   decisions<<{'id'=>'confirmed-canbus-unplaced','sourceText'=>nil,'action'=>'pending','text'=>options.fetch('productParameters')[/\bCAN[ -]?BUS(?:\s+READY)?\b/i],'reason'=>'Confirmed CANBUS fact has no unambiguous source feature slot; do not silently discard it or invent coordinates','authorization'=>'confirmed productParameters'}
  end
  e['rewrites']=rewrites;v['text']=texts;{'candidate'=>v,'decisions'=>decisions,'pending'=>decisions.select{|d|d['action']=='pending'},'changes'=>decisions.reject{|d|d['action']=='retain'},'state'=>decisions.any?{|d|d['action']=='pending'} ? 'awaiting-copy-resolution' : 'element-complete'}
 end
end
