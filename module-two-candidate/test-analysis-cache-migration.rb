require_relative 'migrate-authorized-analysis-cache'
n=0;check=lambda{|v|raise 'migration assertion failed' unless v;n+=1}
o={'mode'=>'ai-rewrite','brandName'=>'','productParameters'=>''}
check.call(AuthorizedAnalysisMigration.copy('Halogen Light',3,o)=='Comparison View B')
check.call(AuthorizedAnalysisMigration.copy('LED Light',2,o)=='Comparison View A')
check.call(AuthorizedAnalysisMigration.copy('Halogen Light',3,o.merge('productParameters'=>'Halogen'))=='Halogen Light')
check.call(AuthorizedAnalysisMigration.copy('LED Light',2,o.merge('productParameters'=>'LED H11'))=='LED Light')
check.call(AuthorizedAnalysisMigration.copy('My HALOGEN',3,o.merge('mode'=>'custom'))=='My HALOGEN')
check.call(AuthorizedAnalysisMigration.copy('Other label',0,o)=='Other label')
schema=ReferenceProvider.schema
check.call(schema['properties']['text']['items']['properties'].key?('lineHeightPx'))
check.call(!schema['properties']['text']['items']['properties'].key?('lineHeight'))
dir=File.join(__dir__,'diagnostics/compact-analysis-authorized-20261018');old=JSON.parse(File.read(dir+'/plan.json'))
begin;AuthorizedAnalysisMigration.migrate(old,'{}');raise 'unexpected success';rescue ArgumentError,RuntimeError=>e;raise if e.message=='unexpected success';n+=1;end
validated=JSON.parse(File.read(dir+'/migrated-font-validated.json'));check.call(validated['fontChecks'].all?{|r|r['passed']&&r['measuredHeight']<=r['boxHeight']})
raw_plan=Marshal.load(Marshal.dump(validated['plan']));raw_plan['text'].each{|t|t.delete('mode')};check.call(ReferenceProvider.layout(raw_plan,old['frozen'])==validated['plan'])
background=ReferenceProvider.prepare(old['frozen'],'background',validated['plan']);check.call(background['liveEnabled']==false&&background['binding']['layoutHash']==ReferenceProvider.hash(validated['plan']))
File.write(dir+'/background-plan-UNAUTHORIZED.json',JSON.pretty_generate(background))
state={'state'=>'awaiting-background-authorization','analysisApproval'=>'consumed','analysisSourceRequestHash'=>old['binding']['requestHash'],'layoutVersion'=>ReferenceProvider::LAYOUT_VERSION,'layoutHash'=>ReferenceProvider.hash(validated['plan']),'backgroundRequestHash'=>background['binding']['requestHash'],'backgroundAuthorized'=>false,'backgroundCalls'=>0,'newModelCalls'=>0,'migrationChecks'=>n,'fontBlocksPassed'=>validated['fontChecks'].size,'globalPausePresent'=>LiveRequestPause.active?}
File.write(dir+'/offline-continuation.json',JSON.pretty_generate(state));puts JSON.pretty_generate(state)
