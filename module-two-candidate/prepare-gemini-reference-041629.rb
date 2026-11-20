require_relative 'direct-image-plan'
plan=JSON.parse(File.read(File.join(__dir__,'reference-041629-v14-plan.json')))
DirectImagePlan.validate(plan)
raise 'unexpected request' unless plan.dig('binding','sourceHash')=='a54e6b22b36c69bf528ca78c7f7dd0eeda26d60ad0c9110a1d938d54f16d7d98' && plan.dig('binding','requestHash')=='b1b9956cdd41763fe3449b597f2260b070f9856aac5022b411d411176ca9a37c'
puts JSON.generate(plan)
