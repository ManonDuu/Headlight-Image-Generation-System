# Offline preparation only. Does not authorize or execute the experiment.
require_relative 'generate-content-adapter'
root=File.expand_path(__dir__)
plan=GenerateContentAdapter.prepare(File.binread(root+'/bridge-jobs/3bdaaef4bf062f158e862cab/request.json'))
dir=root+'/gc-comparison-20261018'
raise 'plan already exists; preserve it' if File.exist?(dir)
Dir.mkdir(dir,0700)
File.binwrite(dir+'/request.json',plan['body'])
File.write(dir+'/binding.json',JSON.pretty_generate(plan['binding']))
redacted=JSON.parse(plan['body']);redacted['contents'][0]['parts'][1]['inlineData']['data']='[ORIGINAL JPEG OMITTED]'
File.write(dir+'/request-redacted.json',JSON.pretty_generate(redacted))
puts JSON.generate(state:'prepared-not-authorized',directory:dir,requestHash:plan['binding']['requestHash'],modelCalls:0)
