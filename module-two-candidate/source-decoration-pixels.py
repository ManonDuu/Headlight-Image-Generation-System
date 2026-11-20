"""Source-only chromatic components; no file-name rules or model dispatch."""
import colorsys, collections, importlib.util, json, math, sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('native',Path(__file__).with_name('native-image-rgba.py'));native=importlib.util.module_from_spec(spec);spec.loader.exec_module(native)
def components(image,structure,color):
 w,h,rgba=native.read(image);rgb=tuple(int(color[i:i+2],16)/255 for i in (1,3,5));hue,sat,val=colorsys.rgb_to_hsv(*rgb)
 if sat<.4:raise ValueError('neutral decorations need independent geometry evidence')
 mask=bytearray(w*h);exclusions=[g['bounds'] for g in structure['textGroups']]
 for p in structure['panels']:
  if p.get('labelBounds'):exclusions.append(p['labelBounds'])
  pts=p.get('labelPointer',[])
  if pts:exclusions.append(dict(x=min(q[0] for q in pts),y=min(q[1] for q in pts),width=max(q[0] for q in pts)-min(q[0] for q in pts),height=max(q[1] for q in pts)-min(q[1] for q in pts)))
 excluded=bytearray(w*h)
 for b in exclusions:
  for y in range(max(0,int(b['y'])-2),min(h,math.ceil(b['y']+b['height'])+2)):
   x0=max(0,int(b['x'])-2);x1=min(w,math.ceil(b['x']+b['width'])+2);excluded[y*w+x0:y*w+x1]=b'\1'*(x1-x0)
 for i in range(w*h):
  if excluded[i]:continue
  r,g,b=rgba[4*i:4*i+3];mx=max(r,g,b);mn=min(r,g,b)
  if mx<35 or mx-mn<25:continue
  hh,ss,vv=colorsys.rgb_to_hsv(r/255,g/255,b/255);delta=abs(hh-hue)
  if min(delta,1-delta)<.11 and ss>.35:mask[i]=1
 out=[]
 for i in range(w*h):
  if not mask[i]:continue
  mask[i]=0;queue=[i];points=[]
  for q in queue:
   x,y=q%w,q//w;points.append((x,y))
   for nx,ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
    if 0<=nx<w and 0<=ny<h and mask[ny*w+nx]:mask[ny*w+nx]=0;queue.append(ny*w+nx)
  if len(points)<max(12,w*h*.00003):continue
  rows=collections.defaultdict(list)
  for x,y in points:rows[y].append(x)
  x0=min(x for x,y in points);x1=max(x for x,y in points);y0=min(rows);y1=max(rows);out.append({'bounds':dict(x=x0,y=y0,width=x1-x0+1,height=y1-y0+1),'pixels':len(points),'rows':[[y,min(xs),max(xs)] for y,xs in sorted(rows.items())]})
 return w,h,out
def is_up_arrow(c):
 b=c['bounds'];rows=c['rows'];width=b['width'];height=b['height']
 if not (.9<height/width<4) or len(rows)<height*.9:return False
 spans=[r[2]-r[1]+1 for r in rows];peak=max(spans);peak_index=spans.index(peak)
 # An envelope alone can turn a hollow outline or fragmented scene object
 # into a filled arrow. Require actual pixels to support the filled polygon.
 if c['pixels']/sum(spans)<.9:return False
 if not .25*height<peak_index<.75*height:return False
 head=spans[:peak_index+1];tail=spans[int(height*.72):]
 return bool(tail) and head[0]<peak*.2 and sum(tail)/len(tail)<peak*.65 and sum(tail)/len(tail)>peak*.15 and all(abs((r[1]+r[2])/2-(b['x']+width/2))<width*.22 for r in rows)
def simplify(points,tolerance=.7):
 if len(points)<3:return points
 a,b=points[0],points[-1];dx,dy=b[0]-a[0],b[1]-a[1];den=math.hypot(dx,dy)
 ds=[abs(dy*(p[0]-a[0])-dx*(p[1]-a[1]))/den if den else math.hypot(p[0]-a[0],p[1]-a[1]) for p in points]
 i=max(range(len(ds)),key=ds.__getitem__)
 if ds[i]<=tolerance:return [a,b]
 return simplify(points[:i+1],tolerance)[:-1]+simplify(points[i:],tolerance)
def refine(image,structure):
 decorations=structure.get('decorations',[]);result=[];audit=[]
 w,h,rgba=native.read(image)
 eligible=[d for d in decorations if d['type']=='polygon' and d['fill'] and max(bytes.fromhex(d['color'][1:]))-min(bytes.fromhex(d['color'][1:]))>80]
 for d in decorations:
  if d not in eligible:result.append(d);continue
  _,_,found=components(image,structure,d['color']);arrows=[c for c in found if is_up_arrow(c)]
  if len(eligible)!=1 or len(arrows)!=1:raise ValueError('SOURCE_DECORATION_UNRESOLVED: chromatic polygon requires one uniquely measured arrow; never infer absence from predicted box')
  c=arrows[0];rows=c['rows'];left=simplify([[x,y] for y,x,_ in rows]);right=simplify([[x+1,y] for y,_,x in rows][::-1]);points=left+right;b=c['bounds'];stops=[]
  for at in (0,1/3,2/3,1):
   y,l,r=rows[min(len(rows)-1,round(at*(len(rows)-1)))];xs=range(l+max(0,(r-l)//4),r-max(0,(r-l)//4)+1);colors=[rgba[(y*w+x)*4:(y*w+x)*4+3] for x in xs];rgb=[sorted(z[k] for z in colors)[len(colors)//2] for k in range(3)];stops.append({'at':at,'color':'#'+''.join(f'{n:02X}' for n in rgb)})
  repaired=dict(d,bounds=b,points=points,fillStops=stops,fillDirection='vertical',color=stops[0]['color'])
  # Polygon follows actual chromatic boundary (including stem), not an invented triangle.
  result.append(repaired);audit.append({'state':'source-pixel-component-corrected','originalBounds':d['bounds'],'bounds':b,'pixelCount':c['pixels'],'candidateArrows':len(arrows),'otherChromaticComponents':len(found)-1,'method':'unique-up-arrow-profile-after-excluding-source-text-and-labels','deleted':False,'labelPointersExcluded':True,'shapePoints':len(points),'tailLimit':'measured chromatic pixels; no extrapolation into invisible tail'})
 return result,audit
if __name__=='__main__':
 s=json.loads(Path(sys.argv[2]).read_text());w,h,c=components(sys.argv[1],s,sys.argv[3]);Path(sys.argv[4]).write_text(json.dumps(c));print(json.dumps([{k:v for k,v in a.items() if k!='rows'} for a in c]))
