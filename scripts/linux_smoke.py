import base64,json,os,subprocess,tempfile
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)/'a.png';im=Image.new('RGB',(800,400),'white');ImageDraw.Draw(im).text((30,100),'BRIGHT LIGHT',fill='black',font_size=60);im.save(p)
 out=subprocess.check_output([str(ROOT/'deploy/image_probe.py'),'-g','format',str(p)],text=True)
 assert 'pixelWidth: 800' in out and 'format: png' in out
 o=json.loads(subprocess.check_output(['python3',str(ROOT/'deploy/ocr.py'),str(p)]));assert o['lines'],'OCR returned no text'
 jpeg=Path(tmp)/'a.jpg';im.save(jpeg,format='JPEG')
 assert 'format: jpeg' in subprocess.check_output([str(ROOT/'deploy/image_probe.py'),str(jpeg)],text=True)
 broken=Path(tmp)/'broken.png';broken.write_bytes(b'not an image');assert subprocess.run([str(ROOT/'deploy/image_probe.py'),str(broken)]).returncode!=0
 q=Path(tmp)/'b.png';Image.new('RGB',(800,400),'red').save(q)
 # Compile both live prompt pathways without credentials/network and check exact versions.
 code="""require 'json';require 'base64';require 'digest';require_relative './module-two-candidate/bridge-server'
a=File.binread(ARGV[0]);b=File.binread(ARGV[1]);base={'mode'=>'ai-rewrite','layoutMode'=>'auto-layout','layoutTone'=>'adjust-color','color'=>'#ff6600','output'=>{'aspectRatio'=>'1:1','imageSize'=>'2K'}}
[['reference-reconstruction',DirectImagePlan::SPEC,nil],['product-replacement',DirectImagePlan::PRODUCT_SPEC,b]].each do |mod,spec,product|
 plan=DirectImagePlan.prepare(a,product,base.merge('module'=>mod,'businessSpec'=>spec),mock:false,input_origin:'user')
 DirectImagePlan.validate(plan);raise unless plan['binding']['version']==spec
end
puts 'Reference and replacement plans verified'
"""
 subprocess.run(['ruby','-e',code,str(p),str(q)],cwd=ROOT,check=True)
 subprocess.run(['ruby','-e',code,str(jpeg),str(q)],cwd=ROOT,check=True)
print('Linux decode, OCR and frozen prompt compilation passed; no paid calls.')
