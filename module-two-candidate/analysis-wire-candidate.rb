# Offline wire-schema compatibility candidate. Not wired to any live route.
require_relative 'visual-analysis'
module AnalysisWireCandidate
  REVISION='wire-schema-documented-subset-20261018.1'
  def self.project(schema)
    out=Marshal.load(Marshal.dump(schema))
    if out['type']=='string'
      out.delete('minLength');out.delete('maxLength')
    end
    out['properties']=out['properties'].transform_values{|v|project(v)} if out['properties']
    out['items']=project(out['items']) if out['items']
    out
  end
  def self.prepare(original)
    body=Marshal.load(Marshal.dump(original))
    body.fetch('response_format')['schema']=project(VisualAnalysis::SCHEMA)
    {'revision'=>REVISION,'body'=>body,'requestHash'=>Digest::SHA256.hexdigest(JSON.generate(body)),
      'localValidationSchemaHash'=>Digest::SHA256.hexdigest(JSON.generate(VisualAnalysis::SCHEMA)),
      'wireSchemaHash'=>Digest::SHA256.hexdigest(JSON.generate(body['response_format']['schema'])),
      'enabled'=>false,'authorization'=>nil,'rootCauseConfirmed'=>false}
  end
end
