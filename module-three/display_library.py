"""Curated market observations and compact, provider-neutral creative briefs.

This is a display vocabulary, never a database of the customer's product claims.
No network or model calls. Full provenance stays here; prompts get one category.
"""
from copy import deepcopy

REVISION = 'automotive-display-library-20261023-v1'
SOURCES = {
 'auxito-h11': {'url':'https://auxito.com/products/h11-led-headlight-bulb-80w-16000lm-canbus-ready-beam-adjustable-lamp-mini-size', 'review':'13 secondary images visually reviewed; road comparisons, wall patterns, dimensions, cooling, electronics, weather and installation'},
 'lasfit-lsplus': {'url':'https://www.lasfit.com/products/h11-h8-h9-led-headlight-bulbs', 'review':'10 secondary images visually reviewed, gallery indices 6–15; includes product, mechanism and effect combinations'},
 'termitor-h1': {'url':'https://www.amazon.com/dp/B0DC6G2C8K', 'review':'7 gallery secondary images visually reviewed; one HID-kit compatibility graphic excluded from LED fitment inference'},
 'sealight-s7s': {'url':'https://sealight-led.com/product/sealight-s7s-9005-9006-led-headlight-bulbs', 'review':'weather and three-step installation A+ images visually reviewed; wide A+ compositions require adaptation for listing ratio'},
 'auxito-m6': {'url':'https://auxito.com/products/h13-9008-led-headlight-bulbs-6500k-white-adjustable-canbus-ready-light-bulb', 'review':'two A+ graphics visually reviewed: multi-attribute comparison and overhead-road glare comparison'},
 'auxito-ram': {'url':'https://auxito.com/products/2013-2015-ram-1500-led-bulbs', 'review':'fitment and lamp-position text reviewed; first three gallery images are product-only and do NOT establish a fitment-layout precedent'},
 'user-beam': {'files':['original-generated-output (6).jpg','original-generated-output (7).jpg'], 'review':'both visually reviewed; overhead-road scene, driver inset, support labels and lower effect comparisons; seller provenance and conversion not verified'},
 'user-weather': {'files':['城市夜行驾驶场景-3.png','夜路车灯，照亮前行-1.png','夜行车灯场景海报-2.png'], 'review':'three visually reviewed; concern-led split scene, multi-weather panels and emotional road scene; not performance evidence'}
}

def method(key, name, structure, condition, evidence, sources):
 return {'id':key, 'name':name, 'structure':structure, 'condition':condition,
         'evidence':evidence, 'sourceIds':sources}

