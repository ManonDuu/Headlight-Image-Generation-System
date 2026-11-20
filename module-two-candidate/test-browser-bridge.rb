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
Dir.mktmpdir('bridge-browser-') do |dir|
  server=nil;chrome=nil
  begin
    FileUtils.mkdir_p(File.join(dir,'downloads'))
    r,w=IO.pipe;server=Process.spawn({'PATH'=>'/usr/bin:/bin','GEMINI_API_KEY'=>'FAKE-browser-only'},'/usr/bin/ruby',File.join(ROOT,'bridge-server.rb'),'--mock','--gc-comparison-once','--port','8786','--data',File.join(dir,'jobs'),out:w,err:File::NULL,unsetenv_others:true);w.close
    raise 'no local server' unless IO.select([r],nil,nil,10)&&r.gets.include?('READY');r.close
    chrome=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9228',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','--no-default-browser-check','--disable-features=MediaRouter','--window-size=1200,1500','about:blank',out:File::NULL,err:File::NULL)
    pages=nil;100.times do
      begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9228,nil).get('/json/list').body);break if pages.any?;rescue;end;sleep 0.1
    end
    raise 'headless browser not available' unless pages&&pages.any?
    c=CDP.new(pages.find{|x|x['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable')
    c.call('Browser.setDownloadBehavior',behavior:'allow',downloadPath:File.join(dir,'downloads'))
    c.call('Page.navigate',url:'http://127.0.0.1:8786/')
    c.wait("document.getElementById('status').textContent==='本地服务已连接'")
    doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:'#source')['nodeId']
    c.call('DOM.setFileInputFiles',nodeId:node,files:[File.join(ROOT,'assets/81gMZuoRq6L._AC_SL1500_.jpg')])
    c.wait("!document.getElementById('freeze').disabled")
    c.eval_js("document.getElementById('freeze').click()")
    c.wait("typeof job!=='undefined' && job && job.state==='frozen'")
    id=c.eval_js('job.id')
    c.eval_js("document.getElementById('generate').click();document.getElementById('generate').click()")
    c.wait("job.state==='mock-result' && !document.getElementById('output').hidden && document.getElementById('output').naturalWidth===1856")
    raise 'auto accepted' unless c.eval_js("job.visualAcceptance==='not-evaluated'")
    c.eval_js("document.querySelectorAll('#checks fieldset').forEach(f=>{f.querySelector('textarea').value='Mock observation only';f.querySelector('input').value='whole mock image';});document.getElementById('review').click()")
    c.wait("job.visualAcceptance==='mock-review-only'")
    c.eval_js("document.getElementById('saveImage').click();document.getElementById('saveRecord').click()")
    100.times{break if Dir.glob(File.join(dir,'downloads','*.jpg')).any?&&Dir.glob(File.join(dir,'downloads','*.json')).any?;sleep 0.1}
    png=Dir.glob(File.join(dir,'downloads','*.jpg')).first;record=Dir.glob(File.join(dir,'downloads','*.json')).first
    raise 'download failed' unless png&&record
    raise 'image bytes changed' unless Digest::SHA256.file(png).hexdigest==c.eval_js('job.outputHash')
    raise 'record failed' unless JSON.parse(File.read(record))['visualAcceptance']=='mock-review-only'
    c.call('Page.reload');c.wait("document.getElementById('status').textContent==='本地服务已连接'")
    c.eval_js("document.getElementById('history').value=#{JSON.generate(id)};document.getElementById('load').click()")
    c.wait("typeof job!=='undefined' && job && job.id===#{JSON.generate(id)} && !document.getElementById('output').hidden")
    c.eval_js("document.getElementById('output').scrollIntoView({block:'center'})")
    shot=c.call('Page.captureScreenshot',format:'png',captureBeyondViewport:false)['data'];File.binwrite(File.join(ROOT,'diagnostics/browser-module-one.png'),Base64.decode64(shot))
    File.write(File.join(ROOT,'diagnostics/browser-test-result.txt'),"PASS: installed Chrome headless, temporary isolated profile. Imported actual local reference into MOCK loopback service; freeze, double-click protection, mock JPEG, pending acceptance, manual mock review, byte-identical JPEG download, record download, reload/recovery. No external model call; no real credential or personal browser profile.\n")
    # Hold the session refresh so edits while reset is pending cannot be silently erased.
    c.eval_js("const originalRefresh=refreshSession;refreshSession=async()=>{refreshSession=originalRefresh;await new Promise(r=>setTimeout(r,300));return originalRefresh();};document.getElementById('newTask').click()")
    c.wait("!document.getElementById('source').disabled && job===null")
    c.eval_js("document.getElementById('mode').value='custom';document.getElementById('ratio').value='custom';document.getElementById('copy').value='Exact Custom CASE';document.getElementById('width').value='2048';document.getElementById('height').value='2048';options()")
    doc=c.call('DOM.getDocument');node=c.call('DOM.querySelector',nodeId:doc['root']['nodeId'],selector:'#source')['nodeId']
    c.call('DOM.setFileInputFiles',nodeId:node,files:[File.join(ROOT,'assets/81gMZuoRq6L._AC_SL1500_.jpg')])
    c.wait("!document.getElementById('freeze').disabled")
    c.eval_js("document.getElementById('freeze').click()")
    begin;c.wait("job?.state==='frozen'&&job.mode==='custom'");rescue=>e;raise e.message+"; UI: "+c.eval_js("JSON.stringify({status:$('status').textContent,mode:job?.mode,state:job?.state,formMode:$('mode').value,copy:$('copy').value})").to_s;end
    custom_id=c.eval_js('job.id')
    raise 'custom copy not compiled' unless c.eval_js("job.prompt.includes('Exact Custom CASE')&&job.ruleTrace.selectedOptions.customCopy==='Exact Custom CASE'&&job.ruleTrace.output.aspectRatio==='1:1'")
    c.wait("session.mock&&canGenerate(job)&&!document.getElementById('generate').disabled")
    c.call('Page.reload');c.wait("document.getElementById('status').textContent==='本地服务已连接'")
    c.eval_js("document.getElementById('history').value=#{JSON.generate(custom_id)};document.getElementById('load').click()")
    c.wait("job?.id===#{JSON.generate(custom_id)}")
    raise 'option restoration failed' unless c.eval_js("document.getElementById('copy').value==='Exact Custom CASE'&&document.getElementById('ratio').value==='custom'&&document.getElementById('width').value==='2048'")
    c.wait("!document.getElementById('gcExperiment').hidden&&!document.getElementById('gcExperiment').disabled")
    c.eval_js("document.getElementById('gcExperiment').click()")
    c.wait("job?.experiment==='generateContent comparison'&&job.state==='mock-result'&&!document.getElementById('output').hidden")
    c.wait("session.gcComparison.remaining===0&&document.getElementById('gcExperiment').disabled")
    raise 'GC original byte hash missing' unless c.eval_js("job.outputHash&&job.analysisCalls===0&&job.visualAcceptance==='not-evaluated'")
    puts 'PASS Chrome selected GC comparison button: one mock result, original image displayed, independent quota consumed, no repeat.'
    puts 'PASS Chrome: original JPEG byte-identical download, review/reload, new-task reset, exact custom copy + native custom dimensions, history restores choices, independent new mock request remains available; duplicate execution protected. Zero model calls.'
  ensure
    [chrome,server].compact.each{|pid|Process.kill('TERM',pid) rescue nil};[chrome,server].compact.each{|pid|Process.wait(pid) rescue nil}
  end
end
