"""Small, provider-neutral visual briefs shared by chat image tests and production."""
from style_contract import REVISION

RULES = {
 'illumination': {'question':'道路上能看清什么？','primary':'道路照明效果','layout':'场景主导，标题置于安静区域，产品可省略或作小辅助','avoid':'大灯泡遮住道路；亮度、距离、宽度三个同等大数字抢主次','copy':'围绕照明升级，尽量整合亮度、纵深、覆盖与路面细节；数字不编造'},
 'beam': {'question':'光线分布是否清楚、均匀？','primary':'光型边界与光分布','layout':'光场占主要面积，少量标签辅助理解','avoid':'与亮度图重复同一条道路；凭空给远光画近光截止线','copy':'选一个主要光型特点，其余作为简短辅助'},
 'tone': {'question':'实际发出的光是什么颜色？','primary':'中性环境中的真实光色','layout':'以可读光色的发光表面为主体，色温数字辅助','avoid':'全局滤镜染色；把色温当亮度提升','copy':'色温与对应光色，不自动附加雨雾能见度声明'},
 'fitment': {'question':'是否适合我的车辆与配置？','primary':'车型与清晰的适配范围','layout':'车型场景与适配文字分区，年份、车型、配置条件易扫读','avoid':'用通用车辆冒充已验证车型；省略排除条件；塞满装饰图标','copy':'以用户给出的年份、品牌、车型和配置为准'},
 'size': {'question':'尺寸和安装空间如何？','primary':'产品外形及尺寸关系','layout':'上传视角的产品与空间关系，尺寸线留出独立空间，不重建未提供视角','avoid':'未提供的尺寸；无依据的 OEM 1:1 比较；凭空补出灯壳内部','copy':'对应型号的真实尺寸或明确紧凑结构信息'},
 'installation': {'question':'怎样连接与安装？','primary':'接口或安装动作关系','layout':'连续安装概览或主要安装关系配步骤条；未知具体接口用概念流程，保留不同阶段','avoid':'编造接头、线束、适配器或手部动作；重复摆放多个相同产品','copy':'实际安装方式；分钟数、免工具、免改线须来自资料'},
 'electronics': {'question':'提供哪些电子兼容能力？','primary':'已确认的兼容信息','layout':'产品与少量清晰状态说明分区，保持技术表达简洁','avoid':'装饰性仪表冒充测试；CANBUS 自动扩大为所有车型无报错','copy':'尽量覆盖电子兼容、报错、频闪与干扰主题，但不把未知能力写成无报错保证'},
 'thermal': {'question':'如何管理工作热量？','primary':'真实散热部件','layout':'散热部位特写为主，箭头和局部放大解释结构','avoid':'不存在的内部剖面；夸张火焰；用有风扇推出寿命','copy':'风扇、散热片等已提供结构，少量标签'},
 'lifespan': {'question':'长期使用价值是什么？','primary':'解析后的寿命或稳定性信息，用户输入优先','layout':'核心信息突出，产品与场景作支撑，避免空洞大数字','avoid':'编造年限、运行时长、衰减曲线或与其他产品的寿命差距','copy':'保留额定、预计或使用条件等原有限定'},
 'protection': {'question':'能应对哪些环境条件？','primary':'资料支持的防护能力','layout':'环境场景或产品防护细节，等级与场景建立清晰关系','avoid':'浸水图冒充测试；自动从防水推出雨雾照明提升','copy':'使用解析后的防护等级，用户输入优先，其次已确认的默认等级'},
 'coverage': {'question':'主产品对应哪些灯位？','primary':'主产品与灯位对应关系','layout':'仅车辆灯位标注＋用户提供的型号与灯位文字，不展示灯泡产品照片','avoid':'展示灯泡照片或照片到灯位连线；猜测型号与灯位关系；混入赠品；把局部覆盖称整车升级','copy':'按当前车型和配置列型号、数量与灯位，范围明确'}
}
DEFAULT={'question':'用户指定的价值如何一眼理解？','primary':'自定义卖点的核心信息','layout':'根据实际内容选择场景、特写或关系展示','avoid':'增加未经提供的性能、参数或事实','copy':'保留用户意图，不强制映射到其他卖点'}
def recipe(point_id):
    return dict(RULES.get(point_id,DEFAULT))

