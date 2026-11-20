require 'net/http';require 'json'
root=File.expand_path(__dir__);id='5fa7f54a7d1e7a831d292595'
rows=[
 ['visual-input','pass','整体五区','主图及雨雪雾尘四个小图保留，标签对应天气区域。'],
 ['layout','pass','标题、主图、温标及四宫格','保留总体阅读顺序和相对布局，文字清晰，无明显裁切。'],
 ['scene','fail','主图车身朝向','道路/山景明显重构，但主车三分之四视角朝向反转，不符合保留视角要求。'],
 ['proof','fail','雪/尘小图车灯','参考图可见亮灯和光束，新图雪/尘小图灯光表现显著减弱或缺失；功能证据未保留。'],
 ['copy','fail','标题与副标题','IP68 WATERPROOF和Not Blinding Oncoming Drivers沿用；未见实质改写，继续含未经支持性能声明。'],
 ['brand','pass','全部叠加文字','未发现新增或保留明确文字品牌；不能据此认定车身造型无品牌识别。'],
 ['parameters','fail','标题及温标','参数为空仍保留IP68、-40°C及+80°C，违反不得继承未提供参数。'],
 ['palette','pass','文字/边框/温标','保留白字蓝色装饰及红蓝功能温标，未观察到全图色罩。'],
 ['module-scope','unverified','车身与灯组','没有独立目标产品材料；只能确认未执行产品替换，无法认证所有产品结构保持。'],
 ['uncertainty','fail','性能文案和数值','模型没有舍弃不确定的性能声明，不能认定语义合规。']]
d=rows.map{|rid,v,loc,n|{'ruleId'=>rid,'verdict'=>v,'note'=>n,'evidence'=>[{'kind'=>'visual-observation','location'=>loc}]}}
h=Net::HTTP.new('127.0.0.1',8773,nil);h.max_retries=0;h.open_timeout=5;h.read_timeout=10;s=JSON.parse(h.get('/api/session').body)
r=Net::HTTP::Post.new('/api/review');r['Origin']='http://127.0.0.1:8773';r['Content-Type']='application/json';r['X-Session-Token']=s['token'];r.body=JSON.generate({'id'=>id,'decisions'=>d});x=h.request(r);raise "review failed #{x.code}" unless x.code=='200'
a=JSON.parse(x.body);File.write(root+'/diagnostics/direct-awaiting-acceptance/visual-review.json',JSON.pretty_generate(a['review']))
puts JSON.generate({task:id,visualAcceptance:a['visualAcceptance'],reviewCounts:d.group_by{|z|z['verdict']}.transform_values(&:size),modelCalls:0})
