"""Conservative unexplained-raster detector, not a photography classifier.
Never creates regions or coordinates. Textured gaps require local review.
"""
import importlib.util,json,sys,math
from pathlib import Path
spec=importlib.util.spec_from_file_location('native',Path(__file__).with_name('native-image-rgba.py'))
native=importlib.util.module_from_spec(spec);spec.loader.exec_module(native)
def inspect(w,h,data,structure):
 panels=structure.get('panels',[])
 if not panels:return {'state':'single-continuous-scene','unexplainedTiles':[]}
 boxes=[p['bounds'] for p in panels]
 boxes += [g['bounds'] for g in structure.get('textGroups',[])]
 boxes += [d['bounds'] for d in structure.get('decorations',[])]
 if structure.get('productPresent'):boxes.append(structure['productVisibleBounds'])
 def covered(x,y):return any(b['x']<=x<=b['x']+b['width'] and b['y']<=y<=b['y']+b['height'] for b in boxes)
 # Relative grid, independent of file names, brands, image size and panel count.
 tw=max(8,math.ceil(w/32));th=max(8,math.ceil(h/40));pending=[]
 for y in range(0,h-th+1,th):
  for x in range(0,w-tw+1,tw):
   if any(covered(x+tw*a,y+th*b) for a,b in [(0,0),(1,0),(0,1),(1,1),(.5,.5)]):continue
   vals=[];diff=[]
   for yy in range(y,y+th,3):
    for xx in range(x,x+tw-2,3):
     i=(yy*w+xx)*4;j=(yy*w+xx+2)*4
     rgb=data[i:i+3];vals.append(sum(rgb)/3);diff.append(max(abs(data[i+k]-data[j+k]) for k in range(3)))
   mean=sum(vals)/len(vals);sd=(sum((a-mean)**2 for a in vals)/len(vals))**.5
   if sd>10 and sum(d>8 for d in diff)/len(diff)>.15:pending.append({'x':x,'y':y,'width':tw,'height':th})
 return {'state':'unexplained-raster-review-required' if len(pending)>=4 else 'no-large-textured-gap-detected','unexplainedTiles':pending,'semanticCompletenessVerified':False}
if __name__=='__main__':
 w,h,data=native.read(sys.argv[1]);v=json.loads(Path(sys.argv[2]).read_text())
 if [w,h]!=[v['sourceGeometry']['width'],v['sourceGeometry']['height']]:raise ValueError('SOURCE_RASTER_DIMENSIONS_MISMATCH')
 print(json.dumps(inspect(w,h,data,v['sourceStructure'])))
