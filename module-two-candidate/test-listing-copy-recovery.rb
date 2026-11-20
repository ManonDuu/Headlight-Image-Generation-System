require_relative 'product-asset-provider'
require 'json'
root=__dir__;plan=JSON.parse(File.read(root+'/diagnostics/listing-canbus-preflight/analysis-plan-UNAUTHORIZED.json'));raw=File.read(root+'/live-attempts/listing-Sentinel_9ce2af725860819189d6a06874e32720/analysis/response.raw.json')
result=ProductAssetProvider.parse_analysis(plan,200,raw)
raise 'unsupported claims retained' unless result['layout']['text'].empty?
bg=ProductAssetProvider.prepare(plan['productFrozen'],'background',result)
File.write(root+'/diagnostics/approved-listing-20261018/background-plan.json',JSON.pretty_generate(bg))
prompt=JSON.parse(bg['body'])['contents'][0]['parts'][0]['text']
raise 'source evidence leaked into background instructions' if prompt.match?(/99%|CANBUS|NEW GENERATION|Ensure Models Compatibility/i)
v=JSON.parse(JSON.parse(raw)['candidates'][0]['content']['parts'][0]['text']);v.delete('productSlot');options=plan['productFrozen']['options']
# Two distinct source IDs with the same role are valid; positional fallback is not.
v['text']=v['text'].first(2);v['text'].each{|t|t['text']='LED';t['role']='title'}
e=v['evidence'];e['sourceBlocks']=e['sourceBlocks'].first(2);e['sourceBlocks'].each{|b|b['sourceText']='LED'};e['rewrites']=e['rewrites'].first(2)
out=AnalysisOutputContract.process(v,options,[1122,1402],[1638,2048]);raise 'category or same-role blocks lost' unless out['candidate']['text'].map{|t|t['text']}==['LED','LED']
v['text'][0]['text']='';out=AnalysisOutputContract.process(v,options,[1122,1402],[1638,2048]);raise 'empty label retained' unless out['candidate']['text'].size==1&&out['candidate']['evidence']['rewrites'][1]['renderIndex']==0
v['text'][0]['text']='My CANBUS 99%';custom=options.merge('mode'=>'custom');out=AnalysisOutputContract.process(v,custom,[1122,1402],[1638,2048]);raise 'custom copy altered' unless out['candidate']['text'][0]['text']=='My CANBUS 99%'
puts JSON.generate({checks:6,modelCalls:0,reusedAnalysis:true,finalText:result['layout']['text'],productSlot:result['productSlot'],backgroundRequestHash:bg['binding']['requestHash']})
