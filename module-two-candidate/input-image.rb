require 'zlib'
require_relative 'product-replacement-plan'
# Decode/validate only: never convert, resize or alter source bytes.
module InputImage
 PNG="\x89PNG\r\n\x1a\n".b
 def self.inspect(bytes,max_bytes:4*1024*1024)
  raise 'invalid image validation limit' unless [4*1024*1024,20*1024*1024].include?(max_bytes)
  raise 'image exceeds '+(max_bytes/1024/1024).to_s+'MB' unless bytes.is_a?(String)&&bytes.bytesize<=max_bytes
  if bytes.start_with?("\xff\xd8\xff".b)
   return {'mime'=>'image/jpeg','extension'=>'jpg','dimensions'=>ProductReplacementPlan.jpeg(bytes)}
  end
  raise 'JPEG or PNG required' unless bytes.start_with?(PNG)
  pos=8;chunks=[];dims=nil
  while pos<bytes.bytesize
   raise 'truncated PNG chunk' if pos+12>bytes.bytesize
   len=bytes.byteslice(pos,4).unpack1('N');kind=bytes.byteslice(pos+4,4)
   raise 'invalid PNG chunk length' if len>bytes.bytesize-pos-12
   data=bytes.byteslice(pos+8,len);crc=bytes.byteslice(pos+8+len,4).unpack1('N')
   raise 'PNG CRC mismatch' unless Zlib.crc32(kind+data)==crc
   raise 'animated PNG unsupported' if kind=='acTL'
   if chunks.empty?
    raise 'PNG IHDR required' unless kind=='IHDR'&&len==13
    dims=data.unpack('NN');raise 'invalid image dimensions' unless dims.all?{|v|v.between?(1,20000)}
   elsif kind=='IHDR';raise 'duplicate PNG IHDR';end
   chunks<<kind;pos+=len+12
   if kind=='IEND'
    raise 'invalid PNG end' unless len==0&&pos==bytes.bytesize
    break
   end
  end
  raise 'incomplete PNG' unless chunks.last=='IEND'&&chunks.include?('IDAT')
  Tempfile.create(['input-image','.png']) do |f|
   f.binmode;f.write(bytes);f.flush
   out,st=Open3.capture2(File.expand_path('../deploy/image_probe.py',__dir__),'-g','pixelWidth','-g','pixelHeight','-g','format',f.path,err:File::NULL)
   decoded=[out[/pixelWidth: (\d+)/,1].to_i,out[/pixelHeight: (\d+)/,1].to_i]
   raise 'PNG decoder rejected bytes' unless st.success?&&out[/format: (\w+)/,1]=='png'&&decoded==dims
  end
  {'mime'=>'image/png','extension'=>'png','dimensions'=>dims}
 end
 def self.filename(role,mime)
  raise 'invalid image role' unless %w[reference product].include?(role)
  ext={'image/jpeg'=>'jpg','image/png'=>'png'}.fetch(mime)
  role+'.'+ext
 end
end
