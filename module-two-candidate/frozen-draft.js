// Single source for the local preview and request builder. DRAFT, not historical prompt.
var FROZEN = {
  version: 'reference-81g-draft-02', approved: false,
  reference: {path:'assets/81gMZuoRq6L._AC_SL1500_.jpg', width:1200,height:1500,sha256:'d8b87596d3ea2218154b03abafd55333a8f46aa7fcdaca0f53fb63239c2d73ef'},
  example: {path:'assets/exec-2f5b9ebc-8a90-43e8-aaf9-c4a4c0117844.png',scope:'仅结构相似与场景差异程度；文字、字体及间距不作为合格示例'},
  geometryMethod:'人工查看本地原图后按 1200×1500 像素坐标估读；不是自动检测或历史精确合同。框边约 ±10px，仅定位草稿，不是验收容差。',
  regions:[
    {id:'hero',name:'主雨景',box:[0,0,1200,1045],note:'蓝色 SUV，前方三分之四视角，雨夜城市道路；文字覆盖其上'},
    {id:'rain',name:'雨天卡片',box:[60,1051,528,191],note:'左上，车辆在左，雨图标与文字在右'},
    {id:'snow',name:'雪天卡片',box:[607,1051,528,191],note:'右上，车辆在左，雪图标与文字在右'},
    {id:'fog',name:'雾天卡片',box:[60,1261,528,191],note:'左下，车辆在左，雾图标与文字在右'},
    {id:'dust',name:'尘土卡片',box:[607,1261,528,191],note:'右下，车辆在左，尘土图标与文字在右'}
  ],
  text:[
    {text:'IP68 WATERPROOF',box:[238,77,735,62],kind:'营销标题',action:'本次拟删除',font:'无衬线重粗体；具体字体未知；预览近似 Arial Black，约 70px'},
    {text:'Not Blinding Oncoming Drivers',box:[320,164,563,36],kind:'营销副标题',action:'本次拟删除',font:'无衬线粗体；预览近似 Arial Bold，约 39px'},
    {text:'-40°C',box:[69,989,111,37],kind:'功能温度刻度',action:'原文保留，不改为 cold',font:'Arial Bold 约 39px，仅近似'},
    {text:'+80°C',box:[991,989,116,37],kind:'功能温度刻度',action:'原文保留，不改为 warm',font:'Arial Bold 约 39px，仅近似'},
    {text:'Rainy',box:[455,1182,107,40],kind:'天气标签',action:'逐字保留大小写',font:'Arial Bold 约 38px，仅近似'},
    {text:'Snowy',box:[985,1182,130,40],kind:'天气标签',action:'逐字保留大小写',font:'Arial Bold 约 38px，仅近似'},
    {text:'Foggy',box:[452,1387,116,40],kind:'天气标签',action:'逐字保留大小写',font:'Arial Bold 约 38px，仅近似'},
    {text:'Dusty',box:[993,1387,114,40],kind:'天气标签',action:'逐字保留大小写',font:'Arial Bold 约 38px，仅近似'}
  ],
  temperatureBar:[191,976,779,51],
  mode:'no-marketing-copy; retain functional labels verbatim',
  modeSelection:'UNCONFIRMED PROPOSAL for this test; historical approval defines this optional mode but does not select it for this image',
  proposal:'银灰 SUV；河岸仓库和桥梁雨景；天气卡片更换车辆细节与具体环境；保持区域、视角、气候关系、光束方向及阅读顺序。',
  missing:['原 02C 提示词未恢复：使用明确标记的新草稿','原字体无法从位图确证；拟保留视觉字形，Arial Bold 仅作预览近似','框位来自人工估读，尚待本次冻结确认；不冒充历史已批准几何值'],
  call:{model:'gemini-3.1-flash-image',endpoint:'https://generativelanguage.googleapis.com/v1beta/interactions',imageSize:'2K',aspectRatio:'4:5',expectedWidth:1856,expectedHeight:2304,maxOutputTokens:4096,thinkingLevel:'minimal',requests:1,retries:0,timeoutSeconds:180,requestImages:1,acceptedImageCount:1,budgetMicroUSD:260000,conservativeMicroUSD:247808,realEnabled:false},
  prompt:[
    'Create exactly ONE reconstructed image using the attached original image as the visual reference. This is a new implementation prompt, not a recovered 02C prompt.',
    'Use 4:5 portrait, 2K. Preserve the original composition, reading order, subject categories, camera viewpoint, hierarchy, region functions and proof relationships. The layout is one large rainy hero scene plus FOUR weather cards in a 2 by 2 grid. Never use three cards.',
    'Coordinates below are frozen draft anchors in a 1200 by 1500 reference canvas; scale proportionally to the output. Hero [0,0,1200,1045]; rain [60,1051,528,191]; snow [607,1051,528,191]; fog [60,1261,528,191]; dust [607,1261,528,191]. Boxes are x,y,width,height. Temperature bar [191,976,779,51]. Preserve the card borders, spacing, icon placement and hierarchy. Do not redesign or move regions.',
    'No marketing copy: remove IP68 WATERPROOF and Not Blinding Oncoming Drivers without filling that area with a new title or moving the vehicle/cards upward. Remove visible vehicle brand badges and marketing watermarks. Keep the functional temperature bar and exact labels -40°C and +80°C; keep exact weather labels Rainy, Snowy, Foggy, Dusty with original case and positions. No cold/warm substitutions, no new claims, no extra text.',
    'Preserve functional label visual weight, angle and spacing from the original reference. Font identity is unknown; use visually matching bold sans-serif. Only minimal readability repairs are permitted; do not move labels subjectively or substantially alter layout.',
    'Change concrete scene content obviously at first glance: a silver-grey SUV in the hero scene, a rainy riverside warehouse and bridge environment, different vehicle details, wheels, surroundings, road materials and weather textures in the four cards. Keep subject category and viewpoint. These vehicles are weather-scene carriers. Preserve rain, snow, fog and dust expression and the visible lighting direction/range; do not invent brighter beams or comparative advantages.',
    'Do not copy the original scene unchanged, but do not remake the topic or composition. Both reduced-view structural similarity and side-by-side obvious scene difference are required. Do not post-brighten to rescue an inadequate result. Return one final JPEG image only, without explanation or additional variations.'
  ].join('\n')
};
