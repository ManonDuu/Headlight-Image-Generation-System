ObjC.import('Vision');
ObjC.import('Foundation');
function run(args){
 const url=$.NSURL.fileURLWithPath(args[0]);
 const request=$.VNRecognizeTextRequest.alloc.init;
 request.recognitionLevel=0;
 request.usesLanguageCorrection=false;
 const handler=$.VNImageRequestHandler.alloc.initWithURLOptions(url,$({}));
 const error=Ref();if(!handler.performRequestsError($([request]),error))throw Error('Native OCR failed');
 const results=request.results,lines=[];
 for(let i=0;i<results.count;i++){const o=results.objectAtIndex(i),c=o.topCandidates(1).firstObject;const text=ObjC.unwrap(c.string),words=[];const re=/\S+/g;let m;
 while((m=re.exec(text))!==null){const err=Ref();const box=c.boundingBoxForRangeError($.NSMakeRange(m.index,m[0].length),err);if(box)words.push({text:m[0],start:m.index,end:m.index+m[0].length,quad:[box.topLeft,box.topRight,box.bottomRight,box.bottomLeft].map(p=>[Number(p.x),1-Number(p.y)])});}
 lines.push({text,confidence:Number(c.confidence),words,quad:[o.topLeft,o.topRight,o.bottomRight,o.bottomLeft].map(p=>[Number(p.x),1-Number(p.y)])});}
 return JSON.stringify({version:'local-vision-ocr-1',engine:'macOS Vision',network:false,lines});
}
