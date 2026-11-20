ObjC.import('Foundation');
function run(args) {
  function read(p){return ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(p,$.NSUTF8StringEncoding,null));}
  eval(read(args[0]+'/frozen-draft.js')); eval(read(args[0]+'/provider-core.js'));
  var passed=0;
  function check(ok){if(!ok)throw Error('assertion '+passed);passed++;}
  function reject(fn){var caught=false;try{fn();}catch(e){caught=true;}check(caught);}
  var fixture=ObjC.unwrap($.NSData.dataWithContentsOfFile(args[0]+'/fixtures/small-valid.jpg').base64EncodedStringWithOptions(0));
  var body=Provider.request(FROZEN,fixture);
  check(body.model==='gemini-3.1-flash-image' && body.store===false);
  check(body.input.length===2 && body.response_format.image_size==='2K');
  check(!Object.prototype.hasOwnProperty.call(body.input[1],'resolution'));
  check(!body.tools && !body.previous_interaction_id && !body.background);
  check(body.generation_config.max_output_tokens===4096);
  var png={type:'image',mime_type:'image/jpeg',data:fixture};
  function response(content){return {http:200,body:{model:'gemini-3.1-flash-image',status:'completed',usage:{total_input_tokens:100,total_output_tokens:1680,total_thought_tokens:100,total_tokens:1880},steps:[{type:'thought',signature:'not-an-image'},{type:'model_output',content:content}]}};}
  var task={state:'planned'},calls=0;
  var out=Provider.execute(task,function(){calls++;return response([png]);},body,260000);
  check(out.visualAcceptance==='not-evaluated' && task.state==='generated-pending-review');
  reject(function(){Provider.execute(task,function(){calls++;},body,260000);});check(calls===1);
  task={state:'planned'};
  reject(function(){Provider.execute(task,function(){calls++;},body,259999);});check(!task.attempted && calls===1);
  ['timeout','HTTP 400','HTTP 429','HTTP 500'].forEach(function(reason){
    var t={state:'planned'},n=0;
    reject(function(){Provider.execute(t,function(){n++;throw Error(reason);},body,260000);});
    check(n===1 && t.state==='stopped');
    reject(function(){Provider.execute(t,function(){n++;},body,260000);}); check(n===1);
  });
  reject(function(){Provider.parse(response([]));});
  reject(function(){Provider.parse(response([png,png]));});
  reject(function(){Provider.parse({http:200,body:'bad json'});});
  reject(function(){Provider.parse({http:400,body:{}});});
  var incomplete=response([png]);incomplete.body.status='in_progress';reject(function(){Provider.parse(incomplete);});
  var recorded=JSON.parse(read(args[0]+'/fixtures/recorded-incomplete-20261017.json'));
  var recordedTask={state:'planned'},recordedCalls=0;
  reject(function(){Provider.execute(recordedTask,function(){recordedCalls++;return {http:200,body:recorded};},body,260000);});
  check(recordedTask.state==='stopped'&&recordedCalls===1&&!recorded.steps);
  reject(function(){Provider.execute(recordedTask,function(){recordedCalls++;return {http:200,body:recorded};},body,260000);});
  check(recordedCalls===1&&recorded.usage.total_output_tokens===1025);
  var wrong=response([png]);wrong.body.model='other';reject(function(){Provider.parse(wrong);});
  var nested={state:'planned'},nestedCalls=0;
  Provider.execute(nested,function(){nestedCalls++;reject(function(){Provider.execute(nested,function(){nestedCalls++;},body,260000);});return response([png]);},body,260000);
  check(nestedCalls===1);
  check(FROZEN.regions.length===5 && FROZEN.approved===false && FROZEN.call.realEnabled===false);
  check(body.response_format.mime_type==='image/jpeg'&&!Object.prototype.hasOwnProperty.call(body.response_format,'delivery'));
  check(out.outputFilename==='output.jpg'&&out.image.data===fixture&&out.dimensions.width===16);
  reject(function(){Provider.parse(response([{type:'image',mime_type:'image/png',data:fixture}]));});
  reject(function(){Provider.parse(response([{type:'image',mime_type:'image/jpeg',data:'iVBORw0KGgo='}]));});
  reject(function(){Provider.parse(response([{type:'image',mime_type:'image/jpeg',uri:'https://example.com/image.jpg'}]));});
  reject(function(){Provider.parse(response([{type:'image',mime_type:'image/jpeg',data:fixture.slice(0,-8)}]));});
  reject(function(){Provider.jpegInfo('/9j/2Q==');});
  reject(function(){Provider.jpegInfo('@@@@');});
  var noUsage=response([png]);delete noUsage.body.usage;reject(function(){Provider.parse(noUsage);});
  var over=response([png]);over.body.usage.total_thought_tokens=4096;reject(function(){Provider.parse(over);});
  var incompleteImage=response([png]);incompleteImage.body.status='incomplete';reject(function(){Provider.parse(incompleteImage);});
  return 'PASS '
+passed+' provider assertions. No API, credentials or image uploads.';
}
