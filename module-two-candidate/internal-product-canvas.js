'use strict';
// Pixel-preserving foundation used by the local product editor; no model routes.
globalThis.ProductCanvasFoundation = (() => {
  const need=(v,m)=>{if(!v)throw Error(m);};
  const sha=async b=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await b.arrayBuffer()))).map(v=>v.toString(16).padStart(2,'0')).join('');
  const canvas=(w,h)=>{need(Number.isInteger(w)&&Number.isInteger(h)&&w>0&&h>0&&w*h<=16000000,'invalid canvas size');const c=document.createElement('canvas');c.width=w;c.height=h;return c;};
  const png=c=>new Promise((ok,no)=>c.toBlob(b=>b?ok(b):no(Error('PNG export failed')),'image/png'));
  function copyText(text,{mode,role,protectedTokens=[],preserveCase=false},policy){
    need(typeof text==='string'&&policy.modes[mode],'invalid text mode');
    need(!new RegExp(policy.forbiddenSource,'i').test(text),'forbidden text conflict; no silent replacement');
    if(mode==='remove-all-copy')return '';
    if(preserveCase||mode==='custom'||mode==='preserve-reference')return text;
    const c=policy.modes[mode];
    if(role==='brand'){need(c.brand==='UPPERCASE','no supplied brand authority');return text.toUpperCase();}
    if(!['title','subtitle'].includes(role))return text; // No invented body casing.
    need(c[role]===(role==='title'?'Title Case':'Sentence case'),'unsupported shared case contract');
    const protectedSet=new Set(protectedTokens);let first=true;
    return text.replace(/[\p{L}\p{N}]+(?:[._-][\p{L}\p{N}]+)*/gu,word=>{
      const preserve=protectedSet.has(word)||/\d/.test(word)||/^(LED|HID|IP|CANBUS)$/i.test(word);
      const initial=first;first=false;
      if(preserve)return word;
      const lower=word.toLowerCase();return role==='title'||initial?lower[0].toUpperCase()+lower.slice(1):lower;
    });
  }
  // Include every nonzero coverage pixel; faint silver edges are protected too.
  function visibleBounds(image,mask=null){
    const {width:w,height:h,data:d}=image;let left=w,top=h,right=-1,bottom=-1;
    for(let y=0;y<h;y++)for(let x=0;x<w;x++){const i=y*w+x;if(Math.round(d[4*i+3]*(mask?mask[i]:255)/255)>0){left=Math.min(left,x);right=Math.max(right,x);top=Math.min(top,y);bottom=Math.max(bottom,y);}}
    need(right>=left,'product has no visible pixels');return {x:left,y:top,width:right-left+1,height:bottom-top+1};
  }
  class Session {
    #source;#mask;#sourceHash;#maskHash;#policy;#enabled;#transform={x:0,y:0,scale:1,rotation:0};
    #state='empty';#background=null;#shadow=null;#text=[];#clean=false;
    constructor({enabled=false,policy}){this.#enabled=enabled;this.#policy=structuredClone(policy);}
    get state(){return this.#state;}
    async load(source,{sourceHash,mask=null,maskHash=null}){
      need(this.#enabled,'internal feature disabled');need(this.#state==='empty','source is immutable; create a new session');
      need(source instanceof Blob&&await sha(source)===sourceHash,'source hash mismatch');
      const decoded=await createImageBitmap(source);let maskBitmap=null;
      if(mask){need(mask instanceof Blob&&await sha(mask)===maskHash,'mask hash mismatch');maskBitmap=await createImageBitmap(mask);need(maskBitmap.width===decoded.width&&maskBitmap.height===decoded.height,'mask dimensions mismatch');}
      this.#source=decoded;this.#mask=maskBitmap;this.#sourceHash=sourceHash;this.#maskHash=maskHash;this.#state='loaded';
    }
    transform(t){
      need(this.#state!=='empty','source required');need(Object.keys(t).sort().join(',')==='rotation,scale,x,y','only uniform scale/translation/rotation allowed');
      need(Object.values(t).every(Number.isFinite)&&t.scale>0,'invalid or mirrored transform');this.#transform={...t};this.#state='prepared';
    }
    async layers({background=null,shadow=null,backgroundConfirmedClean=false,text=[]}){
      need(this.#state!=='empty','source required');
      // Immutable snapshots; callers cannot alter a canvas after review.
      this.#background=background?await createImageBitmap(background):null;this.#shadow=shadow?await createImageBitmap(shadow):null;
      this.#clean=backgroundConfirmedClean;this.#text=structuredClone(text);this.#state='prepared';
    }
    async exportPNG({width,height}){
      need(this.#enabled&&this.#source,'source required');need(this.#clean,'background old-product clearance not confirmed');
      const text=this.#text.map(t=>copyText(t.text,t,this.#policy));
      const engine=globalThis.InterTextFoundation;
      need(!text.some(Boolean)||engine?.ready,'Inter embedded rendering not ready; text-layer export blocked');
      const textPlans=this.#text.filter((t,i)=>text[i]).map(t=>engine.layout(t,this.#policy,copyText));
      const out=canvas(width,height),ctx=out.getContext('2d'),p=canvas(this.#source.width,this.#source.height),pc=p.getContext('2d');
      pc.drawImage(this.#source,0,0);
      if(this.#mask){pc.globalCompositeOperation='destination-in';pc.drawImage(this.#mask,0,0);pc.globalCompositeOperation='source-over';}
      const {x,y,scale,rotation}=this.#transform,a=rotation*Math.PI/180;
      const visible=visibleBounds(pc.getImageData(0,0,p.width,p.height));
      const corners=[[visible.x,visible.y],[visible.x+visible.width,visible.y],[visible.x,visible.y+visible.height],[visible.x+visible.width,visible.y+visible.height]].map(([u,v])=>[x+scale*(u*Math.cos(a)-v*Math.sin(a)),y+scale*(u*Math.sin(a)+v*Math.cos(a))]);
      need(corners.every(([u,v])=>u>=-1e-8&&v>=-1e-8&&u<=width+1e-8&&v<=height+1e-8),'product would be cropped');
      for(const layer of [this.#background,this.#shadow]){if(layer){need(layer.width===width&&layer.height===height,'layer size mismatch; no hidden stretch');ctx.drawImage(layer,0,0);}}
      const bounds={left:Math.min(...corners.map(c=>c[0])),right:Math.max(...corners.map(c=>c[0])),top:Math.min(...corners.map(c=>c[1])),bottom:Math.max(...corners.map(c=>c[1]))};
      const textLayer=canvas(width,height),tc=textLayer.getContext('2d'),productLayer=canvas(width,height),ac=productLayer.getContext('2d');
      ac.translate(x,y);ac.rotate(a);ac.scale(scale,scale);ac.drawImage(p,0,0);
      for(const plan of textPlans){const b=plan.box;need(b.x>=0&&b.y>=0&&b.x+b.width<=width&&b.y+b.height<=height,'text box outside output');engine.draw(tc,plan);}
      const ta=tc.getImageData(0,0,width,height).data,pa=ac.getImageData(0,0,width,height).data;
      for(let i=3;i<ta.length;i+=4)need(!(ta[i]>0&&pa[i]>0),'text glyph overlaps protected product alpha');
      ctx.drawImage(textLayer,0,0);
      // Product is last: background/shadow cannot repaint its opaque pixels.
      ctx.translate(x,y);ctx.rotate(a);ctx.scale(scale,scale);ctx.drawImage(p,0,0);
      const blob=await png(out),outputHash=await sha(blob);this.#state='exported-fixture-or-unreviewed';
      return {blob,manifest:{version:'canvas-product-foundation-2',visibleSourceBounds:visible,sourceHash:this.#sourceHash,maskHash:this.#maskHash,transform:{...this.#transform},width,height,outputHash,
        layers:['background','shadow','independent-text','original-product'],interReady:!!engine?.ready,textPlans,sourcePixelsReused:true,resampled:scale!==1||rotation!==0||!Number.isInteger(x)||!Number.isInteger(y),
        maskOrigin:'caller-provided-unverified',backgroundClearance:'caller-confirmation-not-automatic-detection',productIdentityAccepted:false,state:this.#state}};
    }
  }
  async function download(result,name='INTERNAL-unreviewed.png'){
    need(await sha(result.blob)===result.manifest.outputHash,'download hash mismatch');const url=URL.createObjectURL(result.blob),a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
  }
  return Object.freeze({Session,copyText,sha,download,visibleBounds,productionEnabled:false});
})();
