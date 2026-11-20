# Prepare only. Never sends to Google or executes a request.
require 'json';require 'fileutils';require 'digest'
root=File.expand_path(__dir__)
dir=File.join(File.dirname(root),'delivery','google-support-incomplete-20261017')
raise 'support bundle already exists' if File.exist?(dir)
FileUtils.mkdir_p(dir,mode:0700)
job=File.join(root,'bridge-jobs','3bdaaef4bf062f158e862cab')
request=JSON.parse(File.read(File.join(job,'request.json')))
request['input'].each do |part|
  part['text']='[PRIVATE FROZEN INSTRUCTION OMITTED]' if part.key?('text')
  part['data']='[PRIVATE JPEG OMITTED; NO IMAGE BYTES INCLUDED]' if part.key?('data')
end
File.write(File.join(dir,'request-redacted.json'),JSON.pretty_generate(request))
FileUtils.cp(File.join(job,'response.json'),File.join(dir,'response-original.json'))
File.write(File.join(dir,'READ-ME.txt'),<<~TEXT)
  PREPARED ONLY — NOT SUBMITTED TO GOOGLE
  Investigate an incomplete result with HTTP 200 and no diagnostic reason or image.
  We have no confirmed remedy. A low token budget, safety filter or alternative endpoint
  is not an established cause or fix. No continuation or retry was made.

  POST https://generativelanguage.googleapis.com/v1beta/interactions
  Content-Type: application/json. Authentication header intentionally omitted.
  curl exit 0; HTTP 200; request began 2026-10-17T07:29:50Z;
  local completion 2026-10-17T07:30:14Z; provider created/updated 07:30:13Z.
  model gemini-3.1-flash-image; store=false; one JPEG input; 2K 4:5 JPEG output requested.
  Actual max_output_tokens=4096; thinking_level=minimal.
  Actual response: incomplete, input=1866, output=1025, thought=0, total=2891.
  There is no steps field, content, image, URL, error/finish reason, ID or continuation token.
  The original 426-byte response is supplied unchanged. No image is hidden in this file.
  request-redacted.json preserves all request keys but replaces private prompt and JPEG.
  It is diagnostic context, not an executable replay request.

  Questions for support: What backend termination condition produced this response?
  Was the requested 4096 output-token cap applied? Why were no steps or diagnostic
  reason returned? What supported diagnostic evidence could distinguish this condition?
  Please do not assume an unreported 1024 cap or recommend larger spend without evidence.

  Docs consulted:
  https://ai.google.dev/api/interactions-api
  https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-image
  https://ai.google.dev/gemini-api/docs/image-generation
  The status documentation gives max-token exhaustion as an example, not proof for this case.
  Request 4096, reported output 1025 and thought 0 do not establish exhaustion or safety rejection.

  No account/project identifiers, credentials, private prompt, image bytes, personal paths,
  browser data or original full request are included. Private local backup is NOT this bundle.
TEXT
manifest={}
Dir[dir+'/*'].each do |p|
  content=File.binread(p)
  raise 'secret/base64 pattern found' if content.match?(/AIza[0-9A-Za-z_-]{35}/)||content.match?(/[A-Za-z0-9+\/_-]{128,}={0,2}/)
  manifest[File.basename(p)]={'bytes'=>File.size(p),'sha256'=>Digest::SHA256.file(p).hexdigest}
end
File.write(File.join(dir,'MANIFEST-SHA256.json'),JSON.pretty_generate(manifest))
puts JSON.generate(preparedOnly:true,files:manifest.size,directory:dir,secretOrImagePayloadPatternMatches:0)
