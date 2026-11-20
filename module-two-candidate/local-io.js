// JXA host: only local file IO, no application automation and no credential access.
ObjC.import('Foundation');
function readText(p) { return ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(p,$.NSUTF8StringEncoding,null)); }
function writeText(p,s) { if (!$(s).writeToFileAtomicallyEncodingError(p,true,$.NSUTF8StringEncoding,null)) throw Error('write-failed'); }
function run(args) {
  var root=args[1]; eval(readText(root+'/frozen-draft.js')); eval(readText(root+'/provider-core.js'));
  if(args[0]==='bridge-prepare') {
    var source=JSON.parse(readText(args[2]+'/input.json'));
    FROZEN.prompt=source.prompt;
    FROZEN.call.aspectRatio=source.output.aspectRatio;
    var request=Provider.request(FROZEN,source.imageBase64);
    writeText(args[2]+'/request.json',JSON.stringify(request));
    return 'Prepared via existing provider adapter.';
  }
  if(args[0]==='prepare') {
    var data=$.NSData.dataWithContentsOfFile(root+'/'+FROZEN.reference.path);
    if(!data) throw Error('reference-missing');
    var payload=Provider.request(FROZEN,ObjC.unwrap(data.base64EncodedStringWithOptions(0)));
    writeText(args[2]+'/request.json',JSON.stringify(payload));
    writeText(args[2]+'/frozen-input.json',JSON.stringify(FROZEN,null,2));
    writeText(args[2]+'/prompt.txt',FROZEN.prompt);
    return 'Prepared local request; no network.';
  }
  if(args[0]==='parse') {
    var result=Provider.parse({http:Number(args[3]),body:readText(args[2]+'/response.json')});
    var bytes=$.NSData.alloc.initWithBase64EncodedStringOptions(result.image.data,0);
    if(!bytes || !bytes.writeToFileAtomically(args[2]+'/output.jpg',true)) throw Error('image-write-failed');
    delete result.image;
    writeText(args[2]+'/result.json',JSON.stringify(result,null,2));
    return 'Image received; visual acceptance pending.';
  }
  throw Error('unknown-operation');
}
