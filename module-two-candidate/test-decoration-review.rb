require_relative 'product-asset-provider'
require 'tmpdir'
checks=[]
Dir.mktmpdir do |dir|
 DeterministicDecorationReview.send(:remove_const,:ROOT);DeterministicDecorationReview.const_set(:ROOT,dir)
 bytes=File.binread('diagnostics/deterministic-decoration/render.png');layout={'text'=>[]};c={'sourceHash'=>'fixture','textLayoutHash'=>ReferenceAnchorReview.fingerprint(layout),'canvas'=>{'width'=>360,'height'=>440},'sceneAssets'=>[{'id'=>'s','sha256'=>Digest::SHA256.hexdigest(bytes),'width'=>360,'height'=>440}]}
 p={'sourceHash'=>'fixture','backgroundHash'=>'output-fixture','proposal'=>{'layout'=>layout},'decoration'=>{'contract'=>c,'contractHash'=>ReferenceAnchorReview.fingerprint(c),'assets'=>{'s'=>{'base64'=>Base64.strict_encode64(bytes)}}}}
 reject=lambda do |q|
 begin;DeterministicDecorationReview.require!(q);raise 'unexpected acceptance';rescue=>e;raise if e.message=='unexpected acceptance';checks<<e.message;end
 end
 reject.call(p)
 binding={'sourceHash'=>p['sourceHash'],'backgroundHash'=>p['backgroundHash'],'layoutHash'=>c['textLayoutHash'],'contractHash'=>p['decoration']['contractHash'],'outputSize'=>[360,440]}
 File.write(File.join(dir,ReferenceAnchorReview.fingerprint(binding)+'.json'),JSON.generate({'binding'=>binding,'reviewState'=>'verified-local-review','cleanScenesReviewed'=>true,'sceneAction'=>'rebuild-environment','sceneActionVerdict'=>'pass','evidenceAndMappingReviewed'=>true}))
 DeterministicDecorationReview.require!(p);checks<<'exact trusted local review accepted in temporary fixture directory'
 q=Marshal.load(Marshal.dump(p));q['options']={'module'=>'product-replacement','sceneMode'=>'keep'};reject.call(q)
 review_path=File.join(dir,ReferenceAnchorReview.fingerprint(binding)+'.json');review=JSON.parse(File.read(review_path));review.delete('sceneAction');File.write(review_path,JSON.generate(review));reject.call(p);review['sceneAction']='rebuild-environment';File.write(review_path,JSON.generate(review))
 q=Marshal.load(Marshal.dump(p));q['backgroundHash']='changed';reject.call(q)
 q=Marshal.load(Marshal.dump(p));q['decoration']['contract']['canvas']['width']=361;reject.call(q)
 q=Marshal.load(Marshal.dump(p));q['decoration']['assets']['s']['base64']=Base64.strict_encode64('bad');reject.call(q)
end
File.write('diagnostics/deterministic-decoration/review-tests.json',JSON.pretty_generate(checks));puts checks
