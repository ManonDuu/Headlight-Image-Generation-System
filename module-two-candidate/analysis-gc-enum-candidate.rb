# Offline correction only. Consumed request/ledger and live route remain unchanged.
require_relative 'analysis-gc-adapter'
module AnalysisGCEnumCandidate
  HASH='cb4b67f9c84cf6ab8df4764d82737d6e8b4b26620996e78772a37891542c6e61'
  def self.need(ok,message);VisualAnalysis.need(ok,message);end
  def self.contract(body)
    need(body.is_a?(Hash)&&body.keys.sort==%w[contents generationConfig],'request envelope')
    cs=body['contents'];need(cs.is_a?(Array)&&cs.size==1,'single content')
    c=cs[0];need(c.keys.sort==%w[parts role]&&c['role']=='user','Content.role string user')
    ps=c['parts'];need(ps.is_a?(Array)&&ps.size==2&&ps[0].keys==['text']&&ps[0]['text'].is_a?(String)&&!ps[0]['text'].empty?,'one text part')
    need(ps[1].keys==['inlineData'],'one inline image only')
    blob=ps[1]['inlineData'];need(blob.keys.sort==%w[data mimeType]&&blob['mimeType']=='image/jpeg','Blob MIME is IANA string, not enum')
    need(Digest::SHA256.hexdigest(Base64.strict_decode64(blob['data']))==AnalysisGCAdapter::SOURCE,'frozen JPEG bytes')
    g=body['generationConfig'];need(g.keys.sort==%w[candidateCount maxOutputTokens mediaResolution responseFormat thinkingConfig],'only audited config fields')
    need(g['candidateCount'].is_a?(Integer)&&g['candidateCount']==1,'integer candidate count')
    need(g['maxOutputTokens'].is_a?(Integer)&&g['maxOutputTokens']==4096,'integer output cap')
    need(g['thinkingConfig']=={'thinkingLevel'=>'MINIMAL'},'ThinkingLevel enum')
    need(g['mediaResolution']=='MEDIA_RESOLUTION_HIGH','GenerationConfig.MediaResolution enum, not Part object')
    need(g['responseFormat'].keys==['text'],'text response only')
    t=g['responseFormat']['text'];need(t.keys.sort==%w[mimeType schema]&&t['mimeType']=='APPLICATION_JSON','TextResponseFormat.MimeType enum')
    need(t['schema']==AnalysisWireCandidate.project(VisualAnalysis::SCHEMA),'JSON schema Value, not deprecated Schema object')
    true
  end
  def self.prepare(original)
    old=AnalysisGCAdapter.prepare(original);body=JSON.parse(old['body'])
    body['generationConfig']['responseFormat']['text']['mimeType']='APPLICATION_JSON'
    contract(body);raw=JSON.generate(body);need(Digest::SHA256.hexdigest(raw)==HASH,'candidate hash changed')
    {'body'=>raw,'binding'=>old['binding'].merge('version'=>'analysis-generateContent-enum-candidate-20261018.1','requestHash'=>HASH),'liveEnabled'=>false,'authorized'=>false}
  end
end
