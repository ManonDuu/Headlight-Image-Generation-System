"""Module 3 domain and persistence. No provider imports or network access."""
import base64
import hashlib
import json
import re
import secrets
import threading
from datetime import datetime, timezone
from pathlib import Path
from design_rules import recipe, shared_contract, REVIEW, presentation, locked_copy
from display_library import creative_brief, REVISION as DISPLAY_REVISION
from content_controls import content_controls
from reference_rules import case_brief
from variation_rules import choose, render_prompt, REVISION
from style_contract import theme, TYPOGRAPHY, resolved_rating, resolved_light_color, resolved_lifespan
from copy import deepcopy

POINTS = {
 'illumination': ('亮度与照射表现', ['道路纵深场景，照明区域为主要画面', '同一视角分区对比，非目标场景条件保持一致']),
 'beam': ('光型表现', ['中性墙面光型展示，保留实际光型边界', '道路光分布展示，突出连续性与均匀度']),
 'tone': ('光色表现', ['中性色路面或发光表面展示真实光色', '车灯局部发光场景，避免环境染色']),
 'fitment': ('车型适配', ['对应车型场景配合简洁适配信息', '车辆与产品分区，突出年份及配置条件']),
 'size': ('尺寸与空间适配', ['产品主视图配合准确尺寸标注', '真实结构特写配合空间关系说明']),
 'installation': ('安装便利', ['真实接口特写配合简短连接说明', '有素材支持的简洁安装步骤']),
 'electronics': ('电子兼容', ['产品技术特写配合已确认的兼容信息', '简洁功能分区说明，不虚构仪表测试结果']),
 'thermal': ('散热设计', ['真实散热部件特写配合散热路径示意', '产品主体配合风扇或散热片局部放大']),
 'lifespan': ('寿命与稳定性', ['额定寿命信息为重点，产品作辅助', '产品与长期使用价值的简洁分区']),
 'protection': ('防水与环境防护', ['防护使用场景配合已填写的防护等级', '产品细节配合防水防尘说明']),
 'coverage': ('多灯位组合', ['车辆灯位标注配合用户提供的型号与灯位文字；不放灯泡产品图'])
}
PALETTES = [
 {'name':'鲜明橙','anchor':'#f06000'},
 {'name':'经典黄','anchor':'#f4b400'},
 {'name':'科技蓝','anchor':'#2563eb'},
 {'name':'翡翠绿','anchor':'#00875a'},
 {'name':'性能红','anchor':'#d71920'},
 {'name':'宝石紫','anchor':'#7038c8'},
 {'name':'浓青蓝','anchor':'#009eaa'}
]
LOCK = threading.RLock()
def require(condition, message):
    if not condition: raise ValueError(message)
def text(value, limit, field):
    require(isinstance(value, str) and len(value) <= limit, f'{field}格式或长度不正确')
    return value.strip()
def palette(color):
    require(isinstance(color,str) and re.fullmatch(r'#[0-9a-fA-F]{6}',color), '请选择有效主导色')
    return theme(color)

def normalize(raw):
    require(isinstance(raw,dict), '方案格式错误')
    p=raw.get('product',{}); s=raw.get('style',{}); images=raw.get('images',[])
    require(isinstance(p,dict) and isinstance(s,dict), '产品及样式格式错误')
    require(p.get('type') in ('led','mixed','halogen'), '产品类型不正确')
    require(s.get('ratio') in ('1:1','4:5','4:3'), '不支持的比例')
    require(s.get('titleCase') in ('upper-title','title-sentence'), '请选择标题大小写')
    require(isinstance(images,list) and 1 <= len(images) <= 12,'请选择 1 至 12 个卖点')
    count=raw.get('count',len(images))
    require(type(count) is int and count==len(images),'图片数量与卖点数量不一致')
    product={k:text(p.get(k,''),limit,k) for k,limit in [('brand',100),('configuration',500),('fitment',4000),('facts',8000)]}
    require(product['configuration'], '请填写型号、数量与灯位')
    product['lifespan']=resolved_lifespan(product['facts'])
    product['lightColor']=resolved_light_color(product['facts'],p['type'])
    product['protectionRating']=resolved_rating(product['facts'])
    product['canbus']={'value':p['type']!='halogen' and not bool(re.search(r'(?:no|without|not equipped with)\s+CAN[- ]?BUS|(?:无|不支持|不带)\s*CAN[- ]?BUS',product['facts'],re.I)), 'source':'user-confirmed-catalog-default-unless-explicitly-excluded'}
    product.update(type=p['type'],subject='halogen' if p['type']=='halogen' else 'led',excludeGifts=True)
    seen=set(); slots=[]
    for image in images:
        require(isinstance(image,dict),'卖点格式错误')
        pid=text(image.get('pointId',''),100,'卖点标识')
        require(pid not in seen,'卖点重复');seen.add(pid)
        if pid in POINTS:
            require(not(p['type']=='halogen' and pid in ('electronics','thermal')),'卤素产品不能使用 LED 电子兼容或散热选项')
            title=POINTS[pid][0]
        else:
            require(re.fullmatch(r'custom-[a-zA-Z0-9-]+',pid),'未知卖点')
            title=text(image.get('sellingPoint',''),160,'自定义卖点')
            require(title,'请填写自定义卖点')
        slots.append({'pointId':pid,'sellingPoint':title})
    return {'product':product,'style':{'ratio':s['ratio'],'primaryColor':s.get('primaryColor'),'palette':palette(s.get('primaryColor')),'titleCase':s['titleCase']},'images':slots,'count':count}
