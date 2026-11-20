require_relative 'direct-image-plan'
require 'json';require 'digest'
n=0;ck=lambda{|v,m|raise m unless v;n+=1}
root=File.expand_path(__dir__);fixture=JSON.parse(File.read(root+'/fixtures/direct-real-failure-20261018.json'))
job=root+'/bridge-jobs/'+fixture['task'];old=JSON.parse(File.read(job+'/generic-gc-plan.json'))
ck.call(DirectImagePlan.validate(old),'legacy frozen contract remains valid')
sent=File.binread(job+'/generic-request.json')
ck.call(sent==old['body']&&Digest::SHA256.hexdigest(sent)==fixture['requestHash'],'actual transmitted bytes match frozen request')
ck.call(Digest::SHA256.file(job+'/output.jpg').hexdigest==fixture['outputHash'],'real failure unchanged')
old_text=JSON.parse(sent)['contents'][0]['parts'][0]['text']
ck.call(old_text.include?('discard unsupported reference claims')&&old_text.include?('Remove added reference brands'),'old prohibitions were transmitted, not omitted')
ck.call(old_text.include?('Never change functional color coding')&&old_text.include?('Preserve retained text appearance'),'old competing retention language present')
ref=File.binread(job+'/reference.jpg');o=old['options'].merge('businessSpec'=>DirectImagePlan::SPEC)
fresh=DirectImagePlan.prepare(ref,nil,o);ck.call(DirectImagePlan.validate(fresh),'new plan deterministic')
body=JSON.parse(fresh['body']);text=body['contents'][0]['parts'][0]['text'];rules=fresh['trace']['ruleBindings'];policy=fresh['trace']['policy']
ck.call(text.bytesize<=8192,'policy stays within reserved prompt budget')
ck.call(fresh['binding']['requestHash']!=old['binding']['requestHash'],'new request cannot reuse consumed approval')
ck.call(DirectImagePlan.image_part(fresh,'reference')==JSON.parse(sent)['contents'][0]['parts'][1]['inlineData'],'same actual input bytes')
ck.call(body['generationConfig']==JSON.parse(sent)['generationConfig'],'transport/model settings unchanged')
ck.call(policy['priority'].first=='user-facts-and-copy-policy'&&policy['referenceTextAuthority']=='none','facts/copy higher than layout')
ck.call(policy['claimAuthority'].empty?&&policy['brandAuthority']=='none','empty supplied facts authorize no claims/brand')
params=rules.find{|r|r['ruleId']=='parameters'}['constraint']
fixture['unsupportedObservedClaims'].each{|c|ck.call(params.include?(c['category']),'real failure category covered: '+c['text'])}
fixture['otherRegressionCategories'].each{|c|ck.call(params.include?(c),'general claims category covered: '+c)}
ck.call(!text.include?('IP68')&&!text.include?('-40')&&!text.include?('+80'),'not a sample-specific blacklist')
ck.call(rules.first['ruleId']=='priority'&&text.include?('leave the space empty'),'explicit conflict and blank-space policy')
ck.call(text.include?('No mirroring')&&text.include?('lamp on/off state'),'view and secondary-light constraints explicit')
ck.call(text.include?('subject count, frame occupancy and view')&&text.include?('beams equally salient'),'fog/snow/dust feedback generalized as evidence invariants')
ck.call(!text.include?('bridge')&&!text.include?('Foggy')&&!text.include?('Snowy')&&!text.include?('Dusty'),'no fixed background or weather template')
ck.call(!text.include?('EVERY photo panel')&&!text.include?('not only the hero'),'withdraw extra scene-change demand based on misread feedback')
ck.call(text.include?('including required removal of a reference brand or unsupported numeric parameter')&&text.include?('No per-block rewrite requirement'),'whole-image minimal rewrite, no per-block requirement')
ck.call(rules.all?{|r|text.include?(r['constraint'])},'all compiled rules survive serialization')
layout_rule=rules.find{|r|r['ruleId']=='layout'}['constraint']
ck.call(!layout_rule.include?('duplicate heading/label regions'),'withdraw unrequested additional layout constraint')
ck.call(rules.map{|r|r['ruleId']}.uniq.size==rules.size,'no duplicate rule categories')
amazon=JSON.parse(File.read(root+'/bridge-jobs/1cb97883b48e2575f123ae2b/generic-gc-plan.json'))
ck.call(DirectImagePlan.validate(amazon),'consumed .2 Amazon contract remains reproducible')
ck.call(fresh['trace']['checks'].all?{|c|c['status']=='not-evaluated'},'no offline semantic pass')
%w[remove-all-copy ai-rewrite custom].product(%w[keep-reference auto-layout]).each do |mode,layout|
 opts=o.merge('mode'=>mode,'layoutMode'=>layout,'brandName'=>'Own','productParameters'=>'60W','customCopy'=>'Own 60W')
 p=DirectImagePlan.prepare(ref,nil,opts);ck.call(DirectImagePlan.validate(p),'mode/layout contract')
 authority=p['trace']['policy']['claimAuthority'];expected=mode=='remove-all-copy' ? [] : mode=='custom' ? ['customCopy'] : ['productParameters']
 ck.call(authority==expected,'effective facts source by copy mode')
 ck.call(p['trace']['policy']['layoutScope']=='geometry-only','layout cannot authorize copy')
end
delivery=fresh['preflight']['delivery'];ck.call(delivery['nativeDimensions']==fixture['nativeDimensions']&&!delivery['exactModelRatio'],'native 4:5 is nominal')
ck.call(delivery['adaptation']=='none'&&!delivery['stretch']&&!delivery['crop'],'no silent adaptation')
alias_plan=DirectImagePlan.prepare(ref,nil,o.merge('output'=>{'aspectRatio'=>'12:15','imageSize'=>'2K'}))
ck.call(alias_plan['body']==fresh['body'],'12:15 maps same native request as 4:5')
ck.call(alias_plan['preflight']['delivery']['requestedRatio']=='12:15','requested alias retained honestly')
square=DirectImagePlan.prepare(ref,nil,o.merge('output'=>{'aspectRatio'=>'1:1','imageSize'=>'2K'}))
ck.call(square['preflight']['delivery']['exactModelRatio'],'square exact ratio recognized')
protected=JSON.parse(File.read(root+'/../delivery/pre-direct-policy-fix-20261018/protected-hashes.json'))
ck.call(protected.all?{|p,h|Digest::SHA256.file(p).hexdigest==h},'historical outputs/states/ledgers unchanged')
puts JSON.pretty_generate({checks:n,result:'passed',oldPromptBytes:old_text.bytesize,newPromptBytes:text.bytesize,newRequestHash:fresh['binding']['requestHash'],externalRequests:0,visualAcceptance:'not-tested',nativeReducedRatio:'29:36',exact12to15:false})
