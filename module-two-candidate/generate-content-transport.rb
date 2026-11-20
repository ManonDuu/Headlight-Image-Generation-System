# Only a future explicitly approved caller may supply its normally acquired key.
# No environment reads, credential persistence, redirection, retry, or fallback.
require 'tempfile';require 'open3'
require_relative 'generate-content-adapter'
require_relative 'live-request-pause'
class GenerateContentTransport
  def initialize(key,authorized_once:false,meter_module:'reference')
    raise 'live experiment locked' unless authorized_once
    raise 'invalid supplied credential' unless key.is_a?(String)&&key.match?(/\A[A-Za-z0-9._-]+\z/)
    @key=key
    @meter_module=meter_module
  end
  def unmetered_call(endpoint,body,options)
    LiveRequestPause.check!
    raise 'transport already used' if @used
    raise 'fixed endpoint/options required' unless endpoint==GenerateContentAdapter::ENDPOINT&&options=={retries:0,timeoutSeconds:180}
    @used=true
    Tempfile.create('gc-request-') do |req|
      req.binmode;req.write(body);req.flush
      Tempfile.create('gc-response-') do |res|
        r,w=IO.pipe
        writer=Thread.new{begin;w.write("x-goog-api-key: #{@key}\n");ensure;w.close;end}
        begin
          http,st=Open3.capture2({'GEMINI_API_KEY'=>nil},'/usr/bin/curl','-q','--header','@/dev/fd/3','--silent','--retry','0','--connect-timeout','15','--max-time','180','--proto','=https','--request','POST','--header','Content-Type: application/json','--data-binary','@'+req.path,'--output',res.path,'--write-out','%{http_code}',endpoint,3=>r,err:File::NULL)
          r.close;writer.join
          # Keep any partial raw response for diagnosis, even if transport failed.
          return [st.success? ? Integer(http) : 0,File.binread(res.path),{'curlExitCode'=>st.exitstatus,'httpStatus'=>http.strip}]
        ensure
          r.close unless r.closed?;writer.join
          @key=nil
        end
      end
    end
  end
  def call(endpoint,body,options)
    helper=File.expand_path('../deploy/meter.py',__dir__)
    id,st=Open3.capture2('python3',helper,'reserve',stdin_data:JSON.generate({module:@meter_module,model:GenerateContentAdapter::MODEL,body:body}))
    raise '系统日/月额度不足或用量记录不可用；未调用模型' unless st.success?
    id=id.strip;http=0;raw=''
    begin
      http,raw,diagnostics=unmetered_call(endpoint,body,options)
      [http,raw,(diagnostics||{}).merge('usageRecordId'=>id)]
    ensure
      _,saved=Open3.capture2('python3',helper,'finish',stdin_data:JSON.generate({id:id,status:http,raw:raw}))
      warn '用量回写失败，已保留预留记录；请管理员核对' unless saved.success?
    end
  end

end
