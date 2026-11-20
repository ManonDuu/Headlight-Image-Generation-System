# Sole new paid-test path. Leaves old pause/STOP records untouched.
# No credential acquisition: caller may later supply its normally acquired key.
require 'json';require 'base64';require 'digest';require 'open3';require 'tempfile';require 'fileutils'
class CumulativeSceneTransport
 ROOT=File.expand_path(__dir__)
 LEDGER=File.join(ROOT,'diagnostics/cumulative-budget/global-ledger')
 ENDPOINT='https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:generateContent'
 def initialize(key:nil,spec:,mock:false,offline_transport:nil,offline_ledger:nil)
  raise 'mock backend required, credentials forbidden' if mock&&(!offline_transport||key)
  raise 'offline overrides forbidden in live transport' if !mock&&(offline_transport||offline_ledger)
  @key,@spec,@mock,@backend=key,JSON.parse(JSON.generate(spec)),mock,offline_transport
  @ledger=mock ? File.expand_path(offline_ledger) : LEDGER
 end
 def record(action,data)
  output,error,status=Open3.capture3({'GEMINI_API_KEY'=>nil},'python3',File.join(ROOT,'cumulative-budget.py'),@ledger,action,stdin_data:JSON.generate(data))
  # Never include credential/response data in error; gate only reads public binding/body.
  raise 'cumulative budget gate rejected '+action unless status.success?
  JSON.parse(output)
 end
 def call(endpoint,body,options)
  raise 'transport already used' if @used
  raise 'fixed scene endpoint and zero retry required' unless endpoint==ENDPOINT&&options=={retries:0,timeoutSeconds:180}
  raise 'frozen request mismatch' unless @spec['endpoint']==endpoint&&@spec['requestHash']==Digest::SHA256.hexdigest(body)
  request=JSON.parse(body);config=request.fetch('generationConfig')
  raise 'unbounded request configuration' unless request.keys.sort==%w[contents generationConfig]&&config.keys.sort==%w[candidateCount imageConfig maxOutputTokens responseModalities thinkingConfig]&&config['responseModalities']==['IMAGE']&&config.dig('imageConfig','imageSize')=='2K'
  raise 'unproven budget ceiling' unless @spec['boundMicroUSD'].is_a?(Integer)&&@spec['boundMicroUSD']>=409600
  raise 'bounded single image request required' unless config['candidateCount']==1&&config['maxOutputTokens']==4096&&request['tools'].nil?&&request['cachedContent'].nil?&&request['contents'].size==1
  raise 'missing normally supplied credential' unless @mock||(@key.is_a?(String)&&@key.match?(/\A[A-Za-z0-9._-]+\z/))
  @used=true
  record('begin',{'spec'=>@spec,'bodyBase64'=>Base64.strict_encode64(body)})
  begin
   result=@mock ? @backend.call(endpoint,body,options) : send_once(endpoint,body)
   http,raw,diag=result
   dir=File.join(@ledger,'responses',@spec['requestHash']);FileUtils.mkdir_p(dir)
   File.open(File.join(dir,'response.raw.json'),File::WRONLY|File::CREAT|File::EXCL,0600){|f|f.write(raw);f.flush;f.fsync}
   File.write(File.join(dir,'transport.json'),JSON.generate({'httpStatus'=>http,'diagnostics'=>diag,'retries'=>0}))
   if http.to_i==0||diag&&diag['curlExitCode'].to_i!=0
    record('settle',{'requestHash'=>@spec['requestHash'],'error'=>'transport-outcome-unknown'})
   else
    record('settle',{'requestHash'=>@spec['requestHash'],'responseHash'=>Digest::SHA256.hexdigest(raw)})
   end
   result
  rescue Exception=>e
   # A failed settlement must not overwrite a prior settled event; failed recovery
   # leaves the pre-dispatch uncertain record durable and never resends.
   begin;record('settle',{'requestHash'=>@spec['requestHash'],'error'=>e.class.name});rescue StandardError;end
   raise
  ensure
   @key=nil
  end
 end
 private
 def send_once(endpoint,body)
  Tempfile.create('bounded-scene-request-') do |req|
   req.binmode;req.write(body);req.flush
   Tempfile.create('bounded-scene-response-') do |res|
    r,w=IO.pipe;writer=Thread.new{begin;w.write("x-goog-api-key: #{@key}\n");ensure;w.close;end}
    begin
     http,status=Open3.capture2({'GEMINI_API_KEY'=>nil},'/usr/bin/curl','-q','--header','@/dev/fd/3','--silent','--retry','0','--connect-timeout','15','--max-time','180','--proto','=https','--request','POST','--header','Content-Type: application/json','--data-binary','@'+req.path,'--output',res.path,'--write-out','%{http_code}',endpoint,3=>r,err:File::NULL)
     [status.success? ? Integer(http) : 0,File.binread(res.path),{'curlExitCode'=>status.exitstatus,'httpStatus'=>http.strip,'retries'=>0}]
    ensure
     r.close unless r.closed?;writer.join
    end
   end
  end
 end
end
