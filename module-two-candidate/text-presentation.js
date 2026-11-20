'use strict';
globalThis.TextPresentation=(()=>{
 const need=(v,m)=>{if(!v)throw Error(m)};
 function palette(t,selected){
  const result=structuredClone(t),neutral=c=>{if(!/^#[0-9a-f]{6}$/i.test(c))return true;const a=[1,3,5].map(i=>parseInt(c.slice(i,i+2),16));return Math.max(...a)-Math.min(...a)<30;};
  // Neutral body/contrast colors stay neutral. Explicit roles override inferred color families.
  const role=t.presentation?.paletteRole|| (neutral(t.color)?'neutral':'accent');if(['accent','primary-accent','emphasis'].includes(role))result.color=selected;
  if(result.presentation?.fill?.stops)result.presentation.fill.stops=result.presentation.fill.stops.map(s=>({...s,color:neutral(s.color)?s.color:selected}));return result;
 }
 function validate(p,b){
  need(p&&['manual-pixel-reviewed','deterministic-derived'].includes(p.reviewState),'Source text treatment needs review');
  need(Array.isArray(p.quad)&&p.quad.length===4,'Missing text quadrilateral');const q=p.quad;
  need(q.every(v=>Array.isArray(v)&&v.length===2&&v.every(Number.isFinite)&&v[0]>=b.x&&v[1]>=b.y&&v[0]<=b.x+b.width&&v[1]<=b.y+b.height),'Projected glyph outside reviewed slot');
  const crosses=q.map((a,i)=>{const c=q[(i+1)%4],d=q[(i+2)%4];return(c[0]-a[0])*(d[1]-c[1])-(c[1]-a[1])*(d[0]-c[0])});need(crosses.every(v=>v>0),'Folded/degenerate text projection');return q;
 }
 function project(q,u,v){
  const [a,b,c,d]=q,dx1=b[0]-c[0],dx2=d[0]-c[0],dx3=a[0]-b[0]+c[0]-d[0],dy1=b[1]-c[1],dy2=d[1]-c[1],dy3=a[1]-b[1]+c[1]-d[1],det=dx1*dy2-dx2*dy1;
  const g=Math.abs(det)<1e-10?0:(dx3*dy2-dx2*dy3)/det,h=Math.abs(det)<1e-10?0:(dx1*dy3-dx3*dy1)/det,z=g*u+h*v+1;
  return[(a[0]+(b[0]-a[0]+g*b[0])*u+(d[0]-a[0]+h*d[0])*v)/z,(a[1]+(b[1]-a[1]+g*b[1])*u+(d[1]-a[1]+h*d[1])*v)/z];
 }
 function draw(ctx,plan,plain){
  const p=plan.presentation,b=plan.box;
  if(p.kind==='parallel-columns'){
   need(p.parts?.length===3&&p.parts.join(' · ')===plan.text,'Parallel copy changed');ctx.save();ctx.font=plan.font;ctx.fillStyle=plan.color;ctx.textBaseline='alphabetic';const cell=b.width/3;
   p.parts.forEach((text,i)=>{const m=ctx.measureText(text);need(m.width<=cell*.92,'Parallel item exceeds its column');ctx.fillText(text,b.x+i*cell+(cell-m.width)/2,b.y+m.actualBoundingBoxAscent);});ctx.restore();return;
  }
  const q=validate(p,b),c=document.createElement('canvas');const padding=p.fitTextureToGlyphs?(p.stroke?.width||0):0;c.width=Math.ceil(b.width+2*padding);c.height=Math.ceil(p.fitTextureToGlyphs?plan.height+2*padding:b.height);const s=c.getContext('2d'),local={...plan,presentation:null,positions:plan.positions.map(v=>({x:v.x-b.x+padding,y:v.y-b.y+padding}))};
  s.font=plan.font;s.textBaseline='alphabetic';s.fillStyle=plan.color;
  if(p.fill?.stops){const grad=s.createLinearGradient(0,0,p.fill.direction==='horizontal'?c.width:0,p.fill.direction==='horizontal'?0:c.height);for(const stop of p.fill.stops)grad.addColorStop(stop.at,stop.color);s.fillStyle=grad;}
  if(p.stroke){s.strokeStyle=p.stroke.color;s.lineWidth=p.stroke.width;s.lineJoin='round';}
  local.lines.forEach((line,i)=>{if(p.stroke)s.strokeText(line,local.positions[i].x,local.positions[i].y);s.fillText(line,local.positions[i].x,local.positions[i].y)});
  // Project rasterized glyphs with a deterministic triangle mesh, never reshape product pixels.
  function tri(src,dst){const [a,b,c0]=src,[d,e,f]=dst,x1=b[0]-a[0],y1=b[1]-a[1],x2=c0[0]-a[0],y2=c0[1]-a[1],den=x1*y2-x2*y1,A=((e[0]-d[0])*y2-(f[0]-d[0])*y1)/den,B=((e[1]-d[1])*y2-(f[1]-d[1])*y1)/den,C=(x1*(f[0]-d[0])-x2*(e[0]-d[0]))/den,D=(x1*(f[1]-d[1])-x2*(e[1]-d[1]))/den;ctx.save();ctx.beginPath();ctx.moveTo(...d);ctx.lineTo(...e);ctx.lineTo(...f);ctx.closePath();ctx.clip();ctx.transform(A,B,C,D,d[0]-A*a[0]-C*a[1],d[1]-B*a[0]-D*a[1]);ctx.drawImage(c,0,0);ctx.restore();}
  const n=16;for(let y=0;y<n;y++)for(let x=0;x<n;x++){const uv=[[x/n,y/n],[(x+1)/n,y/n],[(x+1)/n,(y+1)/n],[x/n,(y+1)/n]],src=uv.map(v=>[v[0]*c.width,v[1]*c.height]),dst=uv.map(v=>project(q,...v));for(const ids of [[0,1,2],[0,2,3]])tri(ids.map(i=>src[i]),ids.map(i=>dst[i]));}
 }
 return {palette,validate,project,draw};
})();
