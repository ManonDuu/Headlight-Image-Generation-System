# Explicit local reviewed-material intake. No network, model, output image, or global bypass.
require 'json';require 'digest';require 'base64';require 'fileutils';require 'tmpdir';require 'open3';require 'time'
root=File.expand_path(ARGV.fetch(0));bundle=JSON.parse(File.read(ARGV.fetch(1)));raise 'explicit reviewed-source authority required' unless bundle['authority']=='parent-visual-review-and-local-material-intake-20261019'
require File.join(root,'product-asset-provider')
r=JSON.parse(File.read(bundle.fetch('renderFile')));f=r.fetch('frozen');DirectImagePlan.validate(f)
read=->(path){File.binread(path)};sha=->(bytes){Digest::SHA256.hexdigest(bytes)}
reference=read.call(bundle.fetch('referenceFile'));product=bundle['productFile']&&read.call(bundle['productFile']);raise 'source changed' unless sha.call(reference)==f.dig('binding','sourceHash');raise 'product changed' unless (product&&sha.call(product))==f.dig('binding','productHash')
bg=read.call(bundle.fetch('backgroundFile'));raise 'background changed' unless sha.call(bg)==r.fetch('backgroundHash');layout=r.fetch('proposal').fetch('layout');lh=ReferenceAnchorReview.fingerprint(layout);raise 'layout changed' unless lh==r.dig('contract','textLayoutHash');raise 'contract changed' unless ReferenceAnchorReview.fingerprint(r['contract'])==r['contractHash']
assets=r['contract'].fetch('sceneAssets').to_h do |a|
 b=read.call(bundle.fetch('sceneFiles').fetch(a['id']));raise 'scene changed' unless sha.call(b)==a['sha256'];[a['id'],{'base64'=>Base64.strict_encode64(b),'mime'=>a['mime']||'image/png'}]
end
binding={'sourceHash'=>f['binding']['sourceHash'],'backgroundHash'=>r['backgroundHash'],'layoutHash'=>lh,'contractHash'=>r['contractHash'],'outputSize'=>f['trace']['expectedDimensions']}
review_paths={'reference-anchor-audits/'+binding['sourceHash']+'/'+lh+'.json'=>bundle.fetch('anchorReview'),'background-geometry-audits/'+BackgroundGeometryReview.key(binding['sourceHash'],binding['backgroundHash'],layout,binding['outputSize'])+'.json'=>bundle.fetch('geometryReview'),'deterministic-decoration-audits/'+ReferenceAnchorReview.fingerprint(binding)+'.json'=>bundle.fetch('decorationReview')}
proposal=r.fetch('proposal')
if f['options']['mode']=='custom'
 raise 'custom copy changed' unless layout['text'].map{|t|t['text']}.join==f['options']['customCopy']
 proposal['copyDecisions']=layout['evidence']['sourceBlocks'].map{|b|{'id'=>b['id'],'sourceText'=>b['sourceText'],'action'=>'remove','text'=>'','reason'=>'Source copy replaced by exact user-supplied custom copy','authorization'=>'selected custom mode and supplied exact customCopy'}}
 proposal['userCopyDecision']={'action'=>'retain-verbatim','text'=>f['options']['customCopy'],'renderIndices'=>(0...layout['text'].length).to_a}
