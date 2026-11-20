require 'json';require 'net/http';require 'socket';require 'base64';require 'securerandom';require 'tmpdir';require 'fileutils';require 'digest'
ROOT=File.expand_path(__dir__)
class CDP
  def initialize(url)
    u=URI(url);@s=TCPSocket.new(u.host,u.port);@id=0
    key=Base64.strict_encode64(SecureRandom.random_bytes(16));@s.write("GET #{u.path} HTTP/1.1\r\nHost: #{u.host}:#{u.port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: #{key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
    h='';h<<@s.read(1) until h.end_with?("\r\n\r\n");raise 'websocket failed' unless h.include?('101')
  end
  def send_frame(payload)
    mask=SecureRandom.random_bytes(4);n=payload.bytesize;header=[0x81].pack('C')+(n<126 ? [0x80|n].pack('C') : n<65536 ? [0xfe,n].pack('Cn') : [0xff,n].pack('CQ>'))
    bytes=payload.bytes.each_with_index.map{|x,i|x^mask.getbyte(i%4)}.pack('C*');@s.write(header+mask+bytes)
  end
  def call(method,params={})
    @id+=1;id=@id;send_frame(JSON.generate(id:id,method:method,params:params))
    loop do
      raise 'CDP timed out' unless IO.select([@s],nil,nil,20)
      h=@s.read(2).bytes;n=h[1]&127;n=@s.read(2).unpack1('n') if n==126;n=@s.read(8).unpack1('Q>') if n==127
      m=(h[1]&128)!=0 ? @s.read(4).bytes : nil;raw=@s.read(n);raw=raw.bytes.each_with_index.map{|x,i|x^m[i%4]}.pack('C*') if m
      obj=JSON.parse(raw);next unless obj['id']==id;raise obj['error'].to_s if obj['error'];return obj['result']
    end
  end
  def eval_js(s)
    r=call('Runtime.evaluate',expression:s,awaitPromise:true,returnByValue:true)
    raise r['exceptionDetails'].to_s if r['exceptionDetails'];r.dig('result','value')
  end
  def wait(s)
    100.times{ return true if eval_js(s);sleep 0.1 };raise "browser condition timeout: #{s}"
  end
end
Dir.mktmpdir('real-result-browser-') do |dir|
  chrome=nil
  begin
    ledger_hashes=Dir[ROOT+'/live-attempts/**/*'].select{|p|File.file?(p)}.map{|p|[p,Digest::SHA256.file(p).hexdigest]}.to_h
    FileUtils.mkdir_p(dir+'/downloads')
    chrome=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9231',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','--no-default-browser-check','--disable-features=MediaRouter','about:blank',out:File::NULL,err:File::NULL)
    pages=nil;100.times do
      begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9231,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1
    end
    raise 'isolated Chrome unavailable' unless pages&&pages.any?
    c=CDP.new(pages.find{|x|x['type']=='page'}['webSocketDebuggerUrl'])
    c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable')
    c.call('Network.setBlockedURLs',urls:['*/api/generate','*/api/experiment/*','*/api/analyze'])
    c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:dir+'/downloads')
    c.call('Page.navigate',url:'http://127.0.0.1:8773/')
    c.wait("typeof session!=='undefined'&&session?.history?.length>0")
    raise 'not consumed real session' unless c.eval_js("session.mock===false&&session.gcComparison.remaining===0")
    id='9dce1ce10578330f6d472373'
    c.eval_js("document.getElementById('history').value=#{JSON.generate(id)};document.getElementById('load').click()")
    c.wait("job?.id===#{JSON.generate(id)}&&!document.getElementById('output').hidden&&document.getElementById('output').naturalWidth===1856")
    raise 'wrong native dimensions' unless c.eval_js("document.getElementById('output').naturalHeight===2304")
    review=JSON.parse(File.read(ROOT+'/GC-VISUAL-REVIEW.json'))
    c.eval_js("(()=>{const review=#{JSON.generate(review)};document.querySelectorAll('#checks fieldset').forEach(f=>{const d=review.decisions.find(x=>x.ruleId===f.dataset.rule);f.querySelector('select').value=d.verdict;f.querySelector('textarea').value=d.note;f.querySelector('input').value=d.evidence[0].location;});document.getElementById('review').click();})()")
    c.wait("job.visualAcceptance==='manual-rejected'")
    c.eval_js("document.getElementById('saveImage').click();document.getElementById('saveRecord').click()")
    100.times{break if Dir[dir+'/downloads/*.jpg'].any?&&Dir[dir+'/downloads/*.json'].any?;sleep 0.1}
    jpg=Dir[dir+'/downloads/*.jpg'].first;record=Dir[dir+'/downloads/*.json'].first
    raise 'download missing' unless jpg&&record
    sha=Digest::SHA256.file(jpg).hexdigest
    raise 'download modified original bytes' unless sha=='3b3113166988b49c8b471297fbf30a0ca216655cc64db4538d479b36e8850fa0'
    raise 'review download not saved' unless JSON.parse(File.read(record))['visualAcceptance']=='manual-rejected'
    c.call('Page.reload');c.wait("typeof session!=='undefined'&&session?.history?.length>0")
    c.eval_js("document.getElementById('history').value=#{JSON.generate(id)};document.getElementById('load').click()")
    c.wait("job?.visualAcceptance==='manual-rejected'&&!document.getElementById('output').hidden")
    raise 'failed quality not restored' unless c.eval_js("Array.from(document.querySelectorAll('#checks fieldset select')).filter(x=>x.value==='fail').length===2")
    c.eval_js("document.getElementById('history').value='3bdaaef4bf062f158e862cab';document.getElementById('load').click()")
    c.wait("job?.id==='3bdaaef4bf062f158e862cab'&&job.state==='stopped'")
    raise 'incomplete misreported success' unless c.eval_js("document.getElementById('output').hidden&&document.getElementById('saveImage').disabled&&document.getElementById('review').disabled")
    raise 'exhausted budget enabled' unless c.eval_js("document.getElementById('generate').disabled&&document.getElementById('gcExperiment').disabled")
    raise 'ledger changed' unless ledger_hashes.all?{|p,h|Digest::SHA256.file(p).hexdigest==h}
    result={state:'passed',realPreview:true,nativeDimensions:[1856,2304],downloadSHA256:sha,downloadByteIdentical:true,
      manualQualityReviewSaved:'manual-rejected',historyRestored:true,failedResultNotSuccess:true,
      exhaustedQuotaDisabled:true,paidRoutesBlockedInBrowser:true,ledgerBindingsUnchanged:ledger_hashes.size,newModelCalls:0}
    File.write(ROOT+'/REAL-RESULT-WORKBENCH-ACCEPTANCE.json',JSON.pretty_generate(result));puts JSON.generate(result)
  ensure
    if chrome;Process.kill('TERM',chrome) rescue nil;Process.wait(chrome) rescue nil;end
  end
end
