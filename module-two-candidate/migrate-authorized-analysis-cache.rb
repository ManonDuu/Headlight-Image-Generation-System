# Explicit migration of ONE known response, never heuristic legacy interpretation.
require_relative 'bridge-server'
module AuthorizedAnalysisMigration
 REQUEST='6eb1f70ea253138b8871736fb32328a624d127623265ec49136815f636431410'
 RESPONSE='561e5bc868f9e1e2b1464c7ad9b99930ba8d8d95537509a8c487874a9d569341'
 def self.copy(text,index,options)
  return text unless options['mode']=='ai-rewrite'
  # Reviewed visual roles for this exact four-block response. Not a universal classifier.
  provided=[options['brandName'],options['productParameters']].compact.join(' ')
  category=index==2 ? 'LED' : 'Halogen'
  return text if provided.match?(/\b#{category}\b/i)
  {1=>'Compare the lighting views',2=>'Comparison View A',3=>'Comparison View B'}.fetch(index,text)
 end
 def self.migrate(plan,raw)
  raise 'legacy version/request mismatch' unless plan.dig('binding','version')=='reference-assets-20261018.2'&&plan.dig('binding','requestHash')==REQUEST
  raise 'only reviewed response may be migrated' unless Digest::SHA256.hexdigest(raw)==RESPONSE
  response=JSON.parse(raw);value=JSON.parse(response['candidates'][0]['content']['parts'].reject{|p|p['thought']}.first['text'])
  raise 'unexpected legacy rows' unless value['text'].size==4&&value['text'].map{|t|t['lineHeight']}==[1.2,1.3,1.2,1.2]&&value['text'].map{|t|t['fontSize']}==[72,44,72,72]
  log=[]
  value['text'].each_with_index do |t,i|
   old=t.delete('lineHeight');t['lineHeightPx']=(old*t['fontSize']).round(3)
   original=t['text'];t['text']=copy(original,i,plan['frozen']['options'])
   log<<{'row'=>i,'lineHeightMultiplierExplicitlyReviewed'=>old,'lineHeightPx'=>t['lineHeightPx'],'originalText'=>original,'correctedText'=>t['text'],'reason'=>'Known cache migration under user instruction; pixel conversion explicit. Neutral labels only where category not supplied; no new product facts.'}
  end
  value['layoutVersion']=ReferenceProvider::LAYOUT_VERSION
  normalized=ReferenceProvider.layout(value,plan['frozen'])
  {'migrationVersion'=>'authorized-cache-migration-1','fromVersion'=>plan['binding']['version'],'toLayoutVersion'=>ReferenceProvider::LAYOUT_VERSION,'sourceRequestHash'=>REQUEST,'sourceResponseHash'=>RESPONSE,'plan'=>normalized,'changes'=>log,'modelCalls'=>0,'state'=>'awaiting-local-font-preflight'}
 end
end
if __FILE__==$0
 dir=File.join(__dir__,'diagnostics/compact-analysis-authorized-20261018')
 plan=JSON.parse(File.read(dir+'/plan.json'));raw=File.read(File.join(__dir__,'live-attempts/compact-analysis-Sentinel_d41e04709adc81918ce0e25a4c39a85d/response.raw.json'))
 result=AuthorizedAnalysisMigration.migrate(plan,raw)
 File.write(dir+'/explicit-migration.json',JSON.pretty_generate(result));puts JSON.generate(result.reject{|k,_|k=='plan'})
end