end
decisions=proposal.fetch('copyDecisions');raise 'unresolved roles' if decisions.any?{|d|d['action']=='pending'};ids=layout.fetch('evidence').fetch('sourceBlocks').map{|b|b['id']};raise 'incomplete source inventory' unless decisions.map{|d|d['id']}.sort==ids.sort
decisions.each{|d|next if d['action']=='remove';t=layout['text'][d.fetch('renderIndex')];raise 'decision/render mismatch' unless t&&t['text']==d['text']};
provenance={'kind'=>'reviewed-local-material-intake','authority'=>bundle['authority'],'modelCalls'=>0,'notNewModelGeneration'=>true,'sourceHash'=>binding['sourceHash'],'productHash'=>f['binding']['productHash'],'layoutHash'=>lh,'backgroundHash'=>binding['backgroundHash'],'sceneHashes'=>r['contract']['sceneAssets'].to_h{|a|[a['id'],a['sha256']]},'reviewedOutputHash'=>bundle.fetch('reviewedOutputHash')}
pkg={'sourceHash'=>binding['sourceHash'],'productHash'=>f['binding']['productHash'],'options'=>f['options'],'proposal'=>proposal,'background'=>{'base64'=>Base64.strict_encode64(bg),'mime'=>'image/png'},'backgroundHash'=>binding['backgroundHash'],'backgroundOrigin'=>'local-deterministic-decoration','decoration'=>{'contract'=>r['contract'],'contractHash'=>r['contractHash'],'assets'=>assets},'visualAcceptance'=>'parent-reviewed-local-material','fixtureOnly'=>false,'materialProvenance'=>provenance}
key=f['binding']['requestHash'];version=ReferenceAnchorReview.fingerprint(provenance);versions=File.join(root,'reviewed-asset-versions',key);destination=File.join(versions,version)
raise 'version already exists; inspect receipt before retry' if File.exist?(destination)
Dir.mktmpdir('reviewed-intake-') do |stage|
 review_paths.each{|rel,source|target=File.join(stage,rel);FileUtils.mkdir_p(File.dirname(target));FileUtils.cp(source,target)}
 cache=File.join(stage,'product-asset-cache',key);FileUtils.mkdir_p(cache);File.write(File.join(cache,'package.json'),JSON.generate(pkg));File.write(File.join(stage,'frozen.json'),JSON.generate(f))
 validator=<<~CODE
 require #{File.join(root,'product-asset-provider').inspect}
 [[ReferenceAnchorReview,'reference-anchor-audits'],[BackgroundGeometryReview,'background-geometry-audits'],[DeterministicDecorationReview,'deterministic-decoration-audits']].each{|m,n|m.send(:remove_const,:ROOT);m.const_set(:ROOT,File.join(#{stage.inspect},n))}
 f=JSON.parse(File.read(#{File.join(stage,'frozen.json').inspect}));raise 'validation failed' unless ProductAssetProvider.cache(f,#{File.join(stage,'product-asset-cache').inspect},mock:false);puts 'review gates passed'
 CODE
 log,status=Open3.capture2e('/usr/bin/ruby','-e',validator);raise log unless status.success?
 review_paths.each{|rel,_|live=File.join(root,rel);raise 'conflicting immutable review' if File.file?(live)&&read.call(live)!=read.call(File.join(stage,rel))}
 FileUtils.mkdir_p(destination);FileUtils.cp_r(File.join(cache,'package.json'),destination);File.write(File.join(destination,'provenance.json'),JSON.pretty_generate(provenance));File.write(File.join(destination,'frozen.json'),JSON.pretty_generate(f));File.binwrite(File.join(destination,'reference-input'),reference);File.binwrite(File.join(destination,'product-input'),product) if product
 review_paths.each{|rel,_|target=File.join(root,rel);next if File.file?(target);FileUtils.mkdir_p(File.dirname(target));tmp=target+'.intake.tmp';FileUtils.cp(File.join(stage,rel),tmp);File.rename(tmp,target)}
 active=File.join(root,'product-asset-cache',key);FileUtils.mkdir_p(active);target=File.join(active,'package.json');oldhash=File.file?(target) ? sha.call(read.call(target)) : nil;FileUtils.cp(target,File.join(destination,'previous-package.json')) if oldhash
 tmp=target+'.intake.tmp';File.write(tmp,JSON.generate(pkg));File.rename(tmp,target)
 raise 'live validation failed' unless ProductAssetProvider.cache(f,File.join(root,'product-asset-cache'),mock:false)
 receipt={'state'=>'activated-reviewed-local-material','requestHash'=>key,'version'=>version,'previousPackageHash'=>oldhash,'activePackageHash'=>sha.call(read.call(target)),'versionDirectory'=>destination,'modelCalls'=>0,'outputImageImported'=>false,'normalEntryMustCompose'=>true,'provenance'=>provenance};File.write(File.join(destination,'receipt.json'),JSON.pretty_generate(receipt));puts JSON.generate(receipt)
end
