require_relative 'product-asset-provider'
require 'tmpdir'
Dir.mktmpdir('intake-fixture-') do |dir|
 old=JSON.parse(File.read('diagnostics/two-backgrounds-20261018/step1-plan.json'));f=old['frozen'];layout=old['layout'];scene=File.expand_path('diagnostics/deterministic-decoration/render.png');meta=InputImage.inspect(File.binread(scene))
 c=JSON.parse(File.read('diagnostics/deterministic-decoration/test-results.json'))['contract'];c['sourceHash']=f['binding']['sourceHash'];c['textLayoutHash']=ReferenceAnchorReview.fingerprint(layout);c['canvas'].merge!('width'=>1856,'height'=>2304);c['sceneAssets'][0].merge!('sha256'=>Digest::SHA256.file(scene).hexdigest,'width'=>meta['dimensions'][0],'height'=>meta['dimensions'][1],'cleanSceneOnlyReviewed'=>false,'bakedFramesAbsentReviewed'=>false)
 {'frozen'=>f,'proposal'=>{'layout'=>layout},'contract'=>c}.each{|name,value|File.write(dir+'/'+name+'.json',JSON.generate(value))}
 i={'frozenFile'=>dir+'/frozen.json','proposalFile'=>dir+'/proposal.json','contractFile'=>dir+'/contract.json','backgroundFile'=>'/Users/manrongdu/Documents/Codex/2026-10-15/task/picture-local/diagnostics/local-anchor-audit/builtin-dark-background.png','assets'=>{'scene'=>scene},'fixtureOnly'=>true};File.write(dir+'/intake.json',JSON.generate(i))
 stdout,stderr,status=Open3.capture3('/usr/bin/ruby',File.expand_path('prepare-decoration-cache.rb'),dir+'/intake.json',dir+'/draft')
 raise 'unreviewed intake accepted' if status.success?;raise stderr unless stderr.include?('decoration requires trusted local scene review')
 raise 'draft missing' unless File.file?(dir+'/draft/package-draft.json')
 stdout,stderr,status=Open3.capture3('/usr/bin/ruby',File.expand_path('prepare-decoration-cache.rb'),dir+'/intake.json',dir+'/draft','--install')
 raise 'fixture installed' if status.success?;raise stderr unless stderr.include?('offline fixture cannot be installed')
 File.write('diagnostics/deterministic-decoration/intake-test.json',JSON.pretty_generate({unreviewedDraftBlocked:true,fixtureInstallBlocked:true,realInputAcceptance:false,modelCalls:0}));puts 'PASS unreviewed draft blocked; fixture production install blocked'
end
