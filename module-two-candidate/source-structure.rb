# Source observations only. Never contains final copy or output coordinates.
module SourceStructure
 VERSION='source-structure-1'
 def self.schema
  n={'type'=>'number'};rect={'type'=>'object','properties'=>%w[x y width height].to_h{|k|[k,n]},'required'=>%w[x y width height]};str={'type'=>'string'}
  group={'type'=>'object','properties'=>{'blockIds'=>{'type'=>'array','items'=>str},'bounds'=>rect,'quad'=>{'type'=>'array','items'=>{'type'=>'array','items'=>n}},'italic'=>{'type'=>'boolean'},'weight'=>n,'paletteRole'=>{'type'=>'string','enum'=>%w[neutral accent emphasis]},'color'=>str,'owner'=>str,'placement'=>{'type'=>'string','enum'=>%w[free header label detail]}},'required'=>%w[blockIds bounds quad italic weight paletteRole color owner placement]}
  panel={'type'=>'object','properties'=>{'id'=>str,'bounds'=>rect,'labelBounds'=>{'anyOf'=>[rect,{'type'=>'null'}]},'sceneRole'=>str,'borderColor'=>str,'labelColor'=>str,'radius'=>n,'borderWidth'=>n,'sceneBounds'=>rect,'labelRadius'=>n,'labelFillStops'=>{'type'=>'array','items'=>{'type'=>'object','properties'=>{'at'=>n,'color'=>str},'required'=>%w[at color]}},'labelPointer'=>{'type'=>'array','items'=>{'type'=>'array','items'=>n}}},'required'=>%w[id bounds labelBounds sceneRole borderColor labelColor radius]}
  {'type'=>'object','properties'=>{'version'=>{'type'=>'string','enum'=>[VERSION]},'coordinateSpace'=>{'type'=>'string','enum'=>['source-pixels']},'productPresent'=>{'type'=>'boolean'},'productVisibleBounds'=>rect,'textGroups'=>{'type'=>'array','items'=>group},'panels'=>{'type'=>'array','items'=>panel},'decorations'=>{'type'=>'array','items'=>{'type'=>'object','properties'=>{'type'=>{'type'=>'string','enum'=>%w[rounded-rect ellipse path polygon]},'bounds'=>rect,'color'=>str,'width'=>n,'radius'=>n,'fill'=>{'type'=>'boolean'},'points'=>{'type'=>'array','items'=>{'type'=>'array','items'=>n}},'commands'=>{'type'=>'array','items'=>{'type'=>'array','items'=>{'anyOf'=>[str,n]}}}},'required'=>%w[type bounds color width radius fill points commands]}}},'required'=>%w[version coordinateSpace productPresent productVisibleBounds textGroups panels]}
 end
 def self.scene_bounds(panel,source_width)
  return panel['sceneBounds'] if panel['sceneBounds']
  b,l=panel.values_at('bounds','labelBounds');pad=[panel['radius'],source_width*0.01].max;top=[b['y']+pad,l ? l['y']+l['height']+source_width*0.012 : b['y']+pad].max
  {'x'=>b['x']+pad,'y'=>top,'width'=>b['width']-2*pad,'height'=>b['y']+b['height']-pad-top}
 end
 def self.validate(v,layout,product:)
  raise 'SOURCE_STRUCTURE_MISSING: source body/text perspective/panels missing; legacy response needs explicit source-observation adapter' unless v.is_a?(Hash)
  raise 'SOURCE_STRUCTURE_VERSION' unless v['version']==VERSION&&v['coordinateSpace']=='source-pixels'
  w,h=layout.fetch('sourceGeometry').values_at('width','height');rect=->(b){b.is_a?(Hash)&&%w[x y width height].all?{|k|b[k].is_a?(Numeric)&&b[k].finite?}&&b['x']>=0&&b['y']>=0&&b['width']>0&&b['height']>0&&b['x']+b['width']<=w&&b['y']+b['height']<=h}
  raise 'PRODUCT_VISIBLE_BOUNDS_MISSING' if product&&(!v['productPresent']||!rect.call(v['productVisibleBounds']))
  raise 'MODULE_ONE_PRODUCT_BODY_OUT_OF_SCOPE' if !product && v['productPresent']
  ids=layout.fetch('evidence').fetch('sourceBlocks').map{|b|b['id']};groups=v['textGroups'];raise 'SOURCE_TEXT_GROUPS_INCOMPLETE' unless groups.is_a?(Array)&&groups.flat_map{|g|g['blockIds']}.sort==ids.sort
  groups.each do |g|
   raise 'SOURCE_GROUP_INVALID' unless rect.call(g['bounds'])&&g['weight'].is_a?(Numeric)&&g['weight'].between?(100,900)&&%w[neutral accent emphasis].include?(g['paletteRole'])&&g['color'].match?(/\A#[0-9a-fA-F]{6}\z/)
   raise 'SOURCE_FILL_DIRECTION_INVALID' if g.key?('fillDirection')&&!%w[horizontal vertical].include?(g['fillDirection'])
   if g.key?('fillStops');stops=g['fillStops'];raise 'SOURCE_FILL_INVALID' unless stops.is_a?(Array)&&stops.size<=4&&stops.all?{|p|p.is_a?(Hash)&&p['at'].is_a?(Numeric)&&p['at'].between?(0,1)&&p['color'].to_s.match?(/\A#[0-9a-fA-F]{6}\z/)}&&stops.map{|p|p['at']}==stops.map{|p|p['at']}.sort;end
   if g.key?('outline');a=g['outline'];raise 'SOURCE_OUTLINE_INVALID' unless a.is_a?(Hash)&&a['width'].is_a?(Numeric)&&a['width'].between?(0,w*0.05)&&a['color'].to_s.match?(/\A#[0-9a-fA-F]{6}\z/);end
   q=g['quad'];raise 'SOURCE_QUAD_INVALID' unless q.is_a?(Array)&&q.size==4&&q.all?{|p|p.is_a?(Array)&&p.size==2&&p.all?{|x|x.is_a?(Numeric)&&x.finite?}&&p[0].between?(0,w)&&p[1].between?(0,h)}
   crosses=4.times.map{|i|a,b,c=q[i],q[(i+1)%4],q[(i+2)%4];(b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0])};raise 'SOURCE_QUAD_NOT_CONVEX' unless crosses.all?{|x|x>0}||crosses.all?{|x|x<0}
  end
  # Optional source-layout illustrations. These are not generated-scene crop coordinates.
  decorations=v.fetch('decorations',[]);raise 'SOURCE_DECORATIONS_INVALID' unless decorations.is_a?(Array)
  decorations.each do |d|
   raise 'SOURCE_DECORATION_INVALID' unless d.is_a?(Hash)&&%w[rounded-rect ellipse path polygon].include?(d['type'])&&rect.call(d['bounds'])&&d['color'].to_s.match?(/\A#[0-9a-fA-F]{6}\z/)&&[true,false].include?(d['fill'])&&%w[width radius].all?{|key|d[key].is_a?(Numeric)&&d[key].finite?&&d[key]>=0}
   if d.key?('fillStops');raise 'SOURCE_DECORATION_FILL_INVALID' unless %w[horizontal vertical].include?(d['fillDirection'])&&d['fillStops'].is_a?(Array)&&d['fillStops'].size.between?(2,4)&&d['fillStops'].all?{|p|p['at'].is_a?(Numeric)&&p['at'].between?(0,1)&&p['color'].to_s.match?(/\A#[0-9a-fA-F]{6}\z/)}&&d['fillStops'].map{|p|p['at']}==d['fillStops'].map{|p|p['at']}.sort;end
   point=->(a){a.is_a?(Array)&&a.size==2&&a.all?{|n|n.is_a?(Numeric)&&n.finite?}&&a[0].between?(d['bounds']['x'],d['bounds']['x']+d['bounds']['width'])&&a[1].between?(d['bounds']['y'],d['bounds']['y']+d['bounds']['height'])}
   raise 'SOURCE_DECORATION_POINTS_INVALID' if d['type']=='polygon'&&(!d['points'].is_a?(Array)||d['points'].size<3||!d['points'].all?{|a|point.call(a)})
   raise 'SOURCE_DECORATION_PATH_INVALID' if d['type']=='path'&&(!d['commands'].is_a?(Array)||d['commands'].empty?||d['commands'][0][0]!='M'||!d['commands'].all?{|a|a.is_a?(Array)&&{'M'=>2,'L'=>2,'Q'=>4,'C'=>6,'Z'=>0}[a[0]]==a.size-1&&a.drop(1).each_slice(2).all?{|xy|point.call(xy)}})
  end
  panels=v['panels'];raise 'SOURCE_PANELS_INVALID' unless panels.is_a?(Array)&&panels.map{|p|p['id']}.uniq.size==panels.size&&panels.all?{|p|rect.call(p['bounds'])&&(p['labelBounds'].nil?||rect.call(p['labelBounds']))&&p['sceneRole'].is_a?(String)&&p['sceneRole'].match?(/\A[a-z][a-z0-9-]{0,63}\z/)&&%w[borderColor labelColor].all?{|k|p[k].is_a?(String)&&p[k].match?(/\A#[0-9a-fA-F]{6}\z/)}&&p['radius'].is_a?(Numeric)&&p['radius']>=0}
  panels.each do |p|
   b,l=p.values_at('bounds','labelBounds');
   if p.key?('sceneBounds')
    scene=p['sceneBounds'];raise 'SOURCE_SCENE_INVALID' unless rect.call(scene)&&scene['x']>=b['x']&&scene['y']>=b['y']&&scene['x']+scene['width']<=b['x']+b['width']&&scene['y']+scene['height']<=b['y']+b['height']
    raise 'SOURCE_SCENE_LABEL_OVERLAP' if l&&scene['x']<l['x']+l['width']&&scene['x']+scene['width']>l['x']&&scene['y']<l['y']+l['height']&&scene['y']+scene['height']>l['y']
   end
   %w[borderWidth labelRadius].each{|key|raise 'SOURCE_DECORATION_SIZE_INVALID' if p.key?(key)&&(!p[key].is_a?(Numeric)||!p[key].finite?||p[key]<0)}
   if p.key?('labelFillStops');st=p['labelFillStops'];raise 'SOURCE_LABEL_FILL_INVALID' unless st.is_a?(Array)&&(st.empty?||st.size.between?(2,8))&&st.all?{|v|v['at'].is_a?(Numeric)&&v['at'].between?(0,1)&&v['color'].to_s.match?(/\A#[0-9a-fA-F]{6}\z/)}&&st.map{|v|v['at']}==st.map{|v|v['at']}.sort;end
   if p.key?('labelPointer');raise 'SOURCE_LABEL_POINTER_INVALID' unless p['labelPointer'].is_a?(Array)&&[0,3].include?(p['labelPointer'].size)&&p['labelPointer'].all?{|q|q.is_a?(Array)&&q.size==2&&q[0].is_a?(Numeric)&&q[1].is_a?(Numeric)&&q[0].between?(b['x'],b['x']+b['width'])&&q[1].between?(b['y'],b['y']+b['height'])};end
raise 'SOURCE_LABEL_OUTSIDE_PANEL' unless !l || l['x']>=b['x']&&l['y']>=b['y']&&l['x']+l['width']<=b['x']+b['width']&&l['y']+l['height']<=b['y']+b['height']
  end
  groups.each do |g|
   raise 'SOURCE_TEXT_OWNERSHIP_MISSING' unless %w[free header label detail].include?(g['placement']) && (g['owner']=='canvas' || panels.any?{|p|p['id']==g['owner']})
   raise 'SOURCE_TEXT_OWNERSHIP_INVALID' if %w[label detail].include?(g['placement']) && g['owner']=='canvas'
  end
  panels.each{|p|raise 'SOURCE_LABEL_CONTAINER_MISSING' if !p['labelBounds']&&groups.any?{|g|g['owner']==p['id']&&g['placement']=='label'}}
  # Compare original observations in SOURCE pixels before any output transform.
  panels.each do |panel|
   labels=groups.select{|g|g['owner']==panel['id']&&g['placement']=='label'};container=panel['labelBounds'];next unless container
   raise "SOURCE_LABEL_RELATION_PENDING: panel #{panel['id']} has a label container but no source label text" if labels.empty?
   tolerance=[2.0,[container['width'],container['height']].min*0.03].max
   inside=->(r){r&&r['x']>=container['x']-tolerance&&r['y']>=container['y']-tolerance&&r['x']+r['width']<=container['x']+container['width']+tolerance&&r['y']+r['height']<=container['y']+container['height']+tolerance}
   labels.each do |g|
    source_boxes=g['blockIds'].map{|id|layout['evidence']['sourceBlocks'].find{|block|block['id']==id}&.fetch('sourceBox')}
    quad_ok=g['quad'].all?{|x,y|inside.call({'x'=>x,'y'=>y,'width'=>0,'height'=>0})}
    unless inside.call(g['bounds'])&&quad_ok&&source_boxes.all?{|r|inside.call(r)}
     raise "SOURCE_LABEL_RELATION_PENDING: panel #{panel['id']}, blocks #{g['blockIds'].join(',')}: source label text and container disagree; no automatic relocation"
    end
   end
  end
  v
 end
end
