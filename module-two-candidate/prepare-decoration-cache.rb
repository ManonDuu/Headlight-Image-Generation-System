# Offline intake into the existing two-module cache. No model transport or credentials.
# Usage: ruby prepare-decoration-cache.rb intake.json draft-directory [--install]
# Intake JSON: frozenFile, proposalFile, contractFile, backgroundFile, assets{id:path}.
require_relative 'product-asset-provider'
require 'tmpdir'
if __FILE__==$0
 input=JSON.parse(File.read(ARGV.fetch(0)));destination=File.expand_path(ARGV.fetch(1));install=ARGV[2]=='--install'
 frozen=JSON.parse(File.read(input.fetch('frozenFile')));DirectImagePlan.validate(frozen)
 proposal=JSON.parse(File.read(input.fetch('proposalFile')));contract=JSON.parse(File.read(input.fetch('contractFile')))
 raise 'decoration output differs from selected native size' unless [contract.dig('canvas','width'),contract.dig('canvas','height')]==frozen.dig('trace','expectedDimensions')
 background=File.binread(input.fetch('backgroundFile'));info=InputImage.inspect(background,max_bytes:20*1024*1024)
 raise 'decoration canvas/background size mismatch' unless info['dimensions']==[contract.dig('canvas','width'),contract.dig('canvas','height')]
 assets=input.fetch('assets').map do |id,path|
  bytes=File.binread(path);meta=InputImage.inspect(bytes);a=contract.fetch('sceneAssets').find{|a|a['id']==id}
  raise 'scene file binding mismatch' unless a&&Digest::SHA256.hexdigest(bytes)==a['sha256']&&meta['dimensions']==[a['width'],a['height']]
  [id,{'base64'=>Base64.strict_encode64(bytes),'mime'=>meta['mime']}]
 end.to_h
 raise 'scene asset inventory mismatch' unless assets.keys.sort==contract['sceneAssets'].map{|a|a['id']}.sort
 package={'sourceHash'=>frozen.dig('binding','sourceHash'),'productHash'=>frozen.dig('binding','productHash'),'options'=>frozen['options'],'proposal'=>proposal,'background'=>{'base64'=>Base64.strict_encode64(background),'mime'=>info['mime']},'backgroundHash'=>Digest::SHA256.hexdigest(background),'backgroundOrigin'=>'local-deterministic-decoration','decoration'=>{'contract'=>contract,'contractHash'=>ReferenceAnchorReview.fingerprint(contract),'assets'=>assets},'visualAcceptance'=>'not-evaluated','fixtureOnly'=>input['fixtureOnly']==true}
 FileUtils.mkdir_p(destination);File.write(File.join(destination,'package-draft.json'),JSON.pretty_generate(package))
 raise 'offline fixture cannot be installed as production cache' if install&&package['fixtureOnly']
 Dir.mktmpdir('decoration-intake-') do |root|
  folder=File.join(root,frozen['binding']['requestHash']);Dir.mkdir(folder);File.write(File.join(folder,'package.json'),JSON.generate(package))
  # Requires independently reviewed local scene, anchor and background records.
  validated=ProductAssetProvider.cache(frozen,root,mock:package['fixtureOnly'])
  if install
   target=File.join(__dir__,'product-asset-cache',frozen['binding']['requestHash']);raise 'existing cache protected; review replacement explicitly' if File.exist?(target)
   FileUtils.mkdir_p(File.dirname(target));stage=Dir.mktmpdir('.decoration-staging-',File.dirname(target))
   begin;File.write(File.join(stage,'package.json'),JSON.pretty_generate(validated));File.rename(stage,target);ensure;FileUtils.rm_rf(stage) if File.exist?(stage);end
  end
  puts JSON.generate({state:install ? 'installed-existing-cache' : 'validated-offline-draft',requestHash:frozen['binding']['requestHash'],sceneAssets:assets.keys,modelCalls:0,workbenchOptionsUnchanged:true})
 end
end
