# Read-only validation of original inputs in genuine old and new history records.
module HistoryInputRecovery
 def self.inspect(dir,state)
  return nil unless %w[product-replacement reference-reconstruction].include?(state['module'])
  roles=state['module']=='product-replacement' ? %w[reference product] : %w[reference]
  assets={}
  roles.each do |role|
   key=role=='reference' ? 'sourceHash' : 'productHash';mime=state[role=='reference' ? 'sourceMime' : 'productMime']||'image/jpeg'
   filename=InputImage.filename(role,mime);path=File.join(dir,filename)
   raise "missing original #{role}" unless File.file?(path)
   hash=Digest::SHA256.file(path).hexdigest
   raise "original #{role} hash mismatch" unless state[key]==hash
   assets[role]={'sha256'=>hash,'filename'=>filename,'mime'=>mime}
  end
  {'state'=>'available','assets'=>assets,'newGenerationAuthorization'=>false}
 rescue => e
  {'state'=>'blocked','reason'=>e.message,'newGenerationAuthorization'=>false}
 end
end
