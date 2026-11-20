# Only constructed by an explicitly enabled service after fresh exact-plan approval.
# Caller supplies an existing in-memory key; no environment/key-file/clipboard reads.
require 'tmpdir';require 'json'
require_relative 'live-request-pause'
class AnalysisTransport
  def initialize(key,record_dir:nil);@key=key;@record_dir=record_dir;end
  def call(request)
    LiveRequestPause.check!
    raise 'missing in-memory credential' unless @key
    Dir.mktmpdir('visual-analysis-transport-') do |dir|
      req=File.join(dir,'request.json');out=File.join(dir,'response.json');File.write(req,JSON.generate(request))
      key_read,key_write=IO.pipe;result_read,result_write=IO.pipe
      writer=Thread.new{begin;key_write.write("x-goog-api-key: #{@key}\n");ensure;key_write.close;end}
      begin
        pid=Process.spawn({'GEMINI_API_KEY'=>nil},'/usr/bin/curl','-q','--header','@/dev/fd/3','--silent','--show-error','--retry','0','--connect-timeout','15','--max-time','120','--max-filesize','1048576','--proto','=https','--request','POST','--header','Content-Type: application/json','--data-binary',"@#{req}",'--output',out,'--write-out','%{http_code}','https://generativelanguage.googleapis.com/v1beta/interactions',3=>key_read,out:result_write,err:File::NULL,close_others:true)
        key_read.close;result_write.close;status=result_read.read;_,process=Process.wait2(pid);writer.join
        if @record_dir
          File.binwrite(File.join(@record_dir,'response.raw.json'),File.file?(out) ? File.binread(out) : '')
          File.write(File.join(@record_dir,'transport.json'),JSON.generate({'httpStatus'=>status,'curlExitCode'=>process.exitstatus,'retries'=>0}))
        end
        raise "analysis transport stopped: curl=#{process.exitstatus} HTTP=#{status}; remote cost may be unknown; no retry" unless process.success?&&status=='200'
        raise 'analysis response too large' unless File.size(out)<=1048576
        VisualAnalysis.parse_json(File.read(out))
      ensure
        [key_read,key_write,result_read,result_write].each{|io|io.close unless io.closed?};writer.join
      end
    end
  end
end
