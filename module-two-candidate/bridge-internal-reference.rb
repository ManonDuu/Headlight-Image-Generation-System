# Offline history and injected mock-provider fixtures only. No live dispatch route.
require_relative 'reference-provider'
module BridgeInternalReference
  INTERNAL_REFERENCE_PATH='/api/internal/reference'
  def internal_root;File.join(@data,'.internal-reference');end
  def internal_path(id)
    raise 'invalid internal task id' unless id.is_a?(String)&&id.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
    File.join(internal_root,id+'.json')
  end
  def internal_bytes(v)
    raise 'binary envelope required' unless v.is_a?(Hash)&&v.keys.sort==%w[base64 mime]
    Base64.strict_decode64(v.fetch('base64'))
  end
  def internal_digest(v);Digest::SHA256.hexdigest(internal_bytes(v));end
  def internal_verify(r)
    raise 'unsupported internal version' unless r['version']==1
    raise 'mock records must be explicitly marked fixtureOnly' if @mock&&r['fixtureOnly']!=true
    f=r.fetch('frozen');parent=snapshot(f.fetch('id'))
    raise 'only reference module supported' unless f['module']=='reference-reconstruction'&&parent['module']==f['module']
    %w[sourceHash requestHash ruleTrace].each{|k|raise "frozen #{k} mismatch" unless f[k]==parent[k]}
    filename,_=input_asset(parent,'reference')
    raise 'original source mismatch' unless internal_digest(r.fetch('reference'))==parent['sourceHash']&&Digest::SHA256.file(File.join(job(parent['id']),filename)).hexdigest==parent['sourceHash']
    raise 'frozen fingerprint mismatch' unless Digest::SHA256.hexdigest(JSON.generate(f))==r['frozenHash']
    if a=r['assets']
      raise 'background hash mismatch' unless internal_digest(a['background'])==a['backgroundHash']&&a['backgroundHash']!=parent['sourceHash']
      raise 'layout hash mismatch' unless Digest::SHA256.hexdigest(JSON.generate(a['plan']))==a['planHash']
      e=a.fetch('evidence');raise 'unreviewed package' unless e.values_at('sourceHash','backgroundHash','planHash')==[parent['sourceHash'],a['backgroundHash'],a['planHash']]&&%w[sceneReconstructed oldCopyAbsent layoutReviewed factsReviewed].all?{|k|e[k]==true}&&%w[reviewer note].all?{|k|e[k].is_a?(String)&&!e[k].strip.empty?}
      text=a.fetch('plan').fetch('text');o=f.fetch('ruleTrace').fetch('selectedOptions');mode=o.fetch('mode')
      raise 'invalid text roles/modes' unless text.is_a?(Array)&&text.all?{|t|t['mode']==mode&&%w[title subtitle body brand].include?(t['role'])&&t['text'].is_a?(String)&&!t['text'].match?(SharedTypography::FORBIDDEN)}
      width,height=f['ruleTrace']['expectedDimensions']
      text.each do |t|
        raise 'explicit valid typography required' unless %w[fontSize weight lineHeightPx].all?{|k|t[k].is_a?(Numeric)&&t[k].finite?}&&t['fontSize']>0&&t['fontSize']<=256&&t['weight'].between?(100,900)&&t['lineHeightPx']>0&&%w[normal italic].include?(t['style'])&&%w[left center right].include?(t['align'])&&!t.key?('scaleX')&&!t.key?('maxWidth')
        b=t['box'];raise 'valid text box required' unless b.is_a?(Hash)&&b.keys.sort==%w[height width x y]&&b.values.all?{|v|v.is_a?(Numeric)&&v.finite?}&&b['x']>=0&&b['y']>=0&&b['width']>0&&b['height']>0&&b['x']+b['width']<=width&&b['y']+b['height']<=height
      end
      raise 'custom changed' if mode=='custom'&&text.map{|t|t['text']}.join!=o['customCopy']
      raise 'no-copy has text' if mode=='remove-all-copy'&&!text.empty?
      raise 'rewrite unreviewed' if mode=='ai-rewrite'&&(text.empty?||e['copyReviewed']!=true)
      raise 'background size mismatch' unless InputImage.inspect(internal_bytes(a['background']))['dimensions']==f['ruleTrace']['expectedDimensions']
    end
    if e=r['typographyEvidence']
      raise 'ink evidence binding mismatch' unless e['sourceHash']==parent['sourceHash']&&Digest::SHA256.hexdigest(JSON.generate(e))==r['typographyEvidenceHash']
      dimensions=InputImage.inspect(internal_bytes(r['reference']))['dimensions']
      raise 'ink evidence dimensions mismatch' unless [e['sourceWidth'],e['sourceHeight']]==dimensions
    end
    if r['output']
      AnalysisOutputContract.validate_render!(r.fetch('assets').fetch('plan').fetch('text'),f.fetch('ruleTrace').fetch('selectedOptions'))
      raise 'output hash mismatch' unless internal_digest(r['output'])==r['outputHash']
      info=InputImage.inspect(internal_bytes(r['output']));raise 'output dimensions/mime mismatch' unless info['mime']=='image/png'&&info['dimensions']==f['ruleTrace']['expectedDimensions']
      raise 'missing output provenance' unless r.dig('manifest','outputHash')==r['outputHash']&&r.dig('manifest','sourceHash')==parent['sourceHash']&&r.dig('manifest','backgroundHash')==r.dig('assets','backgroundHash')&&r.dig('manifest','planHash')==r.dig('assets','planHash')
    end
    raise 'false completion' if %w[candidate accepted rejected].include?(r['state'])&&(!r['output']||!r['assets'])
    raise 'unexpected output in incomplete state' if !%w[candidate accepted rejected].include?(r['state'])&&r['output']
    if %w[accepted rejected].include?(r['state'])
      v=r.fetch('review');raise 'invalid manual review' unless v['verdict']==r['state']&&v['outputHash']==r['outputHash']&&%w[note reviewer].all?{|k|v[k].is_a?(String)&&!v[k].strip.empty?}
    end
    true
  end
  def internal_read(id)
    path=internal_path(id);raise 'internal task missing' unless File.file?(path)
    r=JSON.parse(File.read(path));internal_verify(r);r
  end
  def internal_summary(r)
    r.select{|k,_|%w[id revision state error outputHash review blockers fixtureOnly].include?(k)}.merge('originalTaskId'=>r['frozen']['id'],'sourceHash'=>r['frozen']['sourceHash'],'workflow'=>'internal-reference','productionEnabled'=>false,'paidRequestsPaused'=>true)
  end
  def internal_list
    Dir.glob(File.join(internal_root,'*.json')).map do |p|
      begin;internal_summary(internal_read(File.basename(p,'.json')))
      rescue =>e;{'id'=>File.basename(p,'.json'),'state'=>'corrupt','error'=>e.message,'productionEnabled'=>false};end
    end
  end
  def internal_operation(d,offline:false)
    raise 'offline route cannot dispatch provider operations' if offline&&!%w[read write list policy].include?(d['op'])
    if offline&&d['op']=='policy'
      s=snapshot(d.fetch('originalTaskId'));o=s.fetch('ruleTrace').fetch('selectedOptions')
      return {'forbiddenSource'=>SharedTypography::FORBIDDEN.source,'modes'=>%w[ai-rewrite custom remove-all-copy].map{|m|[m,SharedTypography.contract(o.merge('mode'=>m))]}.to_h}
    end
    raise 'internal reference disabled' unless @internal_reference||offline
    case d['op']
    when 'provider-prepare','provider-mock-propose'
      frozen=JSON.parse(File.read(File.join(job(d['originalTaskId']),'generic-gc-plan.json')))
      if d['op']=='provider-prepare'
        ReferenceProvider.prepare(frozen,d.fetch('stage','layout-copy'),d['layout'])['binding'].merge('liveEnabled'=>false,'protocolVerifiedLive'=>false)
      else
        raise 'provider fixture route is mock-only' unless @mock
        fixtures=d.fetch('fixtures');raise 'two explicit mock responses required' unless fixtures.keys.sort==%w[background layout-copy]
        ReferenceProvider.propose(frozen,File.join(@data,'.reference-provider'),approval_for:lambda{|b|b},transport_for:lambda{|stage|lambda{|_,_,_|v=fixtures.fetch(stage);[v.fetch('http'),JSON.generate(v.fetch('response'))]}},mock:true)
      end
    when 'read';internal_read(d['id'])
    when 'list';internal_list
    when 'write'
      r=d.fetch('record');path=internal_path(r.fetch('id'));old=File.file?(path) ? internal_read(r['id']) : nil
      raise 'history revision conflict; reopen task' unless d['revision']==(old ? old['revision'] : -1)
      allowed={'awaiting-assets'=>%w[ready-to-compose],'ready-to-compose'=>%w[ready-to-compose composing awaiting-typography-review],'awaiting-typography-review'=>%w[awaiting-typography-review ready-to-compose],'composing'=>%w[candidate failed interrupted],'failed'=>%w[ready-to-compose],'interrupted'=>%w[ready-to-compose],'candidate'=>%w[candidate accepted rejected],'accepted'=>%w[accepted],'rejected'=>%w[rejected]}
      if old
        raise 'invalid state transition' unless allowed.fetch(old['state'],[]).include?(r['state'])
        %w[id version reference frozen frozenHash policyHash fixtureOnly].each{|k|raise "immutable #{k} changed" unless old[k]==r[k]}
        if %w[composing candidate accepted rejected].include?(old['state']);raise 'reviewed assets changed' unless old['assets']==r['assets'];end
        if old['output'];%w[output outputHash manifest typographyEvidence typographyEvidenceHash].each{|k|raise 'output changed' unless old[k]==r[k]};end
      else
        raise 'invalid new internal task' unless r['state']=='awaiting-assets'&&r['assets'].nil?&&r['output'].nil?
      end
      internal_verify(r);r['revision']=d['revision']+1;FileUtils.mkdir_p(internal_root,mode:0700);atomic(path,r);{'revision'=>r['revision']}
    else;raise 'unknown internal operation'
    end
  end
  def internal_recover
    return unless @internal_reference
    Dir.glob(File.join(internal_root,'*.json')).each do |p|
      begin
        r=internal_read(File.basename(p,'.json'));next unless r['state']=='composing'
        r['state']='interrupted';r['error']='Local composition interrupted; no model call or automatic retry';r['revision']+=1;r['events']<<{'event'=>'server-recovered-interruption','at'=>Time.now.utc.iso8601};atomic(p,r)
      rescue JSON::ParserError,RuntimeError,KeyError
        # Retain corrupt evidence untouched; internal_list reports a blocked record.
        next
      end
    end
  end
end
Bridge.include(BridgeInternalReference)
