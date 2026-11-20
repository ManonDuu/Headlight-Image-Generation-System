"""Small reviewed-case retrieval; no network, model calls or image transport."""
from pathlib import Path

ROOT = Path(__file__).parent / 'research/layout-study-20261023'
CASES = {
 'illumination': [('novsight-1','同机位道路对照，将纵深、路肩与障碍细节放进一个场景'),('aux-h11-7','驾驶视角的冷暖光效果对照')],
 'beam': [('novsight-2','俯视道路解释光分布与会车关系，解释图从属'),('lasfit-9','结构原因与墙面、道路结果组合；仅适用已知调节结构')],
 'tone': [('aux-h11-7','同路面表现光色差异，不用全局蓝滤镜')],
 'fitment': [('sealight-reflector-kit','车型年份、灯具配置独立成区，区分适配条件'),('sealight-projector-kit','配置区别可视化；不照抄型号或错误灯位标签')],
 'size': [('aux-h11-9','共同灯座基准与独立尺寸线'),('aux-h11-12','明亮信息底色提高尺寸可读性')],
 'installation': [('novsight-5','每步表现一个动作，箭头说明动作方向'),('lasfit-10','一个主动作配从属步骤')],
 'electronics': [('lasfit-12','兼容功能分区与状态说明'),('aux-h11-10','驱动与功能建立联系，禁止凭外观虚构内部')],
 'thermal': [('lasfit-13','实际部件串成传热路径'),('termitor-3','结构分解配对应引线，仅已知内部结构时采用')],
 'lifespan': [('aux-h11-3','长期利益配真实结构解释'),('novsight-4','减少更换的视觉隐喻，仅借鉴关系，不复制数量倍数')],
 'protection': [('lasfit-15','产品防护主视觉配从属环境条'),('aux-h11-11','多种环境围绕同一主题，保留完整覆盖')],
 'coverage': [('sealight-reflector-kit','按灯位组织信息，配置条件独立成区'),('sealight-projector-kit','仅学习信息分组；本系统不展示未识别的灯泡型号照片')]
}

# Production obligations distilled from the reviewed examples. Research alternatives
# remain archived; the chosen composition retains this category's explanatory relation.
DISPLAY_CONTRACTS = {
 'illumination': ('Matched lighting comparison with readable distance, verge and target detail; each identity stays inside its own lighting region', 'No fabricated measured distance, gain ratio or changed target materials'),
 'beam': ('One connected light field explains width, continuity and soft boundaries; annotations attach to the actual surface', 'Precise wall cutoff, adjustment mechanism and oncoming-glare proof require known optics; they are not unconditional defaults'),
 'tone': ('Show resolved light color ON recognizable real surfaces, or relate a headlamp detail to the surface it illuminates', 'No whole-scene blue filter or invented color-accuracy measurement'),
 'fitment': ('A recognizable unbranded vehicle and exact supplied Fits model/year/qualifiers share a clear information hierarchy', 'No invented trim exclusions, headlamp configurations or universal fit'),
 'size': ('Visible mounting base and rear-space envelope have an explicit spatial relationship; dimension endpoints belong to the actual object', 'No invented millimeters, stock-bulb equality or unseen housing geometry'),
 'installation': ('Different stages form a readable remove-fit-check sequence, either substantial sequential regions or one main fitting view plus a subordinate sequence', 'General overview only without matching installation material; do not import competitor socket, rotation, tools or installation minutes'),
 'electronics': ('Separate bulb-warning control, steady lighting and radio compatibility outcomes using coherent status symbols and evidence-linked text', 'No fake PCB, universal error-free claim or decorative cockpit replacing the outcomes'),
 'thermal': ('Actual visible cooling surfaces plus outward heat-path explanation; close-ups explain the heat relationship instead of merely showing shiny metal', 'Internal exploded geometry, hidden fans and heat pipes require actual evidence; external material remains the fallback'),
 'lifespan': ('Resolved lifespan hours and a time/use relation are supported by intact product or actual external details; vary the hierarchy rather than deleting lifespan evidence', 'Decay curves and bulb-equivalence ratios require supplied comparative data; default hours cannot imply either'),
 'protection': ('Use the selected four-weather relationship OR water/dust material macro; retain the complete evidence of that method', 'IP supports bulb water/dust protection, not weather visibility, temperature extremes or whole-vehicle waterproofing'),
 'coverage': ('Vehicle overview or external headlamp detail connects to the supplied model/count configuration; keep scope legible', 'No photo-to-bulb-model guessing or inferred internal high/low position; unknown positions remain external-assembly level'),
}

def display_contract(point_id, method_id):
    if point_id not in DISPLAY_CONTRACTS:
        return {'category':point_id,'method':method_id,'principle':'Explain the supplied custom benefit with directly related evidence','boundary':'Do not invent product claims','sourceCases':[]}
    principle,boundary=DISPLAY_CONTRACTS[point_id]
    return {'category':point_id,'method':method_id,'principle':principle,'boundary':boundary,
            'sourceCases':[key for key,_ in CASES[point_id]],
            'authority':'Preserve this explanatory relationship within the selected composition; do not combine all archived examples. Source images are not automatically sent to Gemini.'}

def case_brief(point_id):
    return {
      'revision':'reviewed-cases-v1',
      'referenceMode':'textual-analysis-only; images are not automatically attached',
      'examples':[{'id':key,'asset':'research/layout-study-20261023/assets/'+key+'.jpg','learn':lesson}
                  for key,lesson in CASES.get(point_id,[])],
      'selection':'先按内容和已知条件选一种主要展示关系，再安排辅助信息；不按图号选，不混用所有案例',
      'informationMap':'先为每个不冲突小卖点安排视觉归属：主场景、局部、标注或图标。同一画面可承担多个相关小点；不能把每个小点都变成独立卡片',
      'copyStructure':'标题说购买收益或顾虑；副标题解释实现方式；标签指向画面具体位置。三者不复述，不出现无解释作用的Explore、Discover等填充句',
      'preserve':'丰富度来自比较、动作、因果或空间关系。拥挤时先调整分区和文案，不删除独立小点。天气保持四项，标题与副标题保留明显空隙',
      'limits':'案例只证明展示方式存在，不证明转化率；不迁移竞品参数、外形、型号、内部结构及绝对承诺'
    }
