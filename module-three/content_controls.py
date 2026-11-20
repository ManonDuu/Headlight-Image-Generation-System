"""Content hierarchy for a single image, shared across image providers."""

def content_controls(point_id, title_case):
    controls = {
        'priority':'这些内容控制优先于展示库中的候选主题和方法；候选不等于必须全画',
        'deduplication':'去重只合并同义文字、重复图标和无新增解释的画面，不删除不同环境、不同观察角度或独立的小卖点。场景上的短标签是必要识别，不算重复。不要把内容丰富误判为冗余',
        'hierarchy':'优先保留完整的小卖点覆盖、有效场景和多角度表达，再改善主次；不能为了稀疏简洁而缩减信息。一个核心主题可以容纳多个场景分区',
        'copyBudget':{'headlineWords':9,'subtitleWords':12,'targetTotalWords':65,
                      'policy':'作为精简目标，不为字数丢失必要型号或适配条件；优先删除重复句和装饰性标签'},
        'textRoles':{
            'headline':'ALL CAPS' if title_case=='upper-title' else 'Every Word Initial Uppercase',
            'subtitleAndExplanations':'Every Word Initial Uppercase' if title_case=='upper-title' else 'Sentence case: capitalize only the first word, proper nouns and abbreviations',
            'shortLabels':'Every Word Initial Uppercase' if title_case=='upper-title' else 'Sentence case',
            'noTrailingPeriod':True,
            'exampleSubtitle':'Light For The Road Ahead' if title_case=='upper-title' else 'Light for the road ahead'},
        'layoutMetrics':{'unit':'fraction-of-canvas','outerMargin':0.04,'headlineMaxHeight':0.10,'headlineToSubtitleGapMinHeight':0.035,'subtitleToVisualGapMinHeight':0.025,'productMaxAreaWhenSupporting':0.18,'policy':'主标题不能霸占画面；主副标题的可见字形边缘之间留足间隔，不把副标题贴在标题基线上。必要时缩短标题或换行，不挤压间距'},
        'preservationPolicy':'修正时保留独立场景、小卖点覆盖、产品外形、主次与大小写等已确认优点；去重不等于减成单场景',
        'preflight':'生成前核对：每区是否有独立解释作用、是否重复同一利益、是否正确区分主标题与副标题大小写。不要把核对清单渲染到图中'
    }
    # Composition and printable copy have one authority: the selected layout and
    # semantic_labels. Do not retain old per-image layouts or competing copy here.
    if point_id=='beam':
        controls.update(
            contentGroups=[
                {'topics':['光线集中与分布','照明连续性与均匀度','暗区与阴影'],
                 'visualHome':'选定光场主画面内解释；不要再加第二幅相似道路全景'},
                {'topics':['近光边界及会车关系'], 'visualHome':'仅在光学条件明确时采用，当前通用方式不强制加入'},
                {'topics':['光源位置或调节关系'], 'visualHome':'仅在真实结构明确时采用，不编造调节机构'}],
            prohibitedDefaultVisuals=['未知近远光时的墙面截止线','近光实测证明','未知光型调节机构'],
            claimBoundary='没有确定近远光或光学结构时，不编造截止线、调节机构、绝对无眩光或零暗区，不写比较距离；用光分布场景表达主题')
    if point_id=='protection':
        controls.update(
            contentGroups=[
                {'topics':['雨天环境','水防护主题'], 'visualHome':'天气方式中的雨区或雨符号；微距方式中的水滴表面'},
                {'topics':['雪天使用情境'], 'visualHome':'天气方式中的雪区或雪符号；不强加到水尘微距'},
                {'topics':['雾天使用情境'], 'visualHome':'天气方式中的雾区或雾符号；不声称穿雾'},
                {'topics':['尘土环境','尘防护主题'], 'visualHome':'天气方式中的尘区或尘符号；微距方式中的尘土表面'},
                {'topics':['IP 防护等级与产品关系'], 'visualHome':'使用解析后的等级；由实际选定构图安排位置'}],
            sceneCoverage={'required':['Rain','Snow','Fog','Dust'],'representation':'icons-or-scenes','minimumDistinctScenes':0,'minimumDistinctTopics':4,
                           'appliesTo':['weather-hero','weather-mosaic'],'reason':'天气方式完整覆盖四项；protection-detail 独立表现水尘材质，不混入四天气'},
            conditionalTopics={'温度条件':'工作温度数字与耐温结论不默认添加'},
            prohibitedDefaultClaims=['Low temperature','High temperature','Cold-resistant','Heat-resistant','Extreme weather proof','All-weather performance','Clear vision in any weather'],
            prohibitedDefaultVisuals=['冰冻灯泡作为耐冻证明','温度计或温度数值','裸灯泡浸水工作画面冒充实际使用'],
            claimBoundary='天气方式保留四种使用情境；微距方式保留水尘证据。解析的 IP 等级只说明灯泡水尘防护，不推出耐温、浸水时长或雨雾能见度改善')
    controls['copyBudget']['policy']+='；每张必须有主副标题，标签或短句按解释需要添加'
    return controls
