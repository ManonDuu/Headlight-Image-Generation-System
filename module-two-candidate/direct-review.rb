# Small human review rubric, not an automated quality detector or retry controller.
module DirectReview
 HARD=%w[copy brand parameters product-identity identity reference-topic-lock parameter-inheritance specific-facts].freeze
 def self.assess(trace,decisions)
  clean=decisions.map{|d|d.merge('verdict'=>d['verdict']=='serious-expression' ? 'fail' : d['verdict'])}
  base=RulesCompiler.review(trace,clean) # Validate coverage and located observations.
  hard=decisions.select{|d|(d['verdict']=='fail'&&HARD.include?(d['ruleId']))||d['verdict']=='serious-expression'}
  advice=decisions.select{|d|d['verdict']=='fail'&&!HARD.include?(d['ruleId'])}
  pending=decisions.any?{|d|d['verdict']=='unverified'&&HARD.include?(d['ruleId'])}
  base.merge('overall'=>hard.any? ? 'hard-issues-require-user-review' : pending ? 'hard-checks-unverified' : advice.any? ? 'usable-with-visual-suggestions' : 'no-hard-issue-reported',
   'rubric'=>'human-hard-issues-vs-visual-advice','blockingRuleIds'=>hard.map{|d|d['ruleId']},
   'advisoryRuleIds'=>advice.map{|d|d['ruleId']},'decisions'=>decisions,
   'automaticRework'=>false,'wholeImageRejected'=>false)
 end
end
