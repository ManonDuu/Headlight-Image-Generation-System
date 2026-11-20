ObjC.import('Foundation');
function run(args){
  function read(p){return ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(args[0]+'/'+p,$.NSUTF8StringEncoding,null));}
  eval(read('provider-core.js'));eval(read('module-flow.js'));eval(read('ui-state.js'));
  var n=0;function check(x){if(!x)throw Error('module assertion '+n);n++;}function rejects(fn){var yes=false;try{fn();}catch(e){yes=true;}check(yes);}
  var req={input:[{text:'test'},{data:'YWJj'}]},t=ModuleFlow.newTask();
  rejects(function(){ModuleFlow.freeze(t,req,null);});ModuleFlow.freeze(t,req,'fake-source-hash');
  rejects(function(){ModuleFlow.freeze(t,req,'hash');});ModuleFlow.mock(t,'success');check(t.acceptance==='not-evaluated');
  rejects(function(){ModuleFlow.mock(t,'success');});rejects(function(){ModuleFlow.review(t,'accepted','test');});
  t=ModuleFlow.newTask();ModuleFlow.freeze(t,req,'hash');ModuleFlow.mock(t,'failure');check(t.state==='stopped');rejects(function(){ModuleFlow.mock(t,'success');});
  t=ModuleFlow.newTask();ModuleFlow.freeze(t,req,'hash');rejects(function(){ModuleFlow.receive(t,{status:'incomplete'});});check(t.state==='stopped');
  var body={usage:{total_input_tokens:0,total_output_tokens:0,total_thought_tokens:0,total_tokens:0},status:'completed',model:'gemini-3.1-flash-image',steps:[{type:'model_output',content:[{type:'image',mime_type:'image/jpeg',data:ObjC.unwrap($.NSData.dataWithContentsOfFile(args[0]+'/fixtures/small-valid.jpg').base64EncodedStringWithOptions(0))}]}]};
  t=ModuleFlow.newTask();ModuleFlow.freeze(t,req,'hash');ModuleFlow.receive(t,body);check(t.acceptance==='not-evaluated');
  rejects(function(){ModuleFlow.review(t,'accepted','');});ModuleFlow.review(t,'rejected','Fixture only; visual failure');check(t.acceptance==='rejected');
  var s=UIState.derive({state:'stopped',hasImage:false,hasResult:false,approvalConsumed:true,connectionOK:true});check(!s.canRetry&&!s.canAutoAccept&&!s.showImage);check(s.remoteResult.indexOf('未知')===0);
  s=UIState.derive({state:'generated_pending_review',hasImage:true,hasResult:true});check(s.showImage&&s.visualAcceptance==='待人工验收'&&!s.canAutoAccept);
  new Function(read('module-one.js')); // syntax check only; browser file APIs are separate
  check(read('module-one.html').indexOf("connect-src 'none'")>=0);
  return 'PASS '+n+' module/state assertions plus UI JavaScript syntax. No network. Browser file APIs not exercised.';
}