def compile_plan(raw, asset_ids, seed=0, history=()):
    plan=normalize(raw)
    require(1<=len(asset_ids)<=12,'至少需要一张主产品图，最多 12 张')
    style=plan['style']; product=plan['product']; tasks=[]
    style['typography']=deepcopy(TYPOGRAPHY)
    contract=shared_contract(style,product)
    outline=[{'slot':i+1,**p,'visualRole':recipe(p['pointId'])['primary']} for i,p in enumerate(plan['images'])]
    product_slot=0
    for i,point in enumerate(plan['images']):
        pid=point['pointId']; methods=POINTS.get(pid,(None,['以用户自定义卖点为中心，使用资料支持的场景或产品特写']))[1]
        visual=recipe(pid)
        library=creative_brief(pid,point['sellingPoint'])
        methods=[m['name']+'：'+m['structure'] for m in library['methods']]
        direction='整合同类型小卖点，再选择或组合：'+'；'.join(m['name'] for m in library['methods'])
        issues=[]
        if pid=='fitment' and not product['fitment']: issues.append('请补充适配车型信息')
        # Coverage uses the external lamp assembly; no inferred internal high/low mapping is required.
        resolved=presentation(pid)
        photo_policy={'omit':'omit','optional':'optional-selected-reference','required':'use-selected-reference'}[resolved['photo']]
        chosen=[] if photo_policy=='omit' else [asset_ids[product_slot%len(asset_ids)]]
        if photo_policy!='omit': product_slot+=1
        case='主标题全大写；副标题每个单词首字母大写' if style['titleCase']=='upper-title' else '主标题每个单词首字母大写；副标题句首大写'
        brief={'slot':i+1,**point,'ratio':style['ratio'],'subject':product['subject'],'assetIds':chosen,'productPhotoPolicy':photo_policy,'resolvedPresentation':resolved,'lockedCopy':locked_copy(pid,product,style['titleCase']),'copyMode':'benefit-led-flexible','displayLibrary':library,'caseStudy':case_brief(pid),'contentControls':content_controls(pid,style['titleCase']),'assetSelectionPolicy':'无型号匹配；当前素材为优先参考，多图尽量分散使用；不为凑多样性强行放产品','visualDirection':direction,'alternativeDirections':methods,'visualRecipe':visual,'compositionPolicy':'尽量完整展示类型下不冲突的小卖点；一个主信息中心配相关分区；先合并重复、调整分区，再处理拥挤；不默认单场景或统一顶部大标题','copyCase':case,'missingInformation':issues,'status':'needs-information' if issues else 'prepared'}
        brief['layoutPlan']=choose(pid,library['subpoints'],seed,history)
        brief['visualDirection']=brief['layoutPlan']['name']+'：'+brief['layoutPlan']['structure']
        brief['alternativeDirections']=brief['layoutPlan']['allowedFamilies']
        brief['copyMode']='bounded-layout-copy'
        brief['prompt']=render_prompt(product,style,contract,outline,brief)
        compiled_image=json.loads(brief['prompt'].splitlines()[-1])['image']
        # Saved summaries must describe the same copy and display relation that
        # are actually submitted, not an older generic draft from locked_copy.
        copy=compiled_image['renderCopy']
        brief['lockedCopy']={'headline':copy['headline'],'subheadline':copy['subtitle'],
                             'labels':copy['labels'], 'shortStatements':copy.get('shortStatements',[])}
        brief['displayContract']=compiled_image['displayContract']
        brief['planningAuthority']='layoutPlan + compiled renderCopy; displayLibrary and caseStudy are research provenance, not competing execution instructions'
        tasks.append(brief)
    return {**plan,'images':tasks,'schemaVersion':'module-three-prepared-v1','assets':asset_ids,'setDesign':contract,'setOutline':outline,'reviewChecklist':REVIEW,'provider':'gemini','liveEnabled':False,'externalRequests':0,'state':'needs-information' if any(t['missingInformation'] for t in tasks) else 'prepared','displayLibraryRevision':DISPLAY_REVISION,'designStatus':'approved-art-direction-gemini-validation-pending','estimatedCost':None,'variationSeed':seed,'rulesRevision':REVISION}