def shared_contract(style, product):
    return {
      'revision':REVISION,
      'scope':'Amazon US secondary listing images only',
      'ratio':style['ratio'], 'palette':style['palette'], 'typography':style['typography'],
      'titleCase':style['titleCase'],
      'subject':product['subject'],
      'productPolicy':'以提供素材锁定外形、材质、颜色及数量；不因风格修改产品。混合套装只展示 LED 主产品。',
      'assetPolicy':'图片无需型号标注或分组。一张素材可反复使用；多张时每张附图可任选一张，整套尽量用到不同素材，不强制。效果图可不展示产品。不得猜测图片型号或补画缺失外形。',
      'coveragePolicy':'只用车辆灯位标注与用户提供的型号、灯位对应文字，不使用灯泡产品图。',
      'compositionPolicy':'每张围绕一个购买顾虑，可组合主场景、对比或局部证据、按需要安排相关短标签；一个主要信息中心不等于只有一个画面。相邻图片避免重复标题位置与图文比例。',
      'brandPolicy':'品牌仅在对比中标识自家产品，不作角落注脚；车辆无商标标识；适配车型文案以 Fits 开头。',
      'artDirection':'色彩饱满、真实的汽车商业摄影与成熟信息排版：正体无衬线、统一 Inter 字体层级、真实光影、细线标注；场景满幅无四周色条，文字留安全距离。主题色必须用于标题利益关键词与主要标签底面，采用同色相渐变；副标题保持易读的中性色，禁止整张只有白字加细色线。文字清晰、对比明确，功能性图形优先于无意义装饰。',
      'creativeFreedom':'以 displayLibrary 的当前类型小卖点和候选方式组织画面。按选定方法组合不冲突的小卖点，避免每轮内容完全相同，允许场景、对比、局部、关系或步骤组合。圆形放大、箭头和分区均可用于解释，不为装饰堆叠。不得按图号套模板。',
      'copyPolicy':'美式英语；先回答购买顾虑，再用已知事实支撑。避免说明书式命名、空洞口号和恐吓。主副标题遵守所选大小写；副标题和标签末尾不加句号；型号、品牌名、单位保持正确写法。',
      'measurementPolicy':'有对比数据或明确基准才呈现性能优劣对照；无数据仍可用主场景加局部、结构关系、适配信息分区增强解释。示意图标注不使虚构性能差距变得合法。',
      'exposurePolicy':'保留夜景语境但不整套压暗去饱和。路面、产品材质和关键信息清楚可见；曝光服从当前卖点：电子兼容以报错顾虑和功能结果为主，如使用照明场景局部才要求夜间开灯；尺寸、安装等结构图优先明亮工作环境；保留绿色植被、暖色地面和材质的中间调，不为白字给全图罩灰黑蒙层；必要时仅在文字背后局部过渡。',
      'deduplicationPolicy':'只合并同义文字和没有新增解释的重复装饰；保留不同场景、角度和小卖点覆盖。主副标题、标签按各自文字角色应用大小写。',
      'conversionPolicy':'每张必须能回答：顾虑是什么、凭什么相信、画面如何解释。图多不等于有效，所有辅助内容必须解释同一购买决策。'
    }

REVIEW = [
 '品牌与比较对象必须各在所属区域；不得把自家品牌贴在较差效果上',
 '每个标签解释具体利益、必要身份或检查事项，并与 evidenceMap 的可见证据一致；不按列表顺序机械排位置',
 '电子兼容中问题状态从属且明确被处理；不得将告警当成功结果',
 '整个主标题使用饱满主题色，不加黑压深、不混入黑白中性字；按主题色渐变端点执行',
 '主产品外形、数量与素材一致；无赠品混入',
 '印出的文字全部来自英文文案清单；不出现字体规格、色码、规划说明或中文原始输入',
 '背景满幅延续到四边，无白边、近白外框、白色边缘渐隐；天然白色物体不等同留白',
 '所选类型的小卖点尽量完整整合；重复合并、冲突剔除；未擅自换点或改序',
 '参数、型号、灯位和适配限定正确，比较没有编造基准',
 '选定比例从构图开始应用，无拼成整套九宫格',
 '主副标题大小写、色板、字体与标注风格一致',
 '画面主次明确，无辅助元素压过卖点；文字清楚无拥挤',
 '整套协调且每张各有分工；有表达方法的变化，无为追求简洁而丢失内容'
]

