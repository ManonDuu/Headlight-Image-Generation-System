# Optional geometry observed in the received clean scene, never borrowed source coordinates.
module SceneOverlayContract
 def self.validate(v,source,scenes)
  return nil unless v
  raise 'overlay source binding mismatch' unless v['sourceHash']==source&&v['version']=='scene-overlays-1'
  scene=scenes.find{|s|s['role']==v['sceneRole']};raise 'overlay scene binding mismatch' unless scene&&scene['sha256']==v['sceneHash']
  bytes=Base64.strict_decode64(scene['base64']);dims=InputImage.inspect(bytes)['dimensions'];raise 'overlay scene dimensions mismatch' unless dims==v['sceneSize']&&v['actualPixelsViewed']==true
  w,h=dims;rect=->(b){b.is_a?(Hash)&&%w[x y width height].all?{|k|b[k].is_a?(Numeric)&&b[k].finite?}&&b['x']>=0&&b['y']>=0&&b['width']>0&&b['height']>0&&b['x']+b['width']<=w&&b['y']+b['height']<=h};color=->(c){c.to_s.match?(/\A#[a-fA-F0-9]{6}\z/)}
  v.fetch('decorations').each do |d|
   raise 'overlay unsupported type' unless %w[rounded-rect ellipse polygon path].include?(d['type'])
   raise 'overlay style invalid' unless color.call(d['color'])&&d['width'].is_a?(Numeric)&&d['width'].between?(0,20)&&d['reason'].is_a?(String)&&!d['reason'].empty?
   if %w[rounded-rect ellipse].include?(d['type']);raise 'overlay rect invalid' unless rect.call(d['bounds'])&&d['radius'].is_a?(Numeric)&&d['radius'].between?(0,50)
   elsif d['type']=='path'
    raise 'overlay path invalid' unless d['commands'].is_a?(Array)&&d['commands'].size.between?(1,64)&&d['commands'].all?{|a|a.is_a?(Array)&&{'M'=>2,'L'=>2,'Q'=>4,'C'=>6,'Z'=>0}[a[0]]==a.size-1&&a.drop(1).each_slice(2).all?{|x,y|x.is_a?(Numeric)&&y.is_a?(Numeric)&&x.between?(0,w)&&y.between?(0,h)}}
   else;raise 'overlay polygon invalid' unless d['points'].is_a?(Array)&&d['points'].size.between?(3,16)&&d['points'].all?{|p|p.size==2&&p[0].is_a?(Numeric)&&p[1].is_a?(Numeric)&&p[0].between?(0,w)&&p[1].between?(0,h)};end
  end
  if v['regions']
   raise 'overlay regions missing source geometry' unless v['sourceSize'].is_a?(Array)&&v['sourceSize'].size==2&&v['regions'].size.between?(1,8)
   sw,sh=v['sourceSize'];v['regions'].each do |region|
    b=region['targetSourceBounds'];raise 'overlay region invalid' unless rect.call(region['bounds'])&&b.is_a?(Hash)&&%w[x y width height].all?{|k|b[k].is_a?(Numeric)&&b[k].finite?}&&b['x']>=0&&b['y']>=0&&b['width']>0&&b['height']>0&&b['x']+b['width']<=sw&&b['y']+b['height']<=sh&&color.call(region['borderColor'])&&region['borderWidth'].is_a?(Numeric)&&region['borderWidth'].between?(0,20)
   end
  end
  v.fetch('textSlots').each{|slot|raise 'overlay text slot invalid' unless slot['blockId'].is_a?(String)&&rect.call(slot['bounds'])}
  raise 'duplicate overlay slots' unless v['textSlots'].map{|s|s['blockId']}.uniq.size==v['textSlots'].size
  v
 end
end
