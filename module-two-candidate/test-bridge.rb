require_relative 'bridge-server'
require 'net/http';require 'json';require 'tmpdir';require 'digest';require 'base64';require 'fileutils'
ROOT=File.expand_path(__dir__)
N={checks:0}
def check(v,msg);raise msg unless v;N[:checks]+=1;end
def request(port,path,token:nil,data:nil,origin:nil,host:nil)
  uri=URI("http://127.0.0.1:#{port}#{path}");r=data ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
  r['X-Session-Token']=token if token;r['Origin']=origin if origin;r['Host']=host if host
  if data;r['Content-Type']='application/json';r.body=JSON.generate(data);end
  Net::HTTP.new('127.0.0.1',port,nil).start{|h|h.request(r)}
end
Dir.mktmpdir('bridge-tests-') do |dir|
  %w[success timeout error multiple].each_with_index do |scenario,index|
    port=8790+index;data=File.join(dir,scenario);FileUtils.mkdir_p(data)
    reader,writer=IO.pipe
    pid=Process.spawn({'PATH'=>'/usr/bin:/bin','GEMINI_API_KEY'=>'FAKE-never-used'},'/usr/bin/ruby',File.join(ROOT,'bridge-server.rb'),'--mock','--scenario',scenario,'--port',port.to_s,'--data',data,out:writer,err:File::NULL,unsetenv_others:true);writer.close
    begin
      raise 'server startup timeout' unless IO.select([reader],nil,nil,10)
      raise 'server not ready' unless reader.gets.include?('READY')
      sess=JSON.parse(request(port,'/api/session').body);token=sess['token'];origin="http://127.0.0.1:#{port}"
      check(request(port,'/api/session',host:'evil.test').code=='400','Host validation')
      check(request(port,'/api/freeze',token:token,data:{},origin:'https://evil.test').code=='400','Origin validation')
      check(request(port,'/api/freeze',data:{},origin:origin).code=='400','CSRF validation')
      check(request(port,'/api/task/../../etc/passwd',token:token).code!='200','no arbitrary file access')
      bytes=File.binread(File.join(ROOT,'assets/81gMZuoRq6L._AC_SL1500_.jpg'))
      body={module:'reference-reconstruction',output:{aspectRatio:'4:5',imageSize:'2K'},layoutTone:'keep-reference',mode:'no-copy',imageBase64:Base64.strict_encode64(bytes),sourceHash:Digest::SHA256.hexdigest(bytes),budgetMicroUSD:260000}
      check(request(port,'/api/freeze',token:token,data:body.merge(budgetMicroUSD:1),origin:origin).code=='400','budget guard')
      check(request(port,'/api/freeze',token:token,data:body.merge(prompt:'x'*2561),origin:origin).code=='400','token allowance guard')
      check(request(port,'/api/freeze',token:token,data:body,origin:origin).code=='400','retired create contract rejected')
      seeder=Bridge.new(mock:true,data:data,scenario:scenario)
      frozen=seeder.freeze_task(JSON.parse(JSON.generate(body))) # Fixture seeds historical contract; HTTP still exercises its bound execution/history.
      check(frozen['state']=='frozen','freeze via adapter')
      id=frozen['id'];generate={id:id,requestHash:frozen['requestHash']}
      check(request(port,'/api/generate',token:token,data:generate.merge(requestHash:'wrong'),origin:origin).code=='400','request binding')
      codes=2.times.map{Thread.new{request(port,'/api/generate',token:token,data:generate,origin:origin).code}}.map(&:value)
      check(codes.sort==['200','400'],'concurrent double click must dispatch once')
      100.times do
        sleep 0.1;s=JSON.parse(request(port,"/api/task/#{id}",token:token).body);break unless s['state']=='running'
      end
      s=JSON.parse(request(port,"/api/task/#{id}",token:token).body)
      check(s['state']==(scenario=='success' ? 'mock-result' : 'stopped'),'terminal result '+scenario)
      check(s['visualAcceptance']=='not-evaluated','never auto accept')
      check(s.dig('providerError','message').include?("Supported values: 'image/jpeg'"),'exact recorded API error is visible') if scenario=='error'
      check(request(port,'/api/generate',token:token,data:generate,origin:origin).code=='400','no retry')
      second=seeder.freeze_task(JSON.parse(JSON.generate(body)))
      check(request(port,'/api/generate',token:token,data:{id:second['id'],requestHash:second['requestHash']},origin:origin).code=='400','global single allowance')
      if scenario=='success'
        png=request(port,"/api/task/#{id}/image",token:token)
        check(png.code=='200'&&Digest::SHA256.hexdigest(png.body)==s['outputHash'],'exact raw JPEG download')
        check(png['Content-Type']=='image/jpeg'&&png.body.b.start_with?("\xFF\xD8\xFF".b),'JPEG MIME and real bytes')
        response=JSON.parse(File.read(File.join(data,id,'response.json')))
        raw=Base64.strict_decode64(response['steps'][0]['content'][0]['data'])
        check(png.body.b==raw,'provider bytes preserved without re-encoding')
        check(s['outputFilename']=='output.jpg'&&s['outputMime']=='image/jpeg','JPEG output metadata')

        review=JSON.parse(request(port,'/api/review',token:token,data:{id:id,decisions:s['ruleTrace']['appliedRuleIds'].map{|rule|{ruleId:rule,verdict:'unverified',note:'Simulated path only',evidence:[{kind:'visual-observation',location:'whole mock image'}]}}},origin:origin).body)
        check(review['visualAcceptance']=='mock-review-only','mock review never real acceptance')
        check(JSON.parse(request(port,"/api/task/#{id}/record",token:token).body)['review']['decisions'][0]['note']=='Simulated path only','saved review')
      else
        check(request(port,"/api/task/#{id}/image",token:token).code=='400','no failed output delivery')
      end
      check(JSON.parse(request(port,'/api/session').body)['remaining']==0,'allowance stays consumed')
    ensure
      Process.kill('TERM',pid) rescue nil;Process.wait(pid) rescue nil;reader.close
    end
  end
end
puts "PASS #{N[:checks]} loopback integration checks. Mock only; zero external requests."
