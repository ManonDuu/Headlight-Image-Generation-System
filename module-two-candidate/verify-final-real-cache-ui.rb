# Actual ordinary UI against existing local service; paid routes blocked in browser.
eval(File.read(File.join(__dir__,'test-real-result-browser.rb')).split("Dir.mktmpdir('real-result-browser-')").first,TOPLEVEL_BINDING,File.join(__dir__,'test-real-result-browser.rb'))
original=ROOT+'/bridge-jobs/19943cd47d3b42b02d8c8739'
protected_files=Dir[original+'/*'].select{|p|File.file?(p)}+Dir[ROOT+'/live-attempts/**/*'].select{|p|File.file?(p)}+[ROOT+'/LIVE-REQUESTS-PAUSED']
protected_hashes=protected_files.map{|p|[p,Digest::SHA256.file(p).hexdigest]}.to_h
Dir.mktmpdir('final-real-cache-') do |dir|
 pid=nil
 begin
  pid=Process.spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','--headless=new','--remote-debugging-address=127.0.0.1','--remote-debugging-port=9242',"--user-data-dir=#{dir}/chrome",'--disable-background-networking','--disable-component-update','--disable-sync','--no-first-run','about:blank',out:File::NULL,err:File::NULL)
  pages=nil;100.times{begin;pages=JSON.parse(Net::HTTP.new('127.0.0.1',9242,nil).get('/json/list').body);break if pages.any?;rescue SystemCallError;end;sleep 0.1};raise 'browser unavailable' unless pages
  c=CDP.new(pages.find{|v|v['type']=='page'}['webSocketDebuggerUrl']);c.call('Page.enable');c.call('Runtime.enable');c.call('Network.enable');c.call('Network.setBlockedURLs',urls:['https://*','*/api/generate','*/api/generic/*','*/api/analysis*','*/api/direct/*','*/api/experiment/*','*/api/analyze'])
  c.call('Page.navigate',url:'http://127.0.0.1:8773/');c.wait("!!session?.history&&!!globalThis.InkReviewUI")
  result=c.eval_js("(async()=>{const id='19943cd47d3b42b02d8c8739';$('history').value=id;await $('load').onclick();await $('openInkReview').onclick();const initial=InkReviewUI.task.status,record=InkReviewUI.task.record();const before={meaningChecked:$('inkMeaning').checked,sourceText:$('inkSourceText').value,continueDisabled:$('inkContinue').disabled};await $('inkMeasure').onclick();const refusal=$('inkStatus').textContent;$('inkCancel').click();await $('openInkReview').onclick();return {realService:true,sourceTask:id,reviewTaskId:initial.id,businessSpec:session.genericGC.businessSpec,paidPaused:session.paidRequestsPaused,sourceCandidatesPresent:!!record.assets?.plan?.evidence?.sourceBlocks,initialState:initial.state,currentState:InkReviewUI.task.status.state,reopenedSameTask:InkReviewUI.task.status.id===initial.id,before,refusal,outputHash:InkReviewUI.task.status.outputHash,modelCalls:0,manualCopySubstitution:false,meaningApprovalSubmitted:false};})()")
  raise 'unexpected real candidate or implicit approval' unless result['outputHash'].nil?&&result['before']['meaningChecked']==false&&result['reopenedSameTask']&&result['currentState']=='awaiting-assets'
  raise 'original or ledger changed' unless protected_hashes.all?{|p,h|Digest::SHA256.file(p).hexdigest==h}
  result['protectedFilesUnchanged']=protected_hashes.size
  File.write(ROOT+'/diagnostics/final-real-cache-ui-check.json',JSON.pretty_generate(result));puts JSON.pretty_generate(result)
 ensure
  Process.kill('TERM',pid) rescue nil;Process.wait(pid) rescue nil
 end
end
