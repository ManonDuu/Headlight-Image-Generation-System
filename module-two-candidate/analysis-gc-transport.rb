# Only a future explicitly approved caller may supply its normally acquired key.
# No environment reads, credential persistence, redirection, retry, or fallback.
require 'tempfile';require 'open3'
require_relative 'analysis-gc-adapter'
require_relative 'live-request-pause'
class AnalysisGCTransport
  def initialize(key,authorized_once:false)
    raise 'live experiment locked' unless authorized_once
    raise 'invalid supplied credential' unless key.is_a?(String)&&key.match?(/\A[A-Za-z0-9._-]+\z/)
    @key=key
  end
  def call(endpoint,body,options)
    LiveRequestPause.check!
    raise 'transport already used' if @used
    raise 'fixed endpoint/options required' unless endpoint==AnalysisGCAdapter::ENDPOINT&&options=={retries:0,timeoutSeconds:120}
    @used=true
    Tempfile.create('gc-request-') do |req|
      req.binmode;req.write(body);req.flush
      Tempfile.create('gc-response-') do |res|
        r,w=IO.pipe
        writer=Thread.new{begin;w.write("x-goog-api-key: #{@key}\n");ensure;w.close;end}
        begin
          http,st=Open3.capture2({'GEMINI_API_KEY'=>nil},'/usr/bin/curl','-q','--header','@/dev/fd/3','--silent','--retry','0','--connect-timeout','15','--max-time','120','--proto','=https','--request','POST','--header','Content-Type: application/json','--data-binary','@'+req.path,'--output',res.path,'--write-out','%{http_code}',endpoint,3=>r,err:File::NULL)
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
end
