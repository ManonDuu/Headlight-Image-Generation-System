# Pure source-ID resolution. No fuzzy text matching or model dispatch.
require_relative 'default-product-facts'
module RenderAssociationResolution
 def self.words(s);s.to_s.downcase.scan(/[[:alnum:]]+/);end
 def self.process(value,options,source_size,output_size)
  v=Marshal.load(Marshal.dump(value));e=v.fetch('evidence');blocks=e.fetch('sourceBlocks');rows=e.fetch('rewrites');audit=[]
  raise 'ambiguous source association' unless blocks.map{|b|b['id']}.uniq.size==blocks.size&&rows.group_by{|r|r['blockId']}.values.all?{|a|a.size==1}&&rows.map{|r|r['blockId']}.sort==blocks.map{|b|b['id']}.sort
  invalid=e.fetch('facts').select{|f|f['origin']=='user'&&(!%w[brandName productParameters].include?(f['userField'])||f['value'].to_s.empty?||!options.fetch(f['userField'],'').include?(f['value']))}
  invalid_ids=invalid.map{|f|f['id']};handled=[];output=[]
  by_render=rows.select{|r|r['action']=='render'}.group_by{|r|r['renderIndex']}
  v.fetch('text').each_with_index do |t,index|
   matches=by_render.fetch(index,[]);raise 'unassociated render block' if matches.empty?
   sources=matches.map{|r|blocks.find{|b|b['id']==r['blockId']}}
   bad=matches.flat_map{|r|r.fetch('usedFactIds',[])}&invalid_ids
   misplaced_canbus=t['text'].match?(DefaultProductFacts::CANBUS)&&sources.all?{|b|%w[title subtitle].include?(b['marketingFunction'])&&!b['sourceText'].match?(DefaultProductFacts::CANBUS)}
   # Invalid injected functionality can be removed without guessing a rewrite:
   # explicitly retain each observed qualitative title at its own source geometry.
   restore=misplaced_canbus&&options['module']=='reference-reconstruction'&&options['mode']=='ai-rewrite'&&sources.all?{|b|!b['sourceText'].match?(/\d|guarantee|compatib|built.in/i)}
   raise 'unverified user fact in render; source retention unavailable' if bad.any?&&!restore
   if matches.size>1&&!restore
    raise 'ambiguous render association; merged rewrite lacks exact source partition' unless words(t['text'])==sources.flat_map{|b|words(b['sourceText'])}
   end
   if matches.size>1||restore
    sources.zip(matches).each do |b,r|
     box=b.fetch('sourceBox');scale=[output_size[0].to_f/source_size[0],output_size[1].to_f/source_size[1]].min
     copy=Marshal.load(Marshal.dump(t));copy['text']=b['sourceText'];copy['box']={'x'=>(output_size[0]-source_size[0]*scale)/2+box['x']*scale,'y'=>(output_size[1]-source_size[1]*scale)/2+box['y']*scale,'width'=>box['width']*scale,'height'=>box['height']*scale}
     r['renderIndex']=output.size;r['usedFactIds']-=invalid_ids;r['omittedFactIds']-=invalid_ids;output<<copy
    end
    handled.concat(bad);audit<<{'renderIndex'=>index,'blockIds'=>sources.map{|b|b['id']},'originalText'=>t['text'],'action'=>restore ? 'retain-observed-source-remove-injected-canbus' : 'partition-exact-source-words','reason'=>'Source IDs and source boxes retained independently; no semantic rewrite allocation inferred'}
   else
    matches.first['renderIndex']=output.size;output<<t
   end
  end
  raise 'unverified user fact authority remains' unless (invalid_ids-handled).empty?
  e['facts'].reject!{|f|invalid_ids.include?(f['id'])};rows.each{|r|r['usedFactIds']-=invalid_ids;r['omittedFactIds']-=invalid_ids};v['text']=output
  {'candidate'=>v,'changes'=>audit,'rejectedUserFacts'=>invalid}
 end
end
