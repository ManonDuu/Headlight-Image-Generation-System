// Pure, synchronous adapter. No network, filesystem, environment or credentials.
var Provider = (function () {
  function assert(ok, why) { if (!ok) throw new Error(why); }
  // Decode and inspect JPEG markers; no re-encoding or pixel transformations.
  // The host decoder also checks readability and output dimensions before delivery.
  function jpegInfo(data) {
    assert(typeof data==='string' && data.length<=40000000 && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(data), 'invalid-base64');
    var abc='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/',pad=data.slice(-2)==='=='?2:data.slice(-1)==='='?1:0;
    var bytes=new Uint8Array(data.length/4*3-pad),q=0;
    for(var i=0;i<data.length;i+=4){var a=abc.indexOf(data[i]),b=abc.indexOf(data[i+1]),c=abc.indexOf(data[i+2]),d=abc.indexOf(data[i+3]);
      bytes[q++]=(a<<2)|(b>>4);if(q<bytes.length)bytes[q++]=((b&15)<<4)|(c>>2);if(q<bytes.length)bytes[q++]=((c&3)<<6)|d;
    }
    assert(bytes.length>12&&bytes[0]===255&&bytes[1]===216,'invalid-jpeg-signature');
    var pos=2,w=0,h=0,scan=false;
    while(pos<bytes.length){
      assert(bytes[pos]===255,'invalid-jpeg-marker');while(bytes[pos]===255)pos++;
      var marker=bytes[pos++];
      if(marker===217){assert(scan&&w>0&&h>0&&pos===bytes.length,'incomplete-jpeg');return {width:w,height:h};}
      assert(marker!==216&&marker!==0&&!(marker>=208&&marker<=215),'unexpected-jpeg-marker');
      assert(pos+2<=bytes.length,'truncated-jpeg');var len=(bytes[pos]<<8)|bytes[pos+1];assert(len>=2&&pos+len<=bytes.length,'truncated-jpeg-segment');
      if([192,193,194,195,197,198,199,201,202,203,205,206,207].indexOf(marker)>=0){assert(len>=8,'invalid-jpeg-frame');h=(bytes[pos+3]<<8)|bytes[pos+4];w=(bytes[pos+5]<<8)|bytes[pos+6];}
      pos+=len;
      if(marker===218){scan=true;while(pos<bytes.length){if(bytes[pos]!==255){pos++;continue;}var next=bytes[pos+1];if(next===0||(next>=208&&next<=215)){pos+=2;continue;}break;}}
    }
    throw Error('missing-jpeg-end');
  }
  function request(f, image64) {

    assert(f.call.model === 'gemini-3.1-flash-image', 'model-changed');
    assert(f.call.maxOutputTokens === 4096 && f.call.requests === 1 && f.call.retries === 0, 'policy-changed');
    assert(f.call.imageSize === '2K' && ['1:1','4:5','5:4','3:4','4:3','9:16','16:9','2:3','3:2'].indexOf(f.call.aspectRatio)>=0, 'format-changed');
    jpegInfo(image64);
    return {model:f.call.model, store:false, input:[{type:'text',text:f.prompt},{type:'image',mime_type:'image/jpeg',data:image64}],
      response_format:{type:'image',mime_type:'image/jpeg',image_size:'2K',aspect_ratio:f.call.aspectRatio},
      generation_config:{max_output_tokens:4096,thinking_level:'minimal'}};
  }
  function parse(response) {
    assert(response.http === 200, 'http-' + response.http);
    var body = typeof response.body === 'string' ? JSON.parse(response.body) : response.body;
    assert(body.model === 'gemini-3.1-flash-image', 'unexpected-model');
    assert(body.status === 'completed', 'incomplete-or-blocked');
    assert(Array.isArray(body.steps), 'missing-steps');
    var images=[];
    body.steps.forEach(function(step) {
      if (step.type === 'model_output') (step.content || []).forEach(function(c) { if(c.type === 'image') images.push(c); });
    });
    assert(images.length === 1, 'image-count-' + images.length);
    assert(images[0].mime_type === 'image/jpeg' && !images[0].uri, 'expected-inline-jpeg');
    var dimensions=jpegInfo(images[0].data);
    var usage=body.usage;
    assert(usage&&['total_input_tokens','total_output_tokens','total_thought_tokens','total_tokens'].every(function(k){return Number.isSafeInteger(usage[k])&&usage[k]>=0;}),'missing-or-invalid-usage');
    assert(usage.total_input_tokens<=25600&&usage.total_output_tokens+usage.total_thought_tokens<=4096,'usage-exceeds-allowance');

    return {state:'generated-pending-review',visualAcceptance:'not-evaluated',image:images[0],dimensions:dimensions,outputMime:'image/jpeg',outputFilename:'output.jpg',usage:usage};
  }
  function execute(task, transport, requestBody, budget) {
    assert(task.state === 'planned' && !task.attempted, 'already-attempted');
    assert(Number.isSafeInteger(budget) && budget >= 260000, 'budget-insufficient');
    task.attempted=true; task.state='running'; task.calls=1;
    try { var result=parse(transport(requestBody, {timeoutSeconds:180,retries:0})); task.state=result.state; return result; }
    catch(e) { task.state='stopped'; throw e; }
  }
  return {request:request,parse:parse,execute:execute,jpegInfo:jpegInfo};
}());
