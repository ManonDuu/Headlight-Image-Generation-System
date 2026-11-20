# Local legacy completion: actual source pixels + native OCR + supplied semantic blocks.
# It never invents a semantic analysis, fetches a sample by hash, or sends a request.
require 'tmpdir'
require_relative 'local-reference-ocr'
module LocalSourceStructure
 def self.observe(reference,layout,inventory:nil,text_only:false)
  hash=Digest::SHA256.hexdigest(reference)
  if inventory
   raise 'SOURCE_PANEL_INVENTORY_UNBOUND' unless inventory['sourceHash']==hash&&inventory['actualPixelsReviewed']==true&&inventory['panels'].is_a?(Array)
  end
  ocr=LocalReferenceOCR.observe(reference,hash)
  raise 'LOCAL_STRUCTURE_OCR_UNAVAILABLE' if ocr['state']=='unavailable'
  Dir.mktmpdir('picture-observations-') do |dir|
   image=File.join(dir,'source.image');File.binwrite(image,reference);File.write(File.join(dir,'ocr.json'),JSON.generate(ocr));File.write(File.join(dir,'layout.json'),JSON.generate(layout));dest=File.join(dir,'structure.json');File.write(File.join(dir,'inventory.json'),JSON.generate(inventory)) if inventory
   _out,err,status=Open3.capture3('python3',File.join(__dir__,'observe-reference-strips.py'),image,File.join(dir,'ocr.json'),File.join(dir,'layout.json'),dest,* (text_only ? ['--text-only'] : inventory ? [File.join(dir,'inventory.json')] : []))
   raise 'LOCAL_STRUCTURE_UNRESOLVED: '+err.lines.last.to_s.strip unless status.success?
   result=JSON.parse(File.read(dest));canonical=->(v){case v;when Hash;v.transform_values{|x|canonical.call(x)};when Array;v.map{|x|canonical.call(x)};when Float;v.round(4);else;v;end};canonical.call(result)
  end
 end
end
