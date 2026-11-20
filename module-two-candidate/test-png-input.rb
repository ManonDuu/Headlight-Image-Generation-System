require_relative 'bridge-server'
require 'tmpdir'
n=0;ck=lambda{|v,m|raise m unless v;n+=1};reject=lambda{|&f|begin;f.call;raise 'invalid accepted';rescue=>e;raise if e.message=='invalid accepted';n+=1;end}
root=File.expand_path(__dir__);png=File.binread(root+'/assets/exec-2f5b9ebc-8a90-43e8-aaf9-c4a4c0117844.png');jpeg=File.binread(root+'/assets/81gMZuoRq6L._AC_SL1500_.jpg')
i=InputImage.inspect(png);ck.call(i['mime']=='image/png'&&i['dimensions']==[1122,1402],'PNG decode dimensions')
ck.call(InputImage.inspect(jpeg)['mime']=='image/jpeg','JPEG preserved')
["bad",png[0,30],png+"junk",InputImage::PNG+('a'*4194304)].each{|b|reject.call{InputImage.inspect(b)}}
bad=png.dup;bad.setbyte(35,bad.getbyte(35)^1);reject.call{InputImage.inspect(bad)}
old=JSON.parse(File.read(root+'/diagnostics/direct-awaiting-acceptance/plan-local.json'));o=old['options'].merge('businessSpec'=>DirectImagePlan::SPEC)
p=DirectImagePlan.prepare(png,nil,o);ck.call(DirectImagePlan.validate(p),'PNG frozen validation');part=JSON.parse(p['body'])['contents'][0]['parts'][2]['inlineData']
ck.call(part['mimeType']=='image/png'&&Base64.strict_decode64(part['data'])==png,'PNG original inline bytes')
ck.call(p['binding']['sourceHash']==Digest::SHA256.hexdigest(png)&&p['binding']['budgetMicroUSD']==260000,'PNG hash/budget')
ck.call(JSON.parse(p['body'])['contents'][0]['parts'][0]['text']==JSON.parse(DirectImagePlan.prepare(jpeg,nil,o)['body'])['contents'][0]['parts'][0]['text'],'business rules unchanged by format')
bad=Marshal.load(Marshal.dump(p));body=JSON.parse(bad['body']);body['contents'][0]['parts'][2]['inlineData']['mimeType']='image/jpeg';bad['body']=JSON.generate(body);reject.call{DirectImagePlan.validate(bad)}
[jpeg,png].each do |r|
 q=r==jpeg ? png : jpeg;opts=o.merge('module'=>'product-replacement','productName'=>'OFFLINE fixture','sceneMode'=>'keep');z=DirectImagePlan.prepare(r,q,opts);ck.call(DirectImagePlan.validate(z),'mixed roles freeze');ps=JSON.parse(z['body'])['contents'][0]['parts'];ck.call(ps[2]['inlineData']['mimeType']==InputImage.inspect(r)['mime']&&ps[4]['inlineData']['mimeType']==InputImage.inspect(q)['mime'],'per-role MIME');ck.call(z['binding']['budgetMicroUSD']==270000,'dual budget unchanged')
end
Dir.mktmpdir do |d|
 b=Bridge.new(mock:true,data:d,analysis_store:d+'/empty');s=b.freeze_direct(o.merge('imageBase64'=>Base64.strict_encode64(png),'sourceHash'=>Digest::SHA256.hexdigest(png),'budgetMicroUSD'=>260000));ck.call(File.binread(d+'/'+s['id']+'/reference.png')==png&&!File.exist?(d+'/'+s['id']+'/reference.jpg'),'stored as original PNG')
 reject.call{b.direct_input({'imageBase64'=>Base64.strict_encode64(png),'sourceHash'=>'wrong'})}
end
puts "PASS #{n} PNG validation/MIME/bytes/roles/budgets/freeze checks; external API calls 0"
