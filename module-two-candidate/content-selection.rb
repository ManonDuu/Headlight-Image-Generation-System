# Source evidence is immutable. Available facts do not request new display copy.
module ContentSelection
 VERSION='content-selection-2'
 IMPLEMENTATION_REVISION='separated-labels-and-source-roles-1'
 def self.process(value,options,dimensions,resolutions:{},source_structure:nil,input_context:nil)
  options=Marshal.load(Marshal.dump(options))
  unless input_context&&input_context['origin']=='user'
   options['productParameters']='';options['brandName']=''
  end
  v=Marshal.load(Marshal.dump(value));e=v.fetch('evidence');blocks=e.fetch('sourceBlocks');old=e.fetch('rewrites');texts=[];decisions=[];rewrites=[]
  original_texts=Marshal.load(Marshal.dump(v.fetch('text')))
  removed_claims=[]
  blocks.each do |b|
   rw=old.find{|r|r['blockId']==b['id']};ids=b.fetch('meaningUnitIds',[])+Array(rw&&rw['usedFactIds'])+Array(rw&&rw['omittedFactIds']);facts=e['facts'].select{|f|ids.include?(f['id'])};source=b.fetch('sourceText');text=source;reason='Source qualitative wording retained';origin='reference';action='retain'
   g=source_structure&&source_structure['textGroups'].find{|a|a['blockIds']==[b['id']]}
   source_brands=e.fetch('facts').select{|f|f['kind']=='brand'&&!f['value'].to_s.empty?&&source.include?(f['value'])}
   numbers=source.scan(/\d+(?:\.\d+)?\s*(?:%|[[:alpha:]]+)?/)
   unsupported=!numbers.empty?&&!numbers.all?{|n|options.fetch('productParameters','').include?(n.strip)}
   if source.match?(DefaultProductFacts::CANBUS)&&options.fetch('productParameters','').match?(DefaultProductFacts::CANBUS)&&!DefaultProductFacts.canbus_ready?(options)
    text='';reason='Explicit negative user CANBUS input overrides reference function';action='remove'
   elsif unsupported
    text='';reason='Reference numeric claim is not substantiated for this product; omitted without substitute';action='remove';removed_claims<<b
    # Only preserve an explicitly separated nonnumeric panel-label segment.
    # Never extract a qualitative adjective from a numerical claim sentence.
    segments=source.split(/\s*(?:[>›»|•;]+|\n+)\s*/)
    if g&&g['placement']=='label'&&segments.size>1
     eligible=segments.reject{|seg|seg.match?(/\d/)}
     eligible.map! do |seg|
      source_brands.reduce(seg){|a,f|a.gsub(f['value'],options.fetch('brandName','').strip)}.strip
     end
     text=eligible.reject(&:empty?).join(' ');action=text.empty? ? 'remove' : 'replace'
     reason='Separated source label retained; unsupported numeric segments and reference brand removed' unless text.empty?
    end
   elsif source.match?(/ensure[\s\S]*compatib|guarantee[\s\S]*compatib/i)&&!options.fetch('productParameters','').include?(source)
    text='';reason='Unsubstantiated reference guarantee omitted';action='remove';removed_claims<<b
   elsif (brand=facts.find{|f|f['kind']=='brand'})
    own=options.fetch('brandName','').strip;descriptor=brand['value'].match(/\b(?:LED|HID|Halogen|CANBUS)(?:\s+Light(?:s)?)?\b/i)&.to_s
    text=descriptor ? [own,descriptor].reject(&:empty?).join(' ') : source.gsub(brand['value'],own).strip
    action=text.empty? ? 'remove' : text==source ? 'retain' : 'replace';reason='Disclosed source brand handling';origin=own.empty? ? 'reference' : 'user-and-reference'
   end
   if !unsupported&&rw&&rw['action']=='omit'&&rw['omissionReason'].to_s.match?(/associated|companion|dependent|qualifier/i)&&facts.any?{|f|%w[comparison specification].include?(f['kind'])}
    box=b['sourceBox'];parent=removed_claims.find{|a|q=a['sourceBox'];box['x']<q['x']+q['width']&&box['x']+box['width']>q['x']&&box['y']>=q['y']&&box['y']-q['y']-q['height']<=q['height']}
    if parent;text='';action='remove';reason='Dependent qualifier omitted together with unsupported reference claim';end
   end
   if (r=resolutions[b['id']])
    raise 'Explicit copy replacement needs user origin and authorization' unless r['origin']=='user'&&!r['authorization'].to_s.empty?&&r['text'].is_a?(String)
    text=r['text'];action=text.empty? ? 'remove' : 'replace';origin='explicit-user-copy';reason=r['authorization']
   end
   raise 'Unsupported forbidden source wording needs explicit resolution' if text.match?(/headlights?/i)
   d={'id'=>b['id'],'sourceText'=>source,'action'=>action,'text'=>text,'reason'=>reason,'authorization'=>'selected ai-rewrite content policy','provenance'=>{'origin'=>origin,'sourceBlockId'=>b['id'],'policyVersion'=>VERSION,'modelSuggestionAccepted'=>false,'referenceClaimApplicable'=>!unsupported}};decisions<<d
   if text.empty?
    rewrites<<{'blockId'=>b['id'],'coreIntent'=>b['coreIntent'],'marketingFunction'=>b['marketingFunction'],'action'=>'omit','renderIndex'=>-1,'omissionReason'=>reason,'preservedMeaningUnitIds'=>[],'usedFactIds'=>[],'omittedFactIds'=>facts.map{|f|f['id']}};next
   end
   g=source_structure&&source_structure['textGroups'].find{|a|a['blockIds']==[b['id']]};box=b.fetch('sourceBox');scale=[dimensions[0].to_f/v['sourceGeometry']['width'],dimensions[1].to_f/v['sourceGeometry']['height']].min
   original=rw&&rw['action']=='render'&&rw['renderIndex'].is_a?(Integer)&&rw['renderIndex']>=0 ? original_texts[rw['renderIndex']] : nil
   role=original&&%w[title subtitle body brand].include?(original['role']) ? original['role'] : (%w[title subtitle body brand].include?(b['marketingFunction']) ? b['marketingFunction'] : 'body')
   t={'text'=>text,'role'=>role,'fontSize'=>[box['height']*scale*0.6,200].min,'weight'=>g ? g['weight'] : 700,'style'=>g&&g['italic'] ? 'italic' : 'normal','lineHeightPx'=>box['height']*scale*0.8,'align'=>'left','color'=>g ? g['color'] : '#FFFFFF','box'=>{'x'=>(dimensions[0]-v['sourceGeometry']['width']*scale)/2+box['x']*scale,'y'=>(dimensions[1]-v['sourceGeometry']['height']*scale)/2+box['y']*scale,'width'=>box['width']*scale,'height'=>box['height']*scale}}
   t['role']='body' if (g&&g['placement']=='label')||(facts.any?{|f|f['kind']=='brand'}&&text!=source)
   d['renderIndex']=texts.size
   rewrites<<{'blockId'=>b['id'],'coreIntent'=>b['coreIntent'],'marketingFunction'=>b['marketingFunction'],'action'=>'render','renderIndex'=>texts.size,'omissionReason'=>'','preservedMeaningUnitIds'=>b['meaningUnitIds'],'usedFactIds'=>facts.select{|f|!f['value'].to_s.empty?&&text.downcase.include?(f['value'].downcase)}.map{|f|f['id']},'omittedFactIds'=>facts.reject{|f|!f['value'].to_s.empty?&&text.downcase.include?(f['value'].downcase)}.map{|f|f['id']}}
   texts<<t
  end
  v['text']=texts;e['rewrites']=rewrites
  {'candidate'=>v,'decisions'=>decisions,'pending'=>[],'changes'=>decisions.reject{|d|d['action']=='retain'},'state'=>'element-complete','policyVersion'=>VERSION}
 end
end
