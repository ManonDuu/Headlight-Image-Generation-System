require_relative 'product-asset-provider'
require 'tmpdir'
out='diagnostics/background-geometry';FileUtils.mkdir_p(out)
source=Digest::SHA256.file('diagnostics/final-readiness/deer-road.png').hexdigest;farm=Digest::SHA256.file(out+'/farm-background.png').hexdigest;size=[1122,1402]
layout={'text'=>[{'text'=>'Ultra Brightness','box'=>{'x'=>436,'y'=>112,'width'=>591,'height'=>60}},{'text'=>'CANBUS ready','box'=>{'x'=>580,'y'=>229,'width'=>464,'height'=>30}},{'text'=>'Other','box'=>{'x'=>96,'y'=>845,'width'=>110,'height'=>35}}]}
edge=lambda{|x,y,r,b|{'left'=>[x,x],'top'=>y.is_a?(Array) ? y : [y,y],'right'=>[r,r],'bottom'=>b.is_a?(Array) ? b : [b,b]}}
regions=[['header','header',edge.call(0,0,1122,203)],['upper','panel',edge.call(45,[204,206],1078,[799,800])],['lower','panel',edge.call(45,[825,827],1078,[1361,1363])],['lower-label','container',edge.call(46,827,298,893)]].map{|id,kind,e|{'id'=>id,'kind'=>kind,'measurementState'=>'reviewed','expectedEdges'=>e,'observedEdges'=>Marshal.load(Marshal.dump(e))}}
a={'sourceHash'=>source,'backgroundHash'=>source,'layoutHash'=>ReferenceAnchorReview.fingerprint(layout),'outputSize'=>size,'reviewState'=>'verified-local-review','verdict'=>'pass','reviewMethod'=>'manual-pixel-geometry','sourceStructureReviewed'=>true,'backgroundStructureReviewed'=>true,'inventoryComplete'=>true,'sourcePanelCount'=>2,'backgroundPanelCount'=>2,'structure'=>'framed','regions'=>regions,'textOwners'=>%w[header upper lower-label].each_with_index.map{|id,i|{'renderIndex'=>i,'regionId'=>id,'ownershipReviewed'=>true}},'fixtureOnly'=>true,'scope'=>'geometry only; source-as-background is NOT a clean-layer approval'}
shifted=Marshal.load(Marshal.dump(a));shifted['backgroundHash']=farm;shifted['regions'][1]['observedEdges'].merge!('top'=>[178,181],'bottom'=>[768,771]);shifted['regions'][2]['observedEdges'].merge!('top'=>[791,794],'bottom'=>[1344,1346]);shifted['verdict']='fail'
canbus=Digest::SHA256.file('assets/listing-canbus-reference/reference.png').hexdigest
unframed=a.merge('sourceHash'=>canbus,'backgroundHash'=>canbus,'structure'=>'unframed','sourcePanelCount'=>0,'backgroundPanelCount'=>0,'regions'=>[],'textOwners'=>[],'unframedClearanceReviewed'=>true)
checks=[];ok=lambda{|v,m|raise m unless v;checks<<m};valid=lambda{|v,s=source,b=source,l=layout,z=size|BackgroundGeometryReview.valid?(v,s,b,l,z)}
ok.call(valid.call(a),'same original scene geometry positive control (not clean-background approval)')
ok.call(!valid.call(shifted,source,farm),'actual farm displacement rejected')
v=Marshal.load(Marshal.dump(shifted));v['verdict']='pass';ok.call(!valid.call(v,source,farm),'mismatch rejected even if pass flag incorrectly set')
ok.call(valid.call(unframed,canbus,canbus),'reviewed truly unframed case allowed without fictitious panels')
{'incomplete inventory'=>lambda{|v|v['inventoryComplete']=false},'missing panel'=>lambda{|v|v['regions'].reject!{|r|r['id']=='lower'}},'missing review'=>lambda{|v|v['reviewState']='missing'},'uncertain verdict'=>lambda{|v|v['verdict']='uncertain'},'rough detector is not review'=>lambda{|v|v['reviewMethod']='low-texture-bands'},'background hash mutation'=>lambda{|v|v['backgroundHash']='0'*64},'source hash mutation'=>lambda{|v|v['sourceHash']='0'*64},'layout hash mutation'=>lambda{|v|v['layoutHash']='0'*64},'dimensions mutation'=>lambda{|v|v['outputSize']=[1122,1401]},'missing container ownership'=>lambda{|v|v['textOwners'].pop},'unreviewed region'=>lambda{|v|v['regions'][0]['measurementState']='candidate'}}.each{|name,change|v=Marshal.load(Marshal.dump(a));change.call(v);ok.call(!valid.call(v),name+' blocked')}
v=Marshal.load(Marshal.dump(unframed));v.delete('unframedClearanceReviewed');ok.call(!valid.call(v,canbus,canbus),'unframed is not automatic bypass')
Dir.mktmpdir('background-geometry-') do |tmp|
 BackgroundGeometryReview.send(:remove_const,:ROOT);BackgroundGeometryReview.const_set(:ROOT,tmp)
 begin;BackgroundGeometryReview.require!(source,source,layout,size);raise 'missing passed';rescue=>e;raise if e.message=='missing passed';checks<<'missing audit blocks before cached package delivery';end
 key=BackgroundGeometryReview.key(source,source,layout,size);File.write(File.join(tmp,key+'.json'),JSON.generate(a));ok.call(BackgroundGeometryReview.require!(source,source,layout,size)==a,'trusted disk review binds exact tuple')
end
File.write(out+'/fixtures.json',JSON.pretty_generate({layout:layout,original:a,shifted:shifted,unframed:unframed}));File.write(out+'/backend-regression.json',JSON.pretty_generate({checks:checks,modelCalls:0,fixtureApprovalNotInstalled:true}));puts JSON.generate({checks:checks.size,modelCalls:0})
