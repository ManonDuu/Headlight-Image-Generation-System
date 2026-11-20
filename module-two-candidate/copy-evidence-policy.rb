# Structural evidence enforcement, not a claim of automatic semantic understanding.
module CopyEvidencePolicy
 VERSION='copy-evidence-1'
 def self.schema
  str={'type'=>'string'}
  fact={'type'=>'object','properties'=>%w[id value origin userField].map{|k|[k,str]}.to_h.merge('kind'=>{'type'=>'string','enum'=>%w[qualitative brand specification certification comparison]},'origin'=>{'type'=>'string','enum'=>%w[reference user]}),'required'=>%w[id value origin userField kind]}
  block={'type'=>'object','properties'=>%w[id sourceText coreIntent marketingFunction].map{|k|[k,str]}.to_h.merge('sourceBox'=>{'type'=>'object','properties'=>%w[x y width height].map{|k|[k,{'type'=>'number'}]}.to_h,'required'=>%w[x y width height]},'meaningUnitIds'=>{'type'=>'array','items'=>str}),'required'=>%w[id sourceText sourceBox coreIntent marketingFunction meaningUnitIds]}
  rewrite={'type'=>'object','properties'=>%w[blockId coreIntent marketingFunction].map{|k|[k,str]}.to_h.merge('action'=>{'type'=>'string','enum'=>%w[render omit]},'renderIndex'=>{'type'=>'integer'},'omissionReason'=>str,'preservedMeaningUnitIds'=>{'type'=>'array','items'=>str},'usedFactIds'=>{'type'=>'array','items'=>str},'omittedFactIds'=>{'type'=>'array','items'=>str}),'required'=>%w[blockId coreIntent marketingFunction action renderIndex omissionReason preservedMeaningUnitIds usedFactIds omittedFactIds]}
  {'type'=>'object','properties'=>{'facts'=>{'type'=>'array','items'=>fact},'sourceBlocks'=>{'type'=>'array','items'=>block},'rewrites'=>{'type'=>'array','items'=>rewrite}},'required'=>%w[facts sourceBlocks rewrites]}
 end
 def self.audit(evidence,options,text)
  return {'state'=>'custom-verbatim','pending'=>[]} if options['mode']=='custom'
  return {'state'=>'no-copy','pending'=>[]} if options['mode']=='remove-all-copy'
  raise 'semantic evidence required; do not substitute empty labels' unless evidence.is_a?(Hash)&&%w[facts sourceBlocks rewrites].all?{|k|evidence[k].is_a?(Array)}
  facts=evidence['facts'];blocks=evidence['sourceBlocks'];rewrites=evidence['rewrites'];pending=[]
  raise 'semantic block count mismatch' unless rewrites.size==blocks.size&&rewrites.count{|w|w.fetch('action','render')=='render'}==text.size
  raise 'duplicate evidence id' unless facts.map{|f|f['id']}.uniq.size==facts.size&&blocks.map{|b|b['id']}.uniq.size==blocks.size
  by_id=rewrites.group_by{|rw|rw['blockId']}
  raise 'ambiguous source association' unless by_id.keys.sort==blocks.map{|b|b['id']}.sort&&by_id.values.all?{|rows|rows.size==1}
  rewrites=blocks.map{|b|by_id.fetch(b['id']).first}
  verified={}
  facts.each do |f|
   raise 'invalid fact origin/value' unless %w[reference user].include?(f['origin'])&&f['value'].is_a?(String)&&!f['value'].strip.empty?
   field=f['userField'];provided=%w[brandName productParameters].include?(field)&&options[field].is_a?(String)&&options[field].include?(f['value'])
   raise 'model cannot invent user fact authority' if f['origin']=='user'&&!provided
   verified[f['id']]=f['origin']=='user'&&provided
  end
  rendered_indices=rewrites.each_with_index.select{|w,i|w.fetch('action','render')=='render'}.map{|w,i|w.fetch('renderIndex',i)}
  raise 'ambiguous render indices' unless rendered_indices.sort==(0...text.size).to_a
  blocks.zip(rewrites).each_with_index do |(b,w),i|
   if w['action']=='omit'
    raise 'unexplained omission' unless w['blockId']==b['id']&&w['renderIndex']==-1&&w['omissionReason'].is_a?(String)&&!w['omissionReason'].strip.empty?&&w['usedFactIds']==[]
    pending<<{'blockId'=>b['id'],'reason'=>'Verify omission removes only unsupported claims, preserving eligible selling meaning'}
    next
   end
   t=text.fetch(w.fetch('renderIndex',i))
   raise 'meaning evidence incomplete' unless %w[id sourceText coreIntent marketingFunction].all?{|k|b[k].is_a?(String)&&!b[k].strip.empty?}&&b['meaningUnitIds'].is_a?(Array)&&!b['meaningUnitIds'].empty?
   pending<<{'blockId'=>b['id'],'reason'=>'Meaning metadata differs; inspect whole-image intent, not a delivery blocker'} unless w['blockId']==b['id']&&w['coreIntent']==b['coreIntent']&&w['marketingFunction']==b['marketingFunction']&&(b['meaningUnitIds']-w.fetch('preservedMeaningUnitIds',[])).empty?
   raise 'empty rewrite is not fact safety' unless t['text'].is_a?(String)&&!t['text'].strip.empty?
   used=w.fetch('usedFactIds');omitted=w.fetch('omittedFactIds');raise 'ambiguous fact handling' unless used.is_a?(Array)&&omitted.is_a?(Array)&&(used&omitted).empty?&&(used+omitted).all?{|id|verified.key?(id)}
   used.each{|id|pending<<{'blockId'=>b['id'],'factId'=>id,'reason'=>'Reference-only fact needs explicit confirmation'} unless verified[id]}
  end
  # Whole-image requirement only: one natural change is enough. Case, punctuation
  # and line wrapping alone do not create a meaningful copy difference.
  words=lambda{|s|s.downcase.scan(/[[:alnum:]]+/).join(' ')}
  raise 'AI copy collection unchanged except case/punctuation/wrapping' if words.call(blocks.map{|b|b['sourceText']}.join(' '))==words.call(text.map{|t|t['text']}.join(' '))
  # A model declaring equal intent IDs is not proof the words actually preserve meaning.
  pending<<{'reason'=>'Independent meaning review required: check proposed wording against source intent; metadata equality is not semantic proof'}
  {'version'=>VERSION,'state'=>'candidate-with-warnings','pending'=>pending,'wholeImageLexicalDifference'=>true,'meaningfulDifference'=>'requires-review','perBlockDifferenceRequired'=>false,'minimumLexicalDifferenceRatio'=>nil,'silentlyReplaceWithNeutralLabels'=>false,'factAuthority'=>'user-fields-only','referenceFactsAreUnconfirmed'=>true}
 end
end
