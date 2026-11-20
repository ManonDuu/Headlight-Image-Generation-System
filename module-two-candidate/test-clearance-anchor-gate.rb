require_relative 'product-asset-provider'
require 'tmpdir'
l=JSON.parse(File.read('diagnostics/preserve-copy/proposal.json'))['layout'];a=JSON.parse(File.read('diagnostics/canbus-clearance/audit.json'));checks=[]
need=lambda{|v,m|raise m unless v;checks<<m}
need.call(ReferenceAnchorReview.require!(a['sourceHash'],l)['evidencePolicy']=='retained-and-clearance-v1','reviewed omitted OCR error passes independently of retained CANBUS')
need.call(a['sourceBlocks'].find{|b|b['id']=='b3'}.values_at('rawOCR','recognizedSourceText','matches','outputAction')==['09%','99%',0,'omit'],'raw OCR stays wrong; source correction never becomes output copy')
need.call(l['text'].map{|t|t['text']}==["CANBUS\nREADY"]&&l['evidence']['rewrites'].select{|r|r['action']=='render'}.map{|r|[r['blockId'],r['renderIndex']]}==[['b2',0]],'final filtered render associations rebuilt')
Dir.mktmpdir('clearance-gate-') do |root|
 ReferenceAnchorReview.send(:remove_const,:ROOT);ReferenceAnchorReview.const_set(:ROOT,root)
 verify=lambda do |audit,layout|
  audit['layoutHash']=ReferenceAnchorReview.fingerprint(layout);dir=File.join(root,audit['sourceHash']);FileUtils.mkdir_p(dir);File.write(File.join(dir,audit['layoutHash']+'.json'),JSON.generate(audit));ReferenceAnchorReview.require!(audit['sourceHash'],layout)
 end
 reject=lambda do |name,&mutation|
  audit=Marshal.load(Marshal.dump(a));layout=Marshal.load(Marshal.dump(l));mutation.call(audit,layout)
  begin;verify.call(audit,layout);raise 'unexpected acceptance';rescue=>e;raise if e.message=='unexpected acceptance';checks<<name;end
 end
 reject.call('retained CANBUS misread blocks'){|v,_|v['sourceBlocks'].find{|b|b['id']=='b2'}['matches']=0}
 reject.call('retained duplicate OCR blocks'){|v,_|v['sourceBlocks'].find{|b|b['id']=='b2'}['matches']=2}
 reject.call('retained missing OCR blocks'){|v,_|v['sourceBlocks'].reject!{|b|b['id']=='b2'}}
 reject.call('unreviewed clearance blocks'){|v,_|v['sourceBlocks'].find{|b|b['id']=='b3'}['clearanceReview']='uncertain'}
 reject.call('uncorrected source recognition blocks'){|v,_|v['sourceBlocks'].find{|b|b['id']=='b3'}['recognizedSourceText']='09%'}
 reject.call('missing clearance region blocks'){|v,_|v['sourceBlocks'].find{|b|b['id']=='b3'}.delete('clearanceBox')}
 reject.call('out of canvas clearance blocks'){|v,_|v['sourceBlocks'].find{|b|b['id']=='b3'}['clearanceBox']['width']=9999}
 reject.call('missing omission reason blocks'){|v,x|x['evidence']['rewrites'].find{|r|r['blockId']=='b3'}['omissionReason']=''}
 reject.call('omitted block cannot supply retained anchor'){|v,_|v['renderAnchors'][0]['blockId']='b3'}
 reject.call('cleared claim cannot be promoted to render'){|v,x|r=x['evidence']['rewrites'].find{|r|r['blockId']=='b3'};r['action']='render';r['renderIndex']=0}
 reject.call('retained semantic uncertainty blocks'){|v,_|v['renderAnchors'][0]['semanticState']='uncertain'}
 reject.call('unreviewed multiline blocks before background'){|v,_|v['renderAnchors'][0].delete('lineMappingReview')}
 reject.call('candidate text mismatch blocks'){|v,_|v['renderAnchors'][0]['candidate']['sourceText']='99%'}
 reject.call('retained glyph uncertainty blocks'){|v,_|v['renderAnchors'][0]['glyphState']='uncertain'}
end
File.write('diagnostics/canbus-clearance/gate-regression.json',JSON.pretty_generate({checks:checks,modelCalls:0}));puts JSON.generate({checks:checks.size,modelCalls:0})
