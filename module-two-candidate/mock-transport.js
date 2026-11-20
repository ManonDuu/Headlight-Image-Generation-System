ObjC.import('Foundation');
function run(args) {
  var scenario=args[1];
  if(scenario==='timeout') throw Error('mock timeout at 180 seconds; no network');
  if(scenario==='error') throw Error('mock HTTP 400; no network');
  var fixture=$.NSData.dataWithContentsOfFile(args[2]+'/fixtures/small-valid.jpg');
  var image={type:'image',mime_type:'image/jpeg',data:ObjC.unwrap(fixture.base64EncodedStringWithOptions(0))};
  var body={model:'gemini-3.1-flash-image',status:'completed',usage:{total_input_tokens:0,total_output_tokens:0,total_thought_tokens:0,total_tokens:0},steps:[{type:'model_output',content:scenario==='multiple'?[image,image]:[image]}]};
  var text=scenario==='malformed'?'not json':JSON.stringify(body);
  if(!$(text).writeToFileAtomicallyEncodingError(args[0]+'/response.json',true,$.NSUTF8StringEncoding,null)) throw Error('write-failed');
  return 'Fixture only: zero API calls, zero images generated, zero cost.';
}
