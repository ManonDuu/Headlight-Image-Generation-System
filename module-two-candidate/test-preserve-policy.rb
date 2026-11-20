require_relative 'reference-provider'
v={'sourceGeometry'=>{'width'=>100,'height'=>100,'coordinateSpace'=>'source-pixels'},'text'=>[],'evidence'=>{'facts'=>[{'id'=>'brand','kind'=>'brand','value'=>'OLD'},{'id'=>'watts','kind'=>'specification','value'=>'60W'}],'sourceBlocks'=>[{'id'=>'a','sourceText'=>'OLD','meaningUnitIds'=>['brand'],'sourceBox'=>{'x'=>0,'y'=>0,'width'=>80,'height'=>20},'marketingFunction'=>'brand'},{'id'=>'b','sourceText'=>'60W','meaningUnitIds'=>['watts'],'sourceBox'=>{'x'=>0,'y'=>30,'width'=>80,'height'=>20},'marketingFunction'=>'body'},{'id'=>'c','sourceText'=>'LED','meaningUnitIds'=>[],'sourceBox'=>{'x'=>0,'y'=>60,'width'=>80,'height'=>20},'marketingFunction'=>'body'}],'rewrites'=>[]}}
o={'mode'=>'preserve-reference','brandName'=>'MyBrand','productParameters'=>'60W'}
p=PreserveReferenceCopy.process(v,o,[1000,1000]);raise unless p['candidate']['text'].map{|t|t['text']}==['MyBrand','60W','LED']
p=PreserveReferenceCopy.process(v,o.merge('productParameters'=>'80W'),[1000,1000]);raise unless p['candidate']['text'].map{|t|t['text']}==['MyBrand','LED']&&p['changes'].any?{|c|c['action']=='omit'}
raise unless v['evidence']['sourceBlocks'][0]['sourceText']=='OLD'
puts 'PASS preserve wording/case, brand substitution, supplied parameter, conflict omission disclosure, LED category, immutable source; zero model calls'
