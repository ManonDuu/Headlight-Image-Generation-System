require_relative 'direct-image-plan'
source=File.binread('/Users/manrongdu/Downloads/71efzt2fH8L._AC_SL1500_.jpg')
raise 'source changed' unless Digest::SHA256.hexdigest(source)=='c01d6d480029ae562fa12d12a0521c949fe01a4185525527d66321d68c2fa671'
o={'businessSpec'=>DirectImagePlan::SPEC,'module'=>'reference-reconstruction','mode'=>'custom','layoutMode'=>'auto-layout','layoutTone'=>'adjust-color','color'=>'#2864C8','customCopy'=>"Brighter Road Visibility\nLED\nHalogen",'brandName'=>'','productParameters'=>'','output'=>{'aspectRatio'=>'1:1','imageSize'=>'2K'}}
plan=DirectImagePlan.prepare(source,nil,o,mock:false,input_origin:'user')
DirectImagePlan.validate(plan)
raise 'wrong call allowance' unless plan['binding']['maxRequests']==1&&plan['binding']['analysisCalls']==0&&plan['binding']['retries']==0&&plan['binding']['conservativeMicroUSD']<=500000
puts JSON.generate(plan)
