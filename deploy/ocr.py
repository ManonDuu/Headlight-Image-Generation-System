#!/usr/local/bin/python3
"""Local Linux OCR; low-confidence results remain subject to original copy gate."""
import csv,io,json,subprocess,sys
from PIL import Image
with Image.open(sys.argv[1]) as im:w,h=im.size
p=subprocess.run(['tesseract',sys.argv[1],'stdout','-l','eng','--psm','3','tsv'],capture_output=True,text=True,timeout=7,check=True)
groups={}
for row in csv.DictReader(io.StringIO(p.stdout),delimiter='\t'):
    if row['level']!='5' or not row['text'].strip():continue
    groups.setdefault(tuple(row[k] for k in ('page_num','block_num','par_num','line_num')),[]).append(row)
lines=[]
for rows in groups.values():
    x=min(int(r['left']) for r in rows);y=min(int(r['top']) for r in rows);right=max(int(r['left'])+int(r['width']) for r in rows);bottom=max(int(r['top'])+int(r['height']) for r in rows)
    lines.append({'text':' '.join(r['text'] for r in rows),'confidence':min(float(r['conf']) for r in rows)/100,'words':[],'quad':[[x/w,y/h],[right/w,y/h],[right/w,bottom/h],[x/w,bottom/h]]})
print(json.dumps({'version':'linux-tesseract-1','engine':'Tesseract','network':False,'lines':lines}))
