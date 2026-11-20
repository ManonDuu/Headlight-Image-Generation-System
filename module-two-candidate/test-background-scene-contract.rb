require_relative 'product-asset-provider'
out=File.join(__dir__,'diagnostics/scene-scope-repair');FileUtils.mkdir_p(out);checks=[];ok=lambda{|v,m|raise m unless v;checks<<m}
# Reuse actual frozen inputs, but never overwrite or execute old authorized requests.
old1=JSON.parse(File.read('diagnostics/two-backgrounds-20261018/step1-plan.json'));old2=JSON.parse(File.read('diagnostics/two-backgrounds-20261018/step2-plan.json'))
new1=ReferenceProvider.prepare(old1['frozen'],'background',old1['layout']);new2=ProductAssetProvider.prepare(old2['productFrozen'],'background',old2['proposal'])
[[old1,new1],[old2,new2]].each_with_index do |(old,p),i|
 b=JSON.parse(p['body']);text=b['contents'][0]['parts'][0]['text'];prior=JSON.parse(old['body'])
 ok.call(b['contents'][0]['parts'][1]==prior['contents'][0]['parts'][1],'same original reference only '+i.to_s)
 ok.call(b['generationConfig']==prior['generationConfig']&&p['binding']['retries']==0&&!p['liveEnabled'],'same bounded config; disabled '+i.to_s)
 ok.call(p['binding']['requestHash']!=old['binding']['requestHash'],'new prompt invalidates old approval '+i.to_s)
 ok.call(!text.include?('Frozen shared constraints:')&&!text.include?('fontSize')&&!text.include?('"text":"')&&!text.include?('sourceBox'),'no copy/font/raw model source boxes in background '+i.to_s)
 ok.call(text.include?('ENVIRONMENT REBUILD:')&&text.include?('GEOMETRY CONTRACT'),'explicit scoped reconstruction '+i.to_s)
 File.write(out+"/module#{i+1}-plan-NOT-AUTHORIZED.json",JSON.pretty_generate(p));File.write(out+"/module#{i+1}-prompt.txt",text)
end
cases=[['deer-comparison',old1['frozen'],old1['layout'],nil],['canbus-change',old2['productFrozen'],old2['proposal']['layout'],old2['proposal']['productSlot']]]
f=Marshal.load(Marshal.dump(old2['productFrozen']));f['options']['sceneMode']='keep';cases<<['canbus-keep',f,old2['proposal']['layout'],old2['proposal']['productSlot']]
# Different real source category, copy-free background only; not a claim of new geometry review.
weather=File.binread('assets/81gMZuoRq6L._AC_SL1500_.jpg');opts=old1['frozen']['options'].merge('mode'=>'remove-all-copy');wf=DirectImagePlan.prepare(weather,nil,opts);wl={'layoutVersion'=>ReferenceProvider::LAYOUT_VERSION,'text'=>[]};cases<<['weather-five-panels',wf,wl,nil]
h=JSON.parse(File.read('diagnostics/today-real-input-readiness/product-replacement-live-plan.json'));cases<<['historical-product',h,{'text'=>[]},{'x'=>200,'y'=>400,'width'=>1000,'height'=>1700}]
results=cases.map do |name,f,l,slot|
 compiled=BackgroundSceneContract.compile(f,l,product_slot:slot);c=compiled['contract'];text=compiled['instruction'];change=f['options']['module']=='reference-reconstruction'||f['options']['sceneMode']=='change'
 ok.call((c['sceneAction']=='rebuild-environment')==change,'scene selection '+name)
 ok.call(change ? !c['redesignDomains'].empty?&&!text.include?('ENVIRONMENT KEEP:') : c['redesignDomains'].empty?&&!text.include?('ENVIRONMENT REBUILD:'),'no simultaneous keep/rebuild '+name)
 ok.call(c['textExclusionZones'].map{|z|z['box']}==l['text'].map{|t|t['box']},'text anchor geometry unchanged '+name)
 ok.call(c['renderedText']==false&&text.include?('compatibility claims')&&text.include?('CANBUS'),'clean copy layer and CANBUS default scope '+name)
 ok.call(text.include?('same new environment')&&text.include?('camera side'),'paired evidence and viewpoint preserved '+name)
 File.write(out+'/'+name+'-prompt.txt',text);{'case'=>name,'contract'=>c,'sourceHash'=>f['binding']['sourceHash'],'checks'=>'passed','newModelCalls'=>0}
end
ok.call(new1['layout']==old1['layout']&&new2['proposal']['layout']==old2['proposal']['layout'],'both verified layouts unchanged')
ok.call(old2['proposal']['layout']['text'].map{|t|t['text']}==["CANBUS\nREADY"],'module2 allowed output copy stays CANBUS only')
File.write(out+'/regression.json',JSON.pretty_generate({checks:checks,cases:results,apiCalls:0,modelCalls:0,visualGenerationNotTested:true}));puts JSON.generate({checks:checks.size,cases:results.size,modelCalls:0})
