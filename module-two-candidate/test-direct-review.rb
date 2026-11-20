require_relative 'bridge-server'
n=0;ck=lambda{|v|raise 'review assertion failed' unless v;n+=1}
ids=%w[priority visual-input copy parameters brand proof scene layout palette module-scope uncertainty product-identity]
t={'appliedRuleIds'=>ids}
d=ids.map{|id|{'ruleId'=>id,'verdict'=>'pass','note'=>'manual observation','evidence'=>[{'kind'=>'visual-observation','location'=>'panel'}]}}
%w[proof scene layout palette].each do |id|
 a=Marshal.load(Marshal.dump(d));a.find{|x|x['ruleId']==id}['verdict']='fail';r=DirectReview.assess(t,a)
 ck.call(r['overall']=='usable-with-visual-suggestions'&&!r['automaticRework']&&!r['wholeImageRejected'])
end
DirectReview::HARD.each do |id|
 a=Marshal.load(Marshal.dump(d));a.find{|x|x['ruleId']==id}['verdict']='fail';r=DirectReview.assess(t,a)
 ck.call(r['overall']=='hard-issues-require-user-review'&&!r['automaticRework'])
end
a=Marshal.load(Marshal.dump(d));a.find{|x|x['ruleId']=='proof'}['verdict']='serious-expression';r=DirectReview.assess(t,a);ck.call(r['blockingRuleIds']==['proof']&&!r['wholeImageRejected'])
a=Marshal.load(Marshal.dump(d));a.find{|x|x['ruleId']=='parameters'}['verdict']='unverified';ck.call(DirectReview.assess(t,a)['overall']=='hard-checks-unverified')
ck.call(DirectReview.assess(t,d)['automaticVerification']==false)
old=JSON.parse(File.read(File.join(__dir__,'bridge-jobs/5fa7f54a7d1e7a831d292595/state.json')));ck.call(old['visualAcceptance']=='manual-rejected'&&!old.key?('userFeedback'))
feedback=JSON.parse(File.read(File.join(__dir__,'bridge-jobs/5fa7f54a7d1e7a831d292595/user-feedback.json')));ck.call(feedback['overallVisual']=='accepted-by-user'&&!feedback['newGenerationAuthorized'])
puts "PASS #{n} human review rubric and appended feedback checks; model calls 0"
