require_relative 'generate-content-adapter'
require 'tmpdir';require 'zlib'
g=GenerateContentAdapter;n=0;check=lambda{|ok,msg|raise msg unless ok;n+=1}
reject=lambda{|&block|begin;block.call;rescue ArgumentError,Errno::EEXIST;n+=1;else;raise 'expected rejection';end}
raw=File.binread(File.join(__dir__,'bridge-jobs/3bdaaef4bf062f158e862cab/request.json'));plan=g.prepare(raw)
request=JSON.parse(plan['body']);old=JSON.parse(raw)
check.call(request['contents'][0]['parts'][0]['text']==old['input'][0]['text'],'exact frozen prompt')
check.call(request['contents'][0]['parts'][1]['inlineData']['data']==old['input'][1]['data'],'exact original JPEG')
check.call(request['generationConfig']['maxOutputTokens']==4096&&plan['binding']['conservativeMicroUSD']<=260000,'cap and budget')
reject.call{g.prepare(raw+' ')}
Dir.mktmpdir('gc-offline-') do |dir|
  chunk=lambda{|type,data|[data.bytesize].pack('N')+type+data+[Zlib.crc32(type+data)].pack('N')}
  png="\x89PNG\r\n\x1a\n".b+chunk.call('IHDR',[1856,2304,8,2,0,0,0].pack('NNCCCCC'))+chunk.call('IDAT',Zlib::Deflate.deflate(("\x00".b+"\x20\x40\x60".b*1856)*2304))+chunk.call('IEND',''.b)
  File.binwrite(dir+'/fixture.png',png)
  _,st=Open3.capture2(File.expand_path('../deploy/image_probe.py',__dir__),'-s','format','jpeg',dir+'/fixture.png','--out',dir+'/fixture.jpg',err:File::NULL);raise 'mock conversion' unless st.success?
  make=lambda{|mime,bytes|{'modelVersion'=>g::MODEL,'candidates'=>[{'finishReason'=>'STOP','content'=>{'parts'=>[{'inlineData'=>{'mimeType'=>mime,'data'=>Base64.strict_encode64(bytes)}}]}}],'usageMetadata'=>{'promptTokenCount'=>1866,'candidatesTokenCount'=>1680,'thoughtsTokenCount'=>0,'totalTokenCount'=>3546}}}
  response=make.call('image/png',png)
  calls=0;transport=lambda{|endpoint,body,opts|calls+=1;check.call(endpoint==g::ENDPOINT&&opts=={retries:0,timeoutSeconds:180},'no retry or alternate endpoint');[200,JSON.generate(response)]}
  result=g.execute(plan,dir+'/one',approval:plan['binding'],transport:transport)
  check.call(result['state']=='mock-result'&&File.binread(dir+'/one/output.png')==png,'original PNG saved unchanged')
  reject.call{g.execute(plan,dir+'/one',approval:plan['binding'],transport:transport)}
  check.call(calls==1,'no replay')
  jpeg=File.binread(dir+'/fixture.jpg');parsed=g.parse(200,JSON.generate(make.call('image/jpeg',jpeg)))
  check.call(parsed['bytes']==jpeg&&parsed['outputFilename']=='output.jpg','original JPEG unchanged')
  %w[MAX_TOKENS SAFETY OTHER].each{|reason|bad=Marshal.load(Marshal.dump(response));bad['candidates'][0]['finishReason']=reason;reject.call{g.parse(200,JSON.generate(bad))}}
  bad=Marshal.load(Marshal.dump(response));bad['candidates']<<bad['candidates'][0];reject.call{g.parse(200,JSON.generate(bad))}
  bad=Marshal.load(Marshal.dump(response));bad['usageMetadata']['candidatesTokenCount']=4097;reject.call{g.parse(200,JSON.generate(bad))}
  reject.call{g.execute(plan,dir+'/live',approval:plan['binding'],transport:transport,mock:false)}
  check.call(!File.exist?(dir+'/live'),'live locked before reservation')
  altered=Marshal.load(Marshal.dump(plan));altered['body']=altered['body'].sub('4096','8192');altered['binding']['requestHash']=Digest::SHA256.hexdigest(altered['body'])
  reject.call{g.execute(altered,dir+'/tamper',approval:altered['binding'],transport:transport)}
  timeout_calls=0;failing=lambda{|*_|timeout_calls+=1;raise 'simulated timeout'}
  result=g.execute(plan,dir+'/failed',approval:plan['binding'],transport:failing)
  check.call(result['state']=='stopped'&&timeout_calls==1,'timeout terminal, no retry')
  reject.call{g.execute(plan,dir+'/failed',approval:plan['binding'],transport:failing)}
end
puts "PASS #{n} generateContent offline checks including exact request, native PNG/JPEG preservation, terminal errors, budget and replay. No network."
