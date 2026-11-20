# Ordinary preparation is recoverable through the existing task history UI.
# Stores exactly the user-submitted input bytes; never grants generation authority.
module LocalPreparationRecord
 # Reuse the first immutable freeze only for semantically identical user input.
 # JSON object ordering must not change a previously sent analysis prompt.
 def self.frozen_for(root,record,current)
  file=File.join(root,record.fetch('id'),'frozen.json')
  return current unless File.file?(file)&&record.dig('inputProvenance','origin')=='user'
  saved=JSON.parse(File.read(file));DirectImagePlan.validate(saved)
  return current unless saved['options']==current['options']
  keys=%w[requestHash sourceHash productHash module expectedDimensions]
  return current unless keys.all?{|k|saved.dig('binding',k)==current.dig('binding',k)}
  saved
 end
 def self.save(root,frozen,reference,product,raw_options:nil)
  id=Digest::SHA256.hexdigest('local-preparation:input-origin-2:'+frozen.dig('binding','requestHash'))[0,24];dir=File.join(root,id);FileUtils.mkdir_p(dir)
  statefile=File.join(dir,'state.json');return JSON.parse(File.read(statefile)) if File.file?(statefile)
  files={};[['reference',reference],['product',product]].each do |role,bytes|
   next unless bytes;image=InputImage.inspect(bytes);name=InputImage.filename(role,image['mime']);File.binwrite(File.join(dir,name),bytes);files[role]={'file'=>name,'mime'=>image['mime'],'sha256'=>Digest::SHA256.hexdigest(bytes)}
  end
  s={'id'=>id,'createdAt'=>Time.now.utc.iso8601,'state'=>'local-prepared','module'=>frozen['options']['module'],'mode'=>frozen['options']['mode'],'localPreparation'=>true,'requestHash'=>frozen.dig('binding','requestHash'),'sourceHash'=>frozen.dig('binding','sourceHash'),'productHash'=>frozen.dig('binding','productHash'),'inputFiles'=>files,'sourceMime'=>files['reference']['mime'],'productMime'=>files.dig('product','mime'),'options'=>frozen['options'],'ruleTrace'=>{'mode'=>frozen['options']['mode'],'selectedOptions'=>frozen['options'],'output'=>frozen['options']['output'],'checks'=>[]},'newModelCalls'=>0,'generationAuthorized'=>false,'visualAcceptance'=>'not-rendered'}
  s['rawUserOptions']=raw_options if raw_options
  s['inputProvenance']={'version'=>'input-origin-2','origin'=>raw_options ? 'user' : 'legacy-unknown','effectiveOptionsAreUserInput'=>false}
  File.write(File.join(dir,'frozen.json'),JSON.generate(frozen));File.write(statefile+'.tmp',JSON.pretty_generate(s));File.rename(statefile+'.tmp',statefile);s
 end
end