class Store:
    def __init__(self, root):
        self.root=Path(root);self.root.mkdir(parents=True,exist_ok=True,mode=0o700)
    def _path(self, ident):
        require(isinstance(ident,str) and re.fullmatch('[0-9a-f]{32}',ident),'任务编号无效')
        return self.root/ident
    def _write(self, path, data):
        temp=path.with_suffix('.tmp');temp.write_text(json.dumps(data,ensure_ascii=False,indent=2));temp.replace(path)
    def save(self, raw, uploads):
        require(isinstance(uploads,list) and 1<=len(uploads)<=12,'请上传 1 至 12 张主产品图片')
        normalize(raw)
        decoded=[]
        for item in uploads:
            require(isinstance(item,dict),'图片格式错误')
            name=text(item.get('name',''),300,'图片名称');encoded=item.get('base64','')
            require(isinstance(encoded,str) and len(encoded)<=14*1024*1024,'图片大小超限')
            try: data=base64.b64decode(encoded,validate=True)
            except Exception: raise ValueError('图片编码不正确') from None
            require(0<len(data)<=10*1024*1024,'每张图片不能超过 10 MB')
            if data.startswith(b'\x89PNG\r\n\x1a\n'): mime,ext='image/png','.png'
            elif data.startswith(b'\xff\xd8\xff'): mime,ext='image/jpeg','.jpg'
            elif data[:4]==b'RIFF' and data[8:12]==b'WEBP': mime,ext='image/webp','.webp'
            else: raise ValueError('仅支持 PNG、JPEG 和 WebP 图片')
            decoded.append((name,data,mime,ext))
        ident=secrets.token_hex(16)
        with LOCK:
            planned=[]; submitted=[]
            for item in reversed(self.list()):
                record=self.get(item['id'])
                attempts={g['slot']:g for g in record.get('generation',{}).get('images',[])}
                for task in record['plan']['images']:
                    layout=task.get('layoutPlan',{})
                    entry={'pointId':task['pointId'],'variantId':layout.get('variantId'),
                           'detailIndex':layout.get('detailIndex'), 'scene':layout.get('scene')}
                    planned.append(entry)
                    g=attempts.get(task['slot'],{})
                    if g.get('attempts',0)>0 or g.get('state')=='completed':submitted.append(entry)
            # Unrendered drafts must not displace the compositions the customer actually saw.
            seen={x['pointId'] for x in submitted}
            history=[x for x in planned if x['pointId'] not in seen]+submitted
            plan=compile_plan(raw,[f'asset-{i+1}' for i in range(len(decoded))],seed=secrets.randbits(64),history=history)
            folder=self._path(ident);folder.mkdir(mode=0o700)
            metadata=[]
            for i,(name,data,mime,ext) in enumerate(decoded):
                filename=f'asset-{i+1}{ext}';(folder/filename).write_bytes(data)
                metadata.append({'id':f'asset-{i+1}','name':name,'file':filename,'mime':mime,'sha256':hashlib.sha256(data).hexdigest(),'size':len(data)})
            record={'id':ident,'createdAt':datetime.now(timezone.utc).isoformat(),'plan':plan,'assets':metadata,'simulation':None}
            self._write(folder/'record.json',record)
        return record
    def get(self, ident):
        path=self._path(ident)/'record.json'
        require(path.is_file(),'任务不存在')
        return json.loads(path.read_text())
    def list(self):
        records=[]
        with LOCK:
            for path in self.root.glob('*/record.json'):
                try:
                    r=json.loads(path.read_text());records.append({'id':r['id'],'createdAt':r['createdAt'],'count':r['plan']['count'],'state':r['plan']['state'],'configuration':r['plan']['product']['configuration']})
                except (OSError,ValueError,KeyError): continue
        return sorted(records,key=lambda r:r['createdAt'],reverse=True)
    def simulate(self, ident):
        with LOCK:
            record=self.get(ident)
            if record['simulation'] is None:
                record['simulation']={'state':'simulated','costUSD':0,'externalRequests':0,'images':[{'slot':t['slot'],'state':'simulated-no-image'} for t in record['plan']['images']]}
                self._write(self._path(ident)/'record.json',record)
        return record
