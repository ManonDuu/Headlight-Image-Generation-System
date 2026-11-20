# Built-in macOS Vision, local file only. Geometry evidence never replaces copy.
require 'open3'
require 'tempfile'
require 'timeout'
module LocalReferenceOCR
 def self.observe(bytes,source_hash)
  raise 'OCR source binding changed' unless Digest::SHA256.hexdigest(bytes)==source_hash
  @cache ||= {};return @cache[source_hash] if @cache.key?(source_hash)
  result=nil
  Tempfile.create(['picture-reference-','.image']) do |f|
   f.binmode;f.write(bytes);f.flush
   Open3.popen3('python3',File.expand_path('../deploy/ocr.py',__dir__),f.path,pgroup:true) do |stdin,stdout,stderr,wait|
    stdin.close
    begin
     raw=Timeout.timeout(8){stdout.read};status=wait.value
     raise 'native OCR unavailable' unless status.success?
     result=JSON.parse(raw);raise 'invalid OCR lines' unless result['lines'].is_a?(Array)
     result['lines'].each{|a|raise 'invalid OCR geometry' unless a['quad'].size==4&&a['quad'].flatten.all?{|x|x.is_a?(Numeric)&&x.between?(0,1)}}
    rescue Timeout::Error
     Process.kill('TERM',-wait.pid) rescue nil
     raise 'native OCR timed out'
    end
   end
  end
  result['sourceHash']=source_hash;@cache.shift if @cache.size>=8;@cache[source_hash]=result
 rescue StandardError=>e
  {'version'=>'local-vision-ocr-1','sourceHash'=>source_hash,'lines'=>[],'state'=>'unavailable','reason'=>e.message,'network'=>false}
 end
end
