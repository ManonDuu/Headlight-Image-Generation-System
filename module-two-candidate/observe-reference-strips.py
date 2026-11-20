"""Bounded local detector for edge-to-edge comparison label strips.
Consumes actual raster + native OCR + existing same-source semantic blocks.
No output-coordinate presets, filename/hash lookup, model calls or inferred new copy.
"""
import importlib.util,json,sys,hashlib,re
from pathlib import Path
spec=importlib.util.spec_from_file_location('native',Path(__file__).with_name('native-image-rgba.py'));native=importlib.util.module_from_spec(spec);spec.loader.exec_module(native)
dspec=importlib.util.spec_from_file_location('decoration_pixels',Path(__file__).with_name('source-decoration-pixels.py'));decoration_pixels=importlib.util.module_from_spec(dspec);dspec.loader.exec_module(decoration_pixels)
def detect(w,h,data):
 def rgb(x,y):return data[(y*w+x)*4:(y*w+x)*4+3]
 def dist(a,b):return max(abs(x-y) for x,y in zip(a,b))
 xs=list(range(0,w,max(1,w//100)));rows=[]
 for y in range(h):
  a=rgb(max(1,w//100),y);b=rgb(w-1-max(1,w//100),y)
  good=sum(dist(rgb(x,y),[a[j]+(b[j]-a[j])*x/(w-1) for j in range(3)])<25 for x in xs if x<w*.2 or x>w*.8)/sum(x<w*.2 or x>w*.8 for x in xs)
  rows.append(good>.72 and max(a)>45 and max(b)>45 and dist(a,rgb(max(1,w//100),max(0,y-1)))<16)
 bands=[];start=None
 for y,on in enumerate(rows+[False]):
  if on and start is None:start=y
  if not on and start is not None:
   if h*.025<=y-start<=h*.15:bands.append((start,y))
   start=None
 if not bands:raise ValueError('no corroborated full-width label strips')
 # Include antialiased transition rows supported by both edge colors.
 refined=[]
 for top,bottom in bands:
  center=(top+bottom)//2
  while top>0 and all(dist(rgb(x,top-1),rgb(x,center))<28 for x in [1,w-2]):top-=1
  refined.append((top,bottom))
 bands=refined;out=[]
 for i,(top,bottom) in enumerate(bands):
  center=(top+bottom)//2;stops=[]
  for at in [0,.25,.5,.75,1]:
   x=min(w-1,max(0,round(at*(w-1))));colors=[rgb(x,y) for y in range(top,min(bottom,top+max(2,(bottom-top)//6)))];col=[sorted(v[j] for v in colors)[len(colors)//2] for j in range(3)];stops.append({'at':at,'color':'#'+''.join(f'{v:02X}' for v in col)})
  # A pointer is measured only where strip-colored pixels form a narrow run above it.
  heights=[]
  for x in range(0,w,max(1,w//400)):
   base=rgb(x,center);y=top-1
   while y>=max(0,top-int(h*.1)) and dist(rgb(x,y),base)<22:y-=1
   heights.append((x,top-1-y))
  active=[(x,n) for x,n in heights if n>2];clusters=[];pointer=[]
  for q in active:
   if not clusters or q[0]-clusters[-1][-1][0]>max(1,w//400)*1.5:clusters.append([])
   clusters[-1].append(q)
  candidates=[g for g in clusters if w*.015<g[-1][0]-g[0][0]<w*.2 and h*.012<max(n for x,n in g)<h*.1]
  if candidates:
   g=max(candidates,key=lambda v:sum(n for x,n in v));lo=g[0][0];hi=g[-1][0];peak=max(g,key=lambda q:q[1]);pointer=[[lo,top],[peak[0],top-peak[1]],[hi,top]]
  y0=0 if i==0 else bands[i-1][1]
  out.append({'id':str(i),'bounds':{'x':0,'y':y0,'width':w,'height':bottom-y0},'sceneBounds':{'x':0,'y':y0,'width':w,'height':top-y0},'labelBounds':{'x':0,'y':top,'width':w,'height':bottom-top},'sceneRole':'region-'+str(i+1),'borderColor':'#000000','borderWidth':0,'labelColor':stops[0]['color'],'labelFillStops':stops,'radius':0,'labelRadius':0,'labelPointer':pointer})
 return out

def observe(image,ocr,layout,observed_panels=None):
 w,h,data=native.read(image);
 if (layout['sourceGeometry']['width'],layout['sourceGeometry']['height'])!=(w,h):raise ValueError('semantic source dimensions differ from actual image')
 panels=detect(w,h,data) if observed_panels is None else observed_panels;unresolved=[];norm=lambda s:re.sub('[^A-Z0-9%]','',s.upper());groups=[]
 for block in layout['evidence']['sourceBlocks']:
  wanted=norm(block['sourceText']);lines=[]
  for v in ocr['lines']:
   if v['confidence']<.8:continue
   n=norm(v['text'])
   if n==wanted or (n and n in wanted):lines.append(v);continue
   if wanted and wanted in n:
    # A partial line needs actual Vision word boxes; never give two source
    # blocks the entire row, and never estimate glyph widths from character counts.
    words=v.get('words',[]);spans=[]
    for start in range(len(words)):
     for end in range(start+1,len(words)+1):
      if norm(' '.join(x['text'] for x in words[start:end]))==wanted:spans.append(words[start:end])
    if len(spans)!=1:raise ValueError('partial OCR text lacks unique word geometry: '+block['id'])
    pts=[p for word in spans[0] for p in word['quad']];xs=[p[0] for p in pts];ys=[p[1] for p in pts]
    lines.append(dict(text=block['sourceText'],confidence=v['confidence'],quad=[[min(xs),min(ys)],[max(xs),min(ys)],[max(xs),max(ys)],[min(xs),max(ys)]]))
  if len({norm(v['text']) for v in lines}) != len(lines):raise ValueError('duplicate OCR text is ambiguous: '+block['id'])
  if not lines or sum(len(norm(v['text'])) for v in lines)<len(wanted)*.8:
   if observed_panels==[]:
    prior=next((v for v in layout.get('sourceStructure',{}).get('textGroups',[]) if v['blockIds']==[block['id']]),None)
    if prior:
     prior=json.loads(json.dumps(prior));prior['localMeasurementState']='unresolved-ocr';groups.append(prior);unresolved.append(block['id']);continue
   if block['id'] not in layout.get('_locallyOmittedBlockIds',[]):raise ValueError('OCR cannot corroborate block '+block['id'])
   b=block['sourceBox'];lines=[{'text':block['sourceText'],'quad':[[b['x']/w,b['y']/h],[(b['x']+b['width'])/w,b['y']/h],[(b['x']+b['width'])/w,(b['y']+b['height'])/h],[b['x']/w,(b['y']+b['height'])/h]]}]
  points=[(x*w,y*h) for l in lines for x,y in l['quad']];x=min(a for a,b in points);y=min(b for a,b in points);right=max(a for a,b in points);bottom=max(b for a,b in points);bounds=dict(x=x,y=y,width=right-x,height=bottom-y)
  owner='canvas';placement='header' if block['marketingFunction'] in ['title','subtitle'] else 'free'
  for p in panels:
   l=p['labelBounds']
   if y>=l['y']-h*.005 and bottom<=l['y']+l['height']+h*.005:owner=p['id'];placement='label';break
   if placement!='header' and y>=p['sceneBounds']['y'] and bottom<=p['sceneBounds']['y']+p['sceneBounds']['height']:owner=p['id'];placement='detail'
  line_styles=[]
  for line in lines:
   pts=[(a*w,b*h) for a,b in line['quad']];lx,ly=min(a for a,b in pts),min(b for a,b in pts);rx,by=max(a for a,b in pts),max(b for a,b in pts);inks=[]
   for yy in range(int(ly),min(h,int(by))):
    for xx in range(int(lx),min(w,int(rx))):
     c=data[(yy*w+xx)*4:(yy*w+xx)*4+3]
     if max(c)-min(c)<30 and min(c)>145:inks.append(sum(c)//3)
   density=len(inks)/max(1,(rx-lx)*(by-ly))
   if inks:
    level=sorted(inks)[int(len(inks)*.65)];line_styles.append({'text':line['text'],'color':'#'+f'{level:02X}'*3,'weight':200 if density<.2 else 700,'density':density})
  groups.append({'blockIds':[block['id']],'bounds':bounds,'quad':[[x,y],[right,y],[right,bottom],[x,bottom]],'italic':False,'weight':400 if placement=='header' and block['marketingFunction']=='subtitle' else 700,'paletteRole':'neutral','color':'#FFFFFF','owner':owner,'placement':placement,'lineStyles':line_styles})
 for g in groups:
  prior=next((v for v in layout.get('sourceStructure',{}).get('textGroups',[]) if v['blockIds']==g['blockIds']),None)
  if observed_panels is not None and prior and prior.get('fillStops'):
   g['fillStops']=prior['fillStops'];g['fillDirection']='horizontal';g['weight']=prior['weight'];g['paletteRole']=prior['paletteRole'];g['color']=prior['color']
 # Observe label glyph neutral intensity, excluding the colored/gray background.
 for g in groups:
  if g.get('localMeasurementState')=='unresolved-ocr':continue
  b=g['bounds'];samples=[]
  for y in range(int(b['y']),min(h,int(b['y']+b['height'])),2):
   for x in range(int(b['x']),min(w,int(b['x']+b['width'])),2):
    v=data[(y*w+x)*4:(y*w+x)*4+3]
    if max(v)-min(v)<35 and min(v)>140:samples.append(sum(v)//3)
  if samples and g['placement']=='header' and any(b0['id'] in g['blockIds'] and b0['marketingFunction']=='subtitle' for b0 in layout['evidence']['sourceBlocks']):
   density=len(samples)/max(1,b['width']*b['height']/4);g['weight']=200 if density<.2 else 400;g['weightEvidence']={'method':'neutral-glyph-coverage','density':density}
  if samples:
   level=sorted(samples)[int(len(samples)*.65)];g['color']='#'+f'{level:02X}'*3;g['colorEvidence']={'method':'neutral-source-glyph-pixels','sampleCount':len(samples)}
  # Mixed-color heading: detect a leading chromatic glyph run followed by white glyphs.
  if g['placement']=='header':
   chrom=[];white=[]
   for x in range(int(b['x']),min(w,int(b['x']+b['width'])),3):
    cs=[];ws=0
    for y in range(int(b['y']),min(h,int(b['y']+b['height'])),2):
     v=data[(y*w+x)*4:(y*w+x)*4+3]
     if max(v)>170 and max(v)-min(v)>100:cs.append(v)
     elif min(v)>190:ws+=1
    if len(cs)>3 and len(cs)>ws:chrom.append((x,cs[len(cs)//2]))
    if ws>3:white.append(x)
   if chrom and white and chrom[0][0]<b['x']+b['width']*.1 and chrom[-1][0]<b['x']+b['width']*.6 and min(white)>chrom[-1][0]:
    edge=(chrom[-1][0]-b['x'])/b['width'];hexcolor=lambda v:'#'+''.join(f'{n:02X}' for n in v)
    g['fillStops']=[{'at':0,'color':hexcolor(chrom[len(chrom)//5][1])},{'at':edge,'color':hexcolor(chrom[-max(1,len(chrom)//5)][1])},{'at':min(1,edge+.008),'color':g['color']},{'at':1,'color':g['color']}];g['fillDirection']='horizontal';g['colorEvidence']={'method':'chromatic-leading-glyphs-and-neutral-trailing-glyphs','sampleCount':len(chrom)+len(white)}
   elif chrom and chrom[-1][0]-chrom[0][0]>b['width']*.7 and len(white)<len(chrom)*.15:
    stops=[]
    for at in [0,1/3,2/3,1]:
     center=b['x']+b['width']*at;near=sorted(chrom,key=lambda v:abs(v[0]-center))[:max(3,len(chrom)//12)]
     rgb=[sorted(v[1][j] for v in near)[len(near)//2] for j in range(3)]
     stops.append({'at':at,'color':'#'+''.join(f'{n:02X}' for n in rgb)})
    g.update(fillStops=stops,fillDirection='horizontal',color=stops[0]['color'],paletteRole='accent',colorEvidence={'method':'chromatic-source-glyph-columns','sampleCount':len(chrom)})
 if not all(any(g['owner']==p['id'] and g['placement']=='label' for g in groups) for p in panels):raise ValueError('strip has no corroborating label text')
 return {'version':'source-structure-1','coordinateSpace':'source-pixels','productPresent':False,'productVisibleBounds':dict(x=0,y=0,width=0,height=0),'textGroups':groups,'panels':panels,'observationEvidence':{'method':'native-ocr-plus-full-width-pixel-strips','sourceHash':hashlib.sha256(Path(image).read_bytes()).hexdigest(),'semanticOrigin':'existing-same-source-raw-analysis','newModelCalls':0,'manualCoordinates':False,'unresolvedTextBlocks':unresolved,'reviewedPanelInventoryUsed':observed_panels is not None,'omittedBlocksMayUseHistoricalBounds':layout.get('_locallyOmittedBlockIds',[]),'scope':'native OCR with source-bound reviewed panel inventory' if observed_panels is not None else 'edge-to-edge labeled strips only; ambiguous OCR stops'}}
if __name__=='__main__':
 text_only=len(sys.argv)>5 and sys.argv[5]=='--text-only'
 inventory=[] if text_only else json.loads(Path(sys.argv[5]).read_text())['panels'] if len(sys.argv)>5 else None
 layout=json.loads(Path(sys.argv[3]).read_text());result=observe(sys.argv[1],json.loads(Path(sys.argv[2]).read_text()),layout,inventory)
 result['decorations'],decoration_audit=decoration_pixels.refine(sys.argv[1],dict(result,decorations=layout.get('sourceStructure',{}).get('decorations',[])))
 if decoration_audit:result['decorationEvidence']=decoration_audit
 if text_only:result['observationEvidence'].update(method='native-ocr-plus-source-glyph-pixels',reviewedPanelInventoryUsed=False,scope='text geometry/style only; scene regions unchanged')
 Path(sys.argv[4]).write_text(json.dumps(result,indent=2));print(json.dumps(result['panels']))
