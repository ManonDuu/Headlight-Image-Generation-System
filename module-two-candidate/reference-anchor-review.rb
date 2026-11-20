# Local review evidence only. Never obtain OCR, keys, or network data here.
require 'json';require 'digest'
module ReferenceAnchorReview
 ROOT=File.join(__dir__,'reference-anchor-audits')
 def self.canonical(v)
  case v;when Hash;v.keys.sort.map{|k|[k,canonical(v[k])]}.to_h;when Array;v.map{|x|canonical(x)};else;v;end
 end
 def self.fingerprint(layout);Digest::SHA256.hexdigest(JSON.generate(canonical(layout)));end
 def self.clearance_valid?(o,b,layout,audit)
  rw=(layout.dig('evidence','rewrites')||[]).select{|r|r['blockId']==b['id']}
  box=o['clearanceBox'];size=audit['sourceSize']
  rw.size==1&&rw[0]['action']=='omit'&&rw[0]['renderIndex']==-1&&!rw[0]['omissionReason'].to_s.strip.empty?&&
   o['outputAction']=='omit'&&o['clearanceReview']=='reviewed'&&o['sourceRecognitionReview']=='manual-pixel-verified'&&
   o['recognizedSourceText']==b['sourceText']&&o['omissionReason']==rw[0]['omissionReason']&&
   !(audit['renderAnchors']||[]).any?{|a|a['blockId']==b['id']}&&
   box.is_a?(Hash)&&size.is_a?(Array)&&size.size==2&&%w[x y width height].all?{|k|box[k].is_a?(Numeric)&&box[k].finite?}&&
   box['x']>=0&&box['y']>=0&&box['width']>0&&box['height']>0&&box['x']+box['width']<=size[0]&&box['y']+box['height']<=size[1]
 end
 def self.render_mapping_valid?(a,layout,observations)
  o=observations.find{|b|b['id']==a['blockId']};c=a['candidate'];t=layout['text'][a['renderIndex']] if a['renderIndex'].is_a?(Integer)
  return false unless o&&c.is_a?(Hash)&&t&&c['sourceText']==o['sourceText']&&c['role']==t['role']
  lines=c['sourceText'].split("\n");measured=a['measuredLines']
  return false unless measured.is_a?(Array)&&measured.size==lines.size&&measured.each_with_index.all?{|l,i|l['sourceText']==lines[i]}
  return false if lines.size>1&&(a['lineMappingReview']!='reviewed'||t['text'].split("\n")!=lines)
  true
 end
 def self.require!(source_hash,layout)
  hash=fingerprint(layout);path=File.join(ROOT,source_hash,hash+'.json')
  raise '保留参考排版尚缺本地可信锚点复核；不会自动改为自动排版。' unless File.file?(path)
  audit=JSON.parse(File.read(path));blocks=layout.dig('evidence','sourceBlocks')||[]
  valid=audit['sourceHash']==source_hash&&audit['layoutHash']==hash&&audit['reviewState']=='verified-local-review'&&audit['semanticReview']=='reviewed'
  if audit['evidencePolicy']=='reviewed-reflow-v1'
   valid&&=audit['nativeLayout']==layout&&audit['nativeLayoutHash']==hash&&audit['sourceElementIds']==blocks.map{|b|b['id']}&&audit['sourcePixelsReviewed']==true&&audit['renderPixelsReviewed']==true&&audit['glyphs'].is_a?(Array)&&audit['glyphs'].size==layout['text'].size
   raise '重排布局与逐元素像素复核绑定不一致' unless valid
   return audit
  end
  observations=audit['sourceBlocks']||[]
  valid&&=observations.map{|b|b['id']}.sort==blocks.map{|b|b['id']}.sort
  valid&&=blocks.all? do |b|
   matches=observations.select{|o|o['id']==b['id']};o=matches.first
   matches.size==1&&o['sourceText']==b['sourceText']&&
    (o['state']=='reviewed-clearance-region' ? clearance_valid?(o,b,layout,audit) : o['matches']==1&&o['state']=='unique-ocr-phrase-anchor-candidate')
  end
  if audit['evidencePolicy']=='retained-and-clearance-v1'
   rewrites=layout.dig('evidence','rewrites')||[]
   valid&&=rewrites.map{|r|r['blockId']}.sort==blocks.map{|b|b['id']}.sort
   rendered=rewrites.select{|r|r['action']=='render'}
   valid&&=rendered.map{|r|r['renderIndex']}.sort==(0...layout['text'].size).to_a
   valid&&=(audit['renderAnchors']||[]).all?{|a|rendered.any?{|r|r['blockId']==a['blockId']&&r['renderIndex']==a['renderIndex']}&&observations.any?{|o|o['id']==a['blockId']&&o['state']=='unique-ocr-phrase-anchor-candidate'}}
   valid&&=rewrites.all?{|r|%w[render omit].include?(r['action'])}
   valid&&=(audit['renderAnchors']||[]).all?{|a|render_mapping_valid?(a,layout,observations)}
  end
  valid&&=audit['renderAnchors'].is_a?(Array)&&audit['renderAnchors'].size==layout['text'].size&&audit['renderAnchors'].map{|a|a['renderIndex']}.sort==(0...layout['text'].size).to_a&&audit['renderAnchors'].all?{|a|a['semanticState']=='reviewed'&&a['glyphState']=='measured'}
  if audit['nativeLayout'];valid&&=audit['nativeLayoutHash']==fingerprint(audit['nativeLayout'])&&audit['nativeLayout']['text'].map{|t|t.values_at('text','role','mode')}==layout['text'].map{|t|t.values_at('text','role','mode')};end
  raise '本地锚点有错读、重复、缺失、语义待定或绑定变化；保留参考排版已停止。' unless valid
  audit
 end
end