def test_packet(plan):
    """No provider transport, no credentials, no image bytes; references must be attached."""
    return {
      'schemaVersion':'module-three-chat-image-test-v1',
      'logicRevision':plan['setDesign']['revision'],
      'status':'awaiting-product-review-and-image-attachments',
      'sharedDesign':plan['setDesign'],
      'setOutline':plan['setOutline'],
      'assetReferences':plan['assets'],
      'instructions':'先核对产品资料和素材对应关系。每次使用对应单张 prompt 和产品图片生成一张独立图。不得把整套任务拼在一张中。不得把第一张图的卖点内容复制到其他张。',
      'images':[{'slot':t['slot'],'sellingPoint':t['sellingPoint'],'assetIds':t['assetIds'],'prompt':t['prompt'],'reviewQuestions':t['missingInformation']} for t in plan['images']],
      'reviewChecklist':REVIEW,
      'providerParity':'Chat image tool 与 Gemini 使用同一份 prompt、产品资料、共享规范及素材语义。适配器仅处理模型参数、素材传输与返回解析。效果仍须各自验收。',
      'paidRequests':0
    }

# Product identity access is resolved here; composition comes from the category library.
def presentation(point_id):
    if point_id in ('coverage','fitment'):
        return {'photo':'omit','scene':'车辆与配置、灯位信息，不使用独立灯泡图片',
                'layout':'从 displayLibrary 按当前内容选择并组合方法；保留既定适配及灯位边界',
                'surface':'adaptive','selection':'planner-selects-one-approved-method'}
    return {'photo':'optional' if point_id in ('illumination','beam','tone','protection','electronics','lifespan') else 'required',
            'scene':'先整合同类型不冲突的小卖点，再选择场景、效果、关系或真实产品细节',
            'layout':'由 displayLibrary 的候选方法决定；允许多分区、对比、圆形或矩形放大和解释箭头，不默认完整立式灯泡',
            'surface':'adaptive','selection':'planner-selects-one-approved-method'}

def locked_copy(point_id, product, case):
    import re
    titles={'illumination':'Light Up Your Night Drive','beam':'Beam Pattern','tone':'Cool White Light','fitment':'Check Your Fit Before You Buy','thermal':'A Closer Look At Cooling','protection':'Environmental Protection','coverage':'Lighting Positions','electronics':'Electronic Compatibility','lifespan':'Service Life','custom-led-array':'See The Light Source Up Close'}
    subs={'illumination':'LED illumination for the road ahead','tone':'See the cool white finish of your lighting upgrade','fitment':product['fitment'],'thermal':'External cooling fins, shown in detail','protection':'Protection against water and dust','custom-led-array':'A detailed view of the LED chip array'}
    title=titles.get(point_id,'Product Details');sub=subs.get(point_id,'').rstrip().rstrip('.。')
    # Fitment text is data: preserve vehicle identifiers and years verbatim.
    if case=='upper-title': title=title.upper()
    if sub and point_id=='fitment' and not re.match(r'^fits\b',sub,re.I): sub='Fits '+sub
    if sub and point_id!='fitment':
        if case=='upper-title': sub=' '.join(w[:1].upper()+w[1:] for w in sub.split())
    result={'headline':title,'subheadline':sub,'labels':[]}
    if point_id=='tone':
        found=re.search(r'\b(\d{4,5})\s*K\b',product['facts'],re.I)
        if found: result['headline']=found[1]+'K '+('COOL WHITE' if case=='upper-title' else 'Cool White')
    if point_id=='protection':
        found=re.search(r'\bIP\s*(\d{2})\b',product['facts'],re.I)
        rating=product.get('protectionRating',{}).get('value') or ('IP'+found[1] if found else 'IP68')
        result['headline']=rating+' '+('PROTECTION' if case=='upper-title' else 'Protection')
    return result
