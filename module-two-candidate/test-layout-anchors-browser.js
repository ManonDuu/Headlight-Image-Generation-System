(()=>{
 let checks=0;const ok=(v,m)=>{if(!v)throw Error(m);checks++;};
 for(const [width,height,first,second,color] of [[800,1000,.42,.88,'#128a52'],[1200,800,.38,.83,'#ac2870']]){
  const c=document.createElement('canvas');c.width=width;c.height=height;const x=c.getContext('2d');x.fillStyle='#080808';x.fillRect(0,0,width,height);x.fillStyle=color;x.fillRect(0,Math.round(height*first),width,Math.round(height*.065));x.fillStyle='#666666';x.fillRect(0,Math.round(height*second),width,Math.round(height*.07));
  const bands=ReferenceLayoutAnchors.bands(c);ok(bands.length===2,'detect both containers at other aspect/positions/colors');ok(bands[0].y<height*.6&&bands[1].y>height*.8,'vertical order retained without sample coordinates');
  x.fillStyle='#080808';x.fillRect(0,0,width,height);ok(ReferenceLayoutAnchors.bands(c).length===0,'no invented containers on empty background');
 }
 return {checks,syntheticScenes:2,modelCalls:0};
})()