# "subpoints" are topics to cover, not unconditional factual promises.
CATALOG = {
 'illumination': {
  'subpoints':['照明亮度','前方照射纵深','横向覆盖与路肩','路面、标线及前方细节','相关流明与光色信息'],
  'benefit':'让客户理解夜路照明升级带来的实际感受',
  'methods':[
   method('matched-road','同场景效果对比','同一机位、道路和裁切下的两种照明状态；相关细节与参数靠近对应画面','有明确比较基准；不任意压暗另一侧或补写倍数','observed',['termitor-h1','auxito-h11']),
   method('scene-details','道路全景与远近细节','主道路占主体，路肩、标线或远处区域以局部连接；标签解释各自作用','细节来自同一主场景；不把不同曝光当实测','adapted',['termitor-h1','user-beam']),
   method('source-effect','光源与道路效果组合','光源局部、道路主效果和简短信息形成因果阅读顺序','外形锁定上传素材；芯片类别及输出数字不猜测','observed',['lasfit-lsplus','auxito-h11']),
   method('multiple-views','驾驶视角与外部视角','驾驶者所见为主，外部车辆灯光为辅，两者解释同一照明体验','避免重复相似道路；不伪装成同次真实拍摄','adapted',['auxito-h11','user-beam'])]},
 'beam': {
  'subpoints':['光线集中与分布','照明连续性与均匀度','暗区与阴影','近光边界及会车关系','光源位置或调节关系'],
  'benefit':'同时解释自己的路面照明和对向驾驶者的感受',
  'methods':[
   method('overhead-traffic','俯视光场与会车关系','俯视道路表现光覆盖，驾驶者局部连接对应车辆，可补道路视角或对照区','近远光与行驶方向明确；不靠驾驶者微笑证明零眩光','observed',['auxito-m6','user-beam']),
   method('wall-road','墙面光型与道路效果','墙面光型和道路光分布并列，各自用短标签解释；主次不同','不为远光画近光截止线；无实测不声称这是客户灯具实测','observed',['lasfit-lsplus','auxito-h11']),
   method('alignment','光源位置与光型关系','光源位置或调节部位特写，连向效果区域，辅助说明对齐关系','只有明确结构才能画调节机构或 1:1 位置比较','observed',['auxito-h11','lasfit-lsplus']),
   method('beam-details','道路光分布与局部说明','主场景配集中区域、边缘和连续照明区域标注；圆形或矩形放大均可','绝对无暗区、无眩光不是自动承诺；无基准不用优劣对照','adapted',['user-beam','auxito-h11'])]},
 'tone': {
  'subpoints':['色温','冷白或暖白的光色','车灯外观一致性','照亮表面的颜色感受'],
  'benefit':'让客户预判安装后的光色，而不是把白光误当蓝光',
  'methods':[
   method('color-compare','同环境光色对照','两种已知光色照亮同一中性路面，色温贴近各自区域','比较色温已知；不加入亮度提升或雨雾穿透暗示','observed',['lasfit-lsplus','auxito-h11']),
   method('lamp-surface','灯具外观与照亮表面','已安装灯具局部和中性路面形成大小分区，突出实际色温','环境滤镜不能改变光色；只强调本产品光色','adapted',['auxito-h11']),
   method('color-detail','光色主场景与近景','车辆场景为主，车灯近景和色温短标签为辅','不默认整车所有灯位均含在套装内','adapted',['auxito-h11'])]},
 'fitment': {
  'subpoints':['车型与车系','年份范围','灯具配置条件','适用及排除范围','购买前核对位置与型号'],
  'benefit':'降低买错配置的顾虑',
  'methods':[
   method('vehicle-info','车辆与适配分区','车辆主画面配清晰车型、年份和配置条件信息区','外观场景不代表所有配置通用','proposed',['auxito-ram']),
   method('configuration-compare','配置区别展示','两种明确配置的灯具或车辆特征并列，清楚区分适用条件','必须能确认区别；不编造灯壳或配置照片','proposed',['auxito-ram']),
   method('fit-check','适配范围与核对流程','年份车型信息主区，配核对原灯型号、灯位、配置的简洁路径','无车型资料时表达核对方法，不新增适配范围','proposed',['auxito-ram'])]},
 'size': {
  'subpoints':['整体长度','尾部直径及占用','灯座与接口关系','安装空间','与原灯的外形关系'],
  'benefit':'回答能否装进灯壳、空间是否合适',
  'methods':[
   method('dimension-views','正侧视与尺寸标注','正侧视或局部配尺寸线，关键安装位置加放大','数字和素材型号能对应；照片不能自动测出尺寸','observed',['auxito-h11']),
   method('same-base','同基准外形对照','原灯与 LED 按相同灯座基准对齐，标出相关空间关系','有对应原灯与尺寸；不能从任意照片推导 1:1','observed',['auxito-h11','termitor-h1']),
   method('space-detail','尾部与接口局部组合','外形主视图加尾部、接口局部，解释检查安装空间的位置','无尺寸仍可展示真实外形；不保证无需改防尘盖','adapted',['auxito-h11'])]},
 'installation': {
  'subpoints':['安装路径','插接关系','固定或锁紧','光源朝向核对','是否需要额外部件'],
  'benefit':'让客户理解怎样完成安装及需要注意什么',
  'methods':[
   method('steps','连续安装步骤','插入、固定、连接等实际步骤，用连续分区和动作箭头解释','步骤依据真实结构；不默认旋转锁紧或三分钟安装','observed',['sealight-s7s','lasfit-lsplus']),
   method('action-connect','安装动作与接口特写','主要安装动作配接口和固定处局部，短标签说明关系','素材缺少接口时不用想象补画','observed',['termitor-h1','lasfit-lsplus']),
   method('connection-check','接口外形与安装检查','真实可见部件为主体，简短流程说明核对、安装和检查','不添加免工具、免改线或无极性保证','adapted',['sealight-s7s'])]},
 'electronics': {
  'subpoints':['车辆电子系统兼容','故障提示','频闪','无线电干扰','驱动与解码关系'],
  'benefit':'回应更换灯泡后是否报错、闪烁或干扰的顾虑',
  'methods':[
   method('system-functions','系统关系与功能分区','车辆系统关系示意，配报错、频闪、干扰等清楚的信息分区','概念示意不冒充真实仪表测试；区分各项能力','adapted',['lasfit-lsplus','termitor-h1']),
   method('driver-functions','驱动部件与功能解释','驱动器或真实产品局部为主，各功能靠近对应解释','不想象 PCB 或芯片剖面；CANBUS 不等于全部无报错','observed',['auxito-h11','lasfit-lsplus']),
   method('states','功能状态对照','明确标注的概念状态对照，配适用范围信息','不是测试照片；无具体能力时改成兼容检查信息','adapted',['lasfit-lsplus'])]},
 'thermal': {
  'subpoints':['散热结构','热量传递路径','鳍片或散热表面','风扇与热管等具体部件','工作热量管理'],
  'benefit':'解释热量怎样离开光源，而非只展示金属材质',
  'methods':[
   method('part-path','散热部件与路径','产品或局部为主，箭头串联实际散热部件，短标签贴近结构','只画真实存在的部件；普通散热箭头不需要虚构温度','observed',['auxito-h11','lasfit-lsplus']),
   method('detail-panels','多个散热局部组合','一个主体配鳍片、热管或风扇细节，按实际结构选取','没有风扇或铜管不能补出；不要复制竞品外形','observed',['lasfit-lsplus','auxito-h11']),
   method('exploded','结构分解与热量关系','已知内部结构分层展开，用标注解释各部位','需要明确内部结构；单张外观图不适合此方法','observed',['termitor-h1']),
   method('visible-fins','外部鳍片与表面细节','外部鳍片主特写配不同区域放大和热量向外示意','仅有外观照片时可用；不把散热设计推导成寿命数字','adapted',['auxito-h11'])]},
 'lifespan': {
  'subpoints':['使用寿命','长期稳定性','亮度保持','减少更换负担','相关散热或驱动设计'],
  'benefit':'解释长期使用价值和更换顾虑',
  'methods':[
   method('life-structure','寿命信息与结构解释','寿命信息为主，散热与驱动局部作辅助，连接长期使用价值','不从外形推算寿命，不把小时数擅自换算年数','observed',['auxito-h11','lasfit-lsplus']),
   method('decay-compare','衰减与效果对照','相同使用条件下的亮度保持或路面效果对照','仅使用实际给出的衰减与时长；不复用竞品百分比','observed',['termitor-h1']),
   method('long-use','使用情境与耐用设计','长期使用主题场景配真实可见的设计细节，保持文字具体','不凭场景暗示经年实测或保证永久稳定','adapted',['auxito-h11'])]},
 'protection': {
  'subpoints':['防水','防尘','不同使用环境','温度条件','防护等级与产品关系'],
  'benefit':'回应环境变化下的产品防护顾虑',
  'methods':[
   method('weather-panels','多环境组合','雨、尘或其他适用环境以二至四区组合，一个主题统领','有 IP 可表达水尘防护；耐极寒耐高温不是默认能力','observed',['auxito-h11','user-weather']),
   method('weather-rating','主环境与等级信息','大幅环境画面配防护等级，辅助雨滴或环境细节','防护不等于雨雾照明提升；无等级不补写 IP 数字','adapted',['sealight-s7s','user-weather']),
   method('product-weather','产品与环境分区','产品细节为主或辅，环境小图说明适用语境','不裸灯泡浸水冒充实测；不让天气遮盖产品外形','observed',['sealight-s7s','lasfit-lsplus']),
   method('concern-scene','具体顾虑场景切入','一个具体雨夜场景吸引注意，旁边以防护信息解释产品关联','避免只剩交通宣传；不自动宣称任何天气都视野清晰','adapted',['user-weather'])]},
 'coverage': {
  'subpoints':['套装涉及灯位','各灯位型号','数量及组合','主产品覆盖范围','当前车型配置'],
  'benefit':'让客户看清套装解决哪些灯位需求',
  'methods':[
   method('vehicle-map','车辆灯位与文字对应','车辆上标注灯位，旁边用用户给出的型号数量文字对应','不使用灯泡产品图，不猜测图片型号或灯位','proposed',['auxito-ram']),
   method('position-panels','车辆总览与灯位局部','车辆总览配已知灯位的灯具局部，每区列相应型号数量','局部应为灯具位置，不是独立灯泡；无对应不补猜','proposed',['auxito-ram']),
   method('coverage-table','灯位覆盖与清晰清单','车辆灯位信息与组合清单分区，便于核对套装范围','混合赠品不列作 LED 主产品；不扩大为整车升级','proposed',['auxito-ram'])]}
}

def creative_brief(point_id, selling_point=''):
 """Only this category's short candidates enter the model context."""
 entry = CATALOG.get(point_id)
 if entry is None:
  return {'revision':REVISION, 'category':point_id, 'coveragePolicy':'保持用户自定义意图，尽量完整表达，不强行并入其他类型',
          'subpoints':[selling_point or '自定义核心内容'], 'methods':[
           {'id':'custom-composition','name':'按内容组合','structure':'选择场景、关系、细节或对比解释用户指定内容','condition':'不新增具体产品结构与数字'}]}
 result = deepcopy(entry)
 result.update(revision=REVISION, category=point_id,
   coveragePolicy='默认尽量展示全部不冲突的小卖点，用户不必逐项填写；先合并重复内容，优先用画面解释。不得为简洁而只留一个小卖点',
   planning='先组织小卖点，再选择一个主方法并按需组合辅助方法；方法不是必须逐一使用的模板',
   factPolicy='小卖点是表达主题，不是已验证承诺；具体数字、结构、型号与配置不凭空补出。未知能力可改为检查或结构说明，不冒充性能结论')
 for candidate in result['methods']:
  candidate.pop('sourceIds', None)
  candidate.pop('evidence', None)
 return result
