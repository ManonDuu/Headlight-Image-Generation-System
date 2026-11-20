'use strict';
// Deterministic local composition. No model, fetch, credentials or worker.
globalThis.LocalProductCompose=(()=>{
 const canvas=(w,h)=>{if(w*h>16000000||w<1||h<1)throw Error('图片尺寸过大');const c=document.createElement('canvas');c.width=w;c.height=h;return c;};
 const png=c=>new Promise((r,j)=>c.toBlob(b=>b?r(b):j(Error('PNG导出失败')),'image/png'));
 async function prepare(blob){
  const b=await createImageBitmap(blob),c=canvas(b.width,b.height),ctx=c.getContext('2d',{willReadFrequently:true});ctx.drawImage(b,0,0);b.close();
  const original=ctx.getImageData(0,0,c.width,c.height),d=original.data,n=c.width*c.height,alpha=new Uint8ClampedArray(n);let transparent=false;
  for(let i=0;i<n;i++){alpha[i]=255;if(d[4*i+3]<255)transparent=true;}
  let removed=0;
  if(!transparent){const seen=new Uint8Array(n),q=new Int32Array(n);let head=0,tail=0;
   const add=i=>{if(!seen[i]&&d[4*i]>=250&&d[4*i+1]>=250&&d[4*i+2]>=250){seen[i]=1;q[tail++]=i;alpha[i]=0;}};
   for(let x=0;x<c.width;x++){add(x);add((c.height-1)*c.width+x);}for(let y=0;y<c.height;y++){add(y*c.width);add(y*c.width+c.width-1);}
   while(head<tail){const i=q[head++],x=i%c.width;if(x)add(i-1);if(x<c.width-1)add(i+1);if(i>=c.width)add(i-c.width);if(i<n-c.width)add(i+c.width);}removed=tail;
   if(removed===n)throw Error('整图为白色，无法区分产品；请使用透明PNG');
  }
  // Closed white regions have no connection to proven exterior background.
  // Silver highlights can have the same RGB: report, do not erase by color alone.
  let unresolvedWhitePixels=0;
  if(!transparent)for(let i=0;i<n;i++)if(alpha[i]&&d[4*i]>=250&&d[4*i+1]>=250&&d[4*i+2]>=250)unresolvedWhitePixels++;
  const initial=alpha.slice(),mask=canvas(c.width,c.height),mc=mask.getContext('2d');
  const sync=()=>{const m=mc.createImageData(c.width,c.height);for(let i=0;i<n;i++){m.data[4*i]=m.data[4*i+1]=m.data[4*i+2]=255;m.data[4*i+3]=alpha[i];}mc.putImageData(m,0,0);};sync();
  return {source:blob,sourceHash:await ProductCanvasFoundation.sha(blob),original,c,mask,alpha,origin:transparent?'original-alpha':'border-connected-white-candidate',removed,unresolvedWhitePixels,
   reset(){alpha.set(initial);sync();},brush(x,y,r,restore){for(let v=Math.max(0,Math.floor(y-r));v<Math.min(c.height,y+r);v++)for(let u=Math.max(0,Math.floor(x-r));u<Math.min(c.width,x+r);u++)if((u-x)**2+(v-y)**2<=r*r)alpha[v*c.width+u]=restore?255:0;sync();},
   preview(){const p=canvas(c.width,c.height),pc=p.getContext('2d');pc.putImageData(original,0,0);pc.globalCompositeOperation='destination-in';pc.drawImage(mask,0,0);return p;}};
 }
 async function compose(asset,{width,height,x,y,scale,background,backgroundConfirmedClean,text='',color='#171d27',maskConfirmed=false}){
  if(!maskConfirmed)throw Error('请核对产品边缘后确认遮罩');
  if(!backgroundConfirmedClean)throw Error('请提供不含旧产品的干净背景');
  if(/headlights?/i.test(text))throw Error('文案含禁用词');
  const bg=canvas(width,height),ctx=bg.getContext('2d');
  if(background){const b=await createImageBitmap(background);const s=Math.max(width/b.width,height/b.height);ctx.drawImage(b,(width-b.width*s)/2,(height-b.height*s)/2,b.width*s,b.height*s);b.close();}
  else{ctx.fillStyle=color;ctx.fillRect(0,0,width,height);}
  if(text){const lines=text.split('\n').filter(Boolean);if(lines.length>4)throw Error('顶部文案最多4行');const band=height*.2,lh=band/(lines.length+1);if(y<band)throw Error('请将产品放在顶部文案区下方');ctx.fillStyle='white';ctx.textAlign='center';ctx.textBaseline='middle';for(let i=0;i<lines.length;i++){let size=Math.min(width*.055,lh*.75);ctx.font=`600 ${size}px sans-serif`;if(ctx.measureText(lines[i]).width>width*.9){size*=width*.9/ctx.measureText(lines[i]).width;ctx.font=`600 ${size}px sans-serif`;}ctx.fillText(lines[i],width/2,(i+1)*lh);}}
  const mask=await png(asset.mask),session=new ProductCanvasFoundation.Session({enabled:true,policy:{modes:{},forbiddenSource:'headlights?'}});
  await session.load(asset.source,{sourceHash:asset.sourceHash,mask,maskHash:await ProductCanvasFoundation.sha(mask)});session.transform({x,y,scale,rotation:0});await session.layers({background:bg,backgroundConfirmedClean:true});
  const result=await session.exportPNG({width,height});Object.assign(result.manifest,{workflow:'local-original-product',maskOrigin:asset.origin,maskConfirmed:true,backgroundOrigin:background?'user-clean-background':'local-solid-background',backgroundHash:background?await ProductCanvasFoundation.sha(background):null,text,modelCalls:0,sourcePixelsReused:true});return result;
 }
 return {prepare,compose,png,canvas};
})();
