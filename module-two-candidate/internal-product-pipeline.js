'use strict';
// Internal only: no fetch, model, worker or production entrypoint.
globalThis.ProductPipeline = (() => {
  const F=ProductCanvasFoundation;
  const need=(v,m)=>{if(!v)throw Error(m);};
  const png=c=>new Promise((yes,no)=>c.toBlob(b=>b?yes(b):no(Error('PNG export failed')),'image/png'));
  const evidence=e=>e&&typeof e.reviewer==='string'&&e.reviewer.trim()&&typeof e.note==='string'&&e.note.trim();
  class Pipeline {
    #enabled;#policy;#source;#hash;#w;#h;#mask=null;#maskHash=null;#maskOK=false;#origin;#risks=[];
    #position=null;#positionEvidence=null;#maskEvidence=null;#text=[];#layoutOK=false;#background=null;#backgroundEvidence=null;#result=null;
    #state='awaiting-source';#history=['awaiting-source'];
    constructor({enabled=false,policy}){this.#enabled=enabled;this.#policy=structuredClone(policy);}
    #set(s){this.#state=s;this.#history.push(s);}
    #invalidate(){this.#result=null;this.#layoutOK=false;this.#background=null;this.#backgroundEvidence=null;}
    get status(){return structuredClone({state:this.#state,sourceHash:this.#hash,maskHash:this.#maskHash,maskOrigin:this.#origin,maskReady:this.#maskOK,risks:this.#risks,history:this.#history,productionEnabled:false});}
    async load(source,sourceHash){
      need(this.#enabled,'internal feature disabled');need(!this.#source,'source immutable');
      need(source instanceof Blob&&await F.sha(source)===sourceHash,'source hash mismatch');
      const b=await createImageBitmap(source);need(b.width*b.height<=16000000,'source too large');
      const c=document.createElement('canvas');c.width=b.width;c.height=b.height;const ctx=c.getContext('2d');ctx.drawImage(b,0,0);b.close();
      const pixels=ctx.getImageData(0,0,c.width,c.height),d=pixels.data,n=c.width*c.height;
      let transparent=0,partial=0,visible=0;for(let i=0;i<n;i++){const a=d[i*4+3];if(a<255)transparent++;if(a>0)visible++;if(a>0&&a<255)partial++;}
      need(visible,'empty transparent source');this.#source=source;this.#hash=sourceHash;this.#w=c.width;this.#h=c.height;this.#set('source-verified');
      if(transparent){
        this.#origin='original-alpha';this.#maskOK=true;
        this.#risks=['Original alpha reused; subject completeness and placement still require review.',...(partial?['Partial alpha retained unchanged; edge colour/halo and canvas premultiplication require visual review.']:[])];
      }else{
        const white=i=>d[i*4]>=250&&d[i*4+1]>=250&&d[i*4+2]>=250;
        const border=[];for(let y=0;y<c.height;y++)for(let x=0;x<c.width;x++)if(!x||!y||x===c.width-1||y===c.height-1)border.push(y*c.width+x);
        if(!border.every(white)){
          this.#origin='unsupported-background';this.#risks=['Non-white/subject-touching border: no automatic mask candidate. Provide reviewed alpha/mask.'];this.#set('awaiting-ready');return this.status;
        }
        const removed=new Uint8Array(n),queue=new Int32Array(n);let head=0,tail=0;
        const add=i=>{if(!removed[i]&&white(i)){removed[i]=1;queue[tail++]=i;}};border.forEach(add);
        while(head<tail){const i=queue[head++],x=i%c.width,y=Math.floor(i/c.width);if(x)add(i-1);if(x+1<c.width)add(i+1);if(y)add(i-c.width);if(y+1<c.height)add(i+c.width);}
        if(tail===n){this.#origin='ambiguous-white';this.#risks=['All-white image: white product cannot be distinguished from background.'];this.#set('awaiting-ready');return this.status;}
        const m=ctx.createImageData(c.width,c.height);let enclosedWhite=0;
        for(let i=0;i<n;i++){m.data.set([255,255,255,removed[i]?0:255],i*4);if(!removed[i]&&white(i))enclosedWhite++;}
        ctx.putImageData(m,0,0);this.#mask=await png(c);this.#maskHash=await F.sha(this.#mask);this.#origin='border-connected-near-white-candidate-v1';
        this.#risks=['Candidate only: white/silver product connected to white border may be removed.', 'No matting/decontamination: reflections and semi-transparent edges need manual review.',`Enclosed near-white pixels retained (${enclosedWhite}); holes cannot be distinguished from highlights.`];
      }
      this.#set('awaiting-mask-position');return this.status;
    }
    candidate(){return {blob:this.#mask,sourceHash:this.#hash,maskHash:this.#maskHash,algorithm:this.#origin,threshold:250,connectivity:4,requiresConfirmation:!this.#maskOK,risks:[...this.#risks]};}
    confirmMask(e){need(this.#mask&&evidence(e)&&e.sourceHash===this.#hash&&e.maskHash===this.#maskHash,'review must bind candidate and source hashes');this.#maskEvidence=structuredClone(e);this.#maskOK=true;this.#invalidate();this.#set('awaiting-mask-position');}
    position(plan,e){
      need(this.#source,'source required');need(evidence(e)&&e.sourceHash===this.#hash,'placement evidence required');
      need(Object.keys(plan).sort().join(',')==='height,rotation,scale,width,x,y','only 2D uniform transform and output dimensions');
      const {width,height,x,y,scale,rotation}=plan;need([width,height].every(v=>Number.isInteger(v)&&v>0)&&width*height<=16000000,'invalid output');
      need([x,y,scale,rotation].every(Number.isFinite)&&scale>0,'invalid transform');const a=rotation*Math.PI/180;
      need([[0,0],[this.#w,0],[0,this.#h],[this.#w,this.#h]].every(([u,v])=>{const X=x+scale*(u*Math.cos(a)-v*Math.sin(a)),Y=y+scale*(u*Math.sin(a)+v*Math.cos(a));return X>=0&&Y>=0&&X<=width&&Y<=height;}),'placement crops original');
      this.#position={...plan};this.#positionEvidence=structuredClone(e);this.#invalidate();this.#set(this.#maskOK?'awaiting-copy-preflight':'awaiting-ready');
    }
    async preflight(text=[]){
      need(this.#maskOK&&this.#position,'reviewed mask/placement required');this.#invalidate();this.#text=structuredClone(text);
      // Reuse exactly the export checks, including text/product overlap, before background work.
      const s=await this.#session();await s.layers({backgroundConfirmedClean:true,text:this.#text});await s.exportPNG(this.#position);
      this.#layoutOK=true;this.#set('awaiting-background');
    }
    async background(blob,e){
      need(this.#layoutOK,'copy preflight required');need(blob instanceof Blob&&evidence(e)&&e.sourceHash===this.#hash&&e.oldProductAbsent===true&&e.backgroundHash===await F.sha(blob),'reviewed clean background with matching hashes required');
      const b=await createImageBitmap(blob);const fits=b.width===this.#position.width&&b.height===this.#position.height;b.close();need(fits,'background dimensions mismatch');
      this.#background=blob;this.#backgroundEvidence=structuredClone(e);this.#result=null;this.#set('ready-to-compose');
    }
    async #session(){const s=new F.Session({enabled:true,policy:this.#policy});await s.load(this.#source,{sourceHash:this.#hash,mask:this.#mask,maskHash:this.#maskHash});const {x,y,scale,rotation}=this.#position;s.transform({x,y,scale,rotation});return s;}
    async compose(){
      need(this.#layoutOK&&this.#maskOK&&this.#positionEvidence&&this.#backgroundEvidence&&this.#background,'waiting for reliable mask, position and clean background evidence');
      const s=await this.#session();await s.layers({background:this.#background,backgroundConfirmedClean:true,text:this.#text});this.#result=await s.exportPNG(this.#position);
      this.#result.manifest.pipeline={maskOrigin:this.#origin,maskEvidence:this.#maskEvidence,positionEvidence:this.#positionEvidence,backgroundEvidence:this.#backgroundEvidence,risks:[...this.#risks],originalBlobUnchanged:await F.sha(this.#source)===this.#hash,reviewStatus:'internal-unaccepted'};
      this.#set('awaiting-download');return {blob:this.#result.blob,manifest:structuredClone(this.#result.manifest)};
    }
    async download(name='INTERNAL-pipeline-unreviewed.png'){need(this.#result,'composition required');await F.download(this.#result,name);this.#set('download-dispatched');}
  }
  return Object.freeze({Pipeline,productionEnabled:false});
})();
