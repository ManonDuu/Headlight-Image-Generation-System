"""Compile printable labels and evidence ownership together, never by list order."""
import re
from copy import deepcopy

POLICY = ('Copy must answer the buying concern with a concrete benefit, without fear or invented promises. '
          'Every image requires a headline AND a concise subtitle. Headline: one core benefit or buying decision. Subtitle: one supporting explanation, usually 6-10 words. Labels and short statements are optional; statements may replace labels, never the subtitle. Do not duplicate their meaning. '
          'Benefit labels target 2-3 words and must not exceed 4; prefer comparable lengths when three share an area. '
          'Identity, supplied model/configuration and necessary fitment qualifiers may be longer. Never truncate these facts. '
          'Keep labels readable; rephrase at planning time, wrap or reposition at rendering time, never shrink the font. '
          'Exact renderCopy is already approved by the planner: do not rewrite it in the image model. '
          'Every label has a semantic owner in labelBindings. Place identifiers INSIDE their own region, '
          'never on a panel divider or shared footer. Benefit labels belong beside their visible evidence; '
          'draw a short leader only to the specified evidence, never to the nearest decorative object. '
          'List order does NOT mean top-to-bottom placement. Plan evidence first, then position its label. '
          'If cramped, move the label within its owner region or wrap it; never swap owners, invent a detail '
          'or add extra text. Negative/problem states must not look like our product outcome.')

def compile_labels(product, style, brief, fallback):
    pid=brief['pointId']; variant=brief['layoutPlan']['id']; copy=deepcopy(fallback)
    if pid=='fitment' and not copy.get('subtitle'):copy['subtitle']='Confirm your vehicle model and year before ordering'
    bindings=[]; regions={}
    def add(text, owner, evidence, role='benefit', placement='Beside the evidence within its owner region; keep the evidence unobscured'):
        bindings.append(dict(text=text,owner=owner,evidence=evidence,role=role,placement=placement))
    ours=product.get('brand') or ('LED' if product['subject']=='led' else 'Our Bulb')
    other='Halogen' if product['subject']=='led' else 'Comparison Bulb'
    if pid=='illumination':
        regions={
          'road-states':{'ours':'UPPER larger bright road panel','baseline':'LOWER smaller dim road panel'},
          'hero-baseline':{'ours':'Large main bright road scene OUTSIDE inset','baseline':'Upper-left small dim comparison inset'},
          'target-detail':{'ours':'UPPER RIGHT brighter target close-up','baseline':'UPPER LEFT dimmer view of identical target','context':'LOWER wide road scene under OUR lighting'},
        }[variant]
        add(ours,'ours','Our brighter illumination, never the dim comparator','identity','Inside upper-left corner of OUR region; never at the shared bottom edge')
        add(other,'baseline','Comparison lighting ONLY','identity','Inside upper-left corner of BASELINE region; neutral tab, never our accent benefit tab')
        if variant=='hero-baseline':
            bindings[0]['placement']='Inside the RIGHT side of the bright main road scene, beside its illuminated verge; NEVER above, below, beside or aligned with the upper-left comparison inset. Separate the brand from that inset by at least one label-width.'
        benefits={
          'road-states':[('See Farther','ours','Lit distant bend, reflectors and markings'),('Clearer Road Edges','ours','Illuminated verge beside the road')],
          'hero-baseline':[('Spot Roadside Obstacles','ours','The low branch at the outer right verge'),('See Farther','ours','Illuminated distant road beyond the near foreground')],
          'target-detail':[('Clearer Distant Details','ours','The sign and reflector in the brighter close-up'),('See Markings Ahead','context','Distant markings in the lower road context')],
        }[variant]
        for text,owner,evidence in benefits:add(text,owner,evidence)
        copy['headline']={'road-states':'See Farther, See More Clearly','hero-baseline':'Bring Roadside Obstacles Into View','target-detail':'See Distant Details Clearly'}[variant]
        copy['subtitle']='Brighter road detail from the lane to its edges'
    elif pid=='beam':
        regions={'field':'ONE continuous illuminated ground surface; nearby ground is at the bottom, distant road toward the vanishing point'}
        benefits={
          'near-far':[('Even Nearby Illumination','Near illuminated pavement at BOTTOM, not trees or sky'),('Continuous Coverage','Connected illumination from near to middle ground, not an isolated spot'),('Smooth Light Distribution','Broad field with gradual falloff toward the distant road; never a nearest gravel patch called distance')],
          'overhead-field':[('Wide Road Coverage','Illuminated lane and its lateral verges'),('Continuous Coverage','Connected light field forward from the vehicle'),('Smooth Beam Edges','Soft lateral perimeter of the same field')],
          'lateral-surface':[('Wide Road Coverage','Broad illuminated pavement across the scene'),('Smooth Beam Edges','Transition from illuminated pavement into the outer edge'),('Clear Road Detail','Visible texture INSIDE the illuminated pavement')],
        }[variant]
        for text,evidence in benefits:add(text,'field',evidence)
        copy['headline']={'near-far':'Even Light Across The Road','overhead-field':'A Wider Field Of Light','lateral-surface':'Light Beyond The Center'}[variant]
        copy['subtitle']='A connected light field with smooth, gradual transitions'
    elif pid=='tone':
        match=re.search(r'\b(\d{4,5})\s*K\b',product['facts'],re.I)
        kelvin=product.get('lightColor',{}).get('kelvin') or (int(match[1]) if match else None)
        desc=('Cool White' if 5000<=kelvin<=7000 else 'Warm White' if kelvin<4000 else 'White' if kelvin<5000 else 'Blue-White') if kelvin else 'Light Color'
        named=(str(kelvin)+'K '+desc) if kelvin else 'Your Light Color'
        copy['headline']=named
        copy['subtitle']='See the difference on pavement and road markings' if variant=='surface-color' else 'See the light color where it meets the road'
        if variant=='surface-color':
            regions={'baseline':'LEFT warm comparison on matched surfaces','ours':'RIGHT brighter supplied product light on the same surfaces'}
            add(other+' — Warm Light','baseline','Warm comparison pavement and stripe','identity')
            add(ours+' — '+named,'ours','Our supplied light color on pavement and stripe','identity')
        elif variant=='lamp-appearance':
            regions={'lamp':'Main real headlamp detail','surface':'Inset of paving stone illuminated by THAT same lamp'}
            add('White Road Illumination' if kelvin and 4000<=kelvin<=7000 else 'Road Light Color','surface','Pale paving stone illuminated in the inset')
        else:
            regions={'materials':'One illuminated roadside scene, no comparator'}
            add('See Roadside Detail','materials','Visible wood grain on fence')
            add('Clear Surface Detail','materials','Visible illuminated gravel texture')
    elif pid=='coverage':
        # Configuration is source data, never printable prose. Only recognized model/count tokens.
        entries=[]
        for m in re.finditer(r'(?<![A-Za-z0-9])((?:900[3-8]|90(?:10|11|12)|H(?:1[0-6]|[1-9])|D[1-8][SR]|880|881|HB[1-5]))(?:\s*[*×xX]\s*(\d{1,2}))?(?![A-Za-z0-9])',product['configuration'],re.I):
            entry=m[1].upper()+((' × '+m[2]) if m[2] else '')
            if entry not in entries:entries.append(entry)
        k=re.search(r'\b(\d{4,5})\s*K\b',product['facts'],re.I)
        spec=entries+([product['lightColor']['value']] if product.get('lightColor') else [k[1]+'K'] if k else [])+(['LED'] if product['subject']=='led' else ['Halogen'])
        copy.update(headline='Your Lighting Setup',subtitle=' · '.join(spec),labels=[])
        regions={'location':'Whole external headlamp assembly on the vehicle, NOT an inferred internal high/low beam chamber'}
        add('Headlamp Location','location','The complete external headlamp housing; model/count/color facts belong in subtitle, not at a guessed internal bulb location','context')
    elif pid=='lifespan':
        life=product.get('lifespan',{})
        titles={'life-structure':'Built For Lasting Use','decay-compare':'More Time On The Road','long-use':'Made For Everyday Miles'}
        subtitles={'life-structure':'Cooling surfaces support long-term lighting use','decay-compare':'A lighting upgrade designed for long-term use','long-use':'Durable design for everyday lighting use'}
        copy.update(headline=titles[variant],subtitle=subtitles[variant],labels=[])
        if product['subject']=='halogen' and variant=='life-structure':copy['subtitle']='Durable construction for long-term lighting use'
        regions={'design':'Intact reference product on a coherent studio surface with a visible material/cooling detail; no giant bulb inside an engine bay','time':'Unnumbered clock arc or simple continued-use symbol behind product, not a measured timeline or bulb equivalence'}
        if life and variant=='life-structure':
            copy['headline']=life['value']+' Lifespan'
            copy['subtitle']='Designed for long-term lighting performance'
        ratio=re.search(r'(?:lifespan|寿命)\s*[:：]?\s*(\d+(?:\.\d+)?)\s*[x×倍]\s*(?:vs\.?|compared with|对比)?\s*(?:halogen|卤素)',product['facts'],re.I)
        if ratio and variant=='decay-compare':
            copy['headline']=ratio[1]+'× Rated Lifespan'
            copy['subtitle']='Compared with the stated halogen baseline'
            regions['time']='Explicitly supplied lifespan ratio shown as a simple proportional comparison, not a fabricated pile of bulbs or invented baseline hours'
        add('Heat Management' if product['subject']=='led' else 'Durable Construction','design','Visible external cooling surface for LED, actual intact material detail for halogen')
        add(life['value'] if life and variant!='life-structure' else 'Long-Term Use','time','Time motif supporting the resolved lifespan value, including its explicit qualifier; no invented years or bulb-equivalence ratio')
    elif pid=='size':
        titles={'dimension-views':'See The Space You Need','same-base':'Match The Mounting Position','space-detail':'Room Behind The Bulb'}
        copy.update(headline=titles[variant],subtitle='Base alignment and rear clearance in one view',labels=[])
        regions={'base':'Mounting flange plane at the actual base tabs, NOT cooling fins','rear':'Spatial envelope BEHIND the mounting flange, extending to the rear housing or connector; not just a dot on a fin'}
        add('Base Alignment','base','A shared mounting-plane guide at actual visible tabs, no invented OEM counterpart')
        add('Rear Space Needed','rear','Bracket spanning mounting plane to rear end plus a translucent abstract clearance envelope; explicitly not a real headlamp cutaway or fit guarantee')
    else:
        # Existing approved scene methods remain intact. Bind each supporting label to a named subject/result.
        anchors={
          'electronics':['Normal bulb-monitoring result: a clear lamp/check symbol. If a red warning is shown, keep it small and visibly resolved/crossed out, NEVER the dominant successful state; no extra Bulb Out text', 'Continuously lit lamp symbol or actual intact bulb, not a sine wave or unrelated dashboard', 'Radio/audio symbol with clean music notes, no extra Playing text'],
          'thermal':['Actual visible external cooling surface; do not invent a fan or internals','Visible housing with schematic outward heat flow, never a fabricated internal heat pipe'],
          'size':['Actual photographed mounting base','Space occupied by the actual rear housing, no invented clearance dimensions'],
          'installation':['Visible base alignment feature; do not invent a socket or hand action','Visible mounting seat; no invented sequential operation'],
          'fitment':['Supplied model and year information with matching unbranded vehicle','Supplied lighting configuration; unknown trims must remain checks'],
          'coverage':['Exact supplied model/count/position mapping; never infer positions from bulb shape'],
          'lifespan':['Actual visible product details only; no invented durability test','Realistic care/use context, not an unsupported lifetime guarantee'],
          'protection':(['Water droplets on exterior material, not submerged bulb','Dust context beside exterior material, no fabricated internal seal'] if variant=='protection-detail' else ['Rain scene or rain symbol','Snow scene or snow symbol, not a temperature rating','Fog scene or fog symbol, not proof of fog penetration','Dust scene or dust symbol']),
        }.get(pid,[])
        if pid=='thermal':copy.update(headline='Designed To Release Heat',subtitle='External cooling surfaces help carry heat away',labels=['Cooling Surface','Heat Flow'])
        if pid=='installation':
            copy.update(headline='Installation Overview',subtitle="Follow your vehicle’s instructions for each step",labels=['1 Remove Old Bulb','2 Fit New Bulb','3 Check The Lights'])
            anchors=['Removal concept in the FIRST region, simple neutral bulb/removal symbol; no invented twist direction or socket', 'Fitting concept in the SECOND region using the intact reference bulb at its uploaded angle, no imagined mating connector', 'Lights-on verification in the THIRD region with an unbranded headlamp in the resolved product light color; not another static bulb crop']
        for i,text in enumerate(copy['labels']):
            owner=f'evidence-{i+1}';evidence=anchors[i] if i<len(anchors) else 'Visible subject explicitly described by this label in the selected composition'
            regions[owner]=evidence
            add(text,owner,evidence,'context' if pid in ('protection','fitment','coverage','size','installation') else 'benefit')
    # Freeze copy and visible emphasis together; do not ask Gemini to improvise synonyms.
    from variation_details import detail
    selected_detail=detail(pid,brief['layoutPlan'].get('detailIndex',0))
    if selected_detail:
        copy['headline'],copy['subtitle']=selected_detail[:2]
        if pid=='protection':copy['headline']=product['protectionRating']['value']+' '+copy['headline']
        if pid in ('illumination','beam'):
            benefits=[b for b in bindings if b['role']=='benefit']
            identities=[b for b in bindings if b['role']!='benefit']
            # Shift emphasis, retaining the paired evidence and every comparison identity.
            if brief['layoutPlan']['detailIndex']==2 and not (pid=='beam' and variant=='overhead-field'):
                benefits=benefits[1:]+benefits[:1]
            bindings=identities+benefits
    for b in bindings:
        if b['role']=='benefit' and len(b['text'].split())>4:
            raise ValueError('Benefit label exceeds four words: '+b['text'])
    mode='headline-subtitle-labels'
    statements=[]
    if (pid,variant) in {('beam','overhead-field'),('electronics','function-results')}:
        mode='headline-subtitle-statements'
        phrases=(['Light reaches across the road','Illumination stays connected ahead','Light fades smoothly at the edges'] if pid=='beam' else
                 ['Helps reduce bulb warning errors','Designed for steady illumination','Check radio compatibility after installation'])
        if pid=='electronics' and not product.get('canbus',{}).get('value',False):
            phrases=['Check bulb monitoring compatibility','Check for stable illumination','Check radio operation after installation']
        for b,phrase in zip(bindings,phrases):
            b.update(text=phrase,role='statement',placement='Readable short statement beside its evidence; no mandatory tab, pill, leader or separate label')
        statements=[b['text'] for b in bindings]
    # Remove explanatory text only when the title/subtitle already supplies its meaning.
    # Retain scene regions: fewer words must not remove visual evidence.
    redundant_context = pid=='fitment' and bool(product.get('fitment'))
    self_explanatory_detail = pid=='protection' and variant=='protection-detail'
    omitted=[]
    if redundant_context or self_explanatory_detail:
        omitted=[dict(b,reason='Already explained by the headline/subtitle; retain its visual evidence') for b in bindings]
        bindings=[]
        mode='headline-subtitle'
    copy['labels']=[] if statements else [b['text'] for b in bindings]
    if statements:copy['shortStatements']=statements
    if not copy['subtitle'] and copy['labels']:mode='headline-labels'
    copy_structure={'mode':mode,
      'decision':{'identityNeeded':any(b['role']=='identity' for b in bindings),'localEvidenceNeedsNaming':any(b['role']=='benefit' for b in bindings),'independentStatements':len(statements),'redundantSupportingCopyRemoved':len(omitted)},
      'omittedCopy':omitted,
      'selectionPrinciple':'Choose text roles by communication need, never by image number or a mandatory template. Keep comparison identities. Use local labels only to locate or explain evidence. Use short statements for independent outcomes. When title and subtitle already explain an obvious scene, omit redundant annotations while retaining the scene. Steps, specifications and fitment keep their necessary information; never invent missing steps to fill a layout.',
      'policy':'Headline and subtitle are both required. Keep the subtitle concise, legible and separate from the headline. Short statements replace labels, never the subtitle; do not repeat them as badges. Keep set fonts, theme and clear hierarchy; supporting text structure may differ by evidence and composition.'}

    if style['titleCase']=='upper-title':
        copy['headline']=copy['headline'].upper()
        copy['subtitle']=' '.join(w[:1].upper()+w[1:] for w in copy['subtitle'].split()) if pid!='fitment' else copy['subtitle']
    else:copy['subtitle']=copy['subtitle'][:1].upper()+copy['subtitle'][1:]
    copy['subtitle']=copy['subtitle'].rstrip('.。')
    if style['titleCase']=='upper-title' and copy.get('shortStatements'):
        copy['shortStatements']=[' '.join(w[:1].upper()+w[1:] for w in text.split()) for text in copy['shortStatements']]
        for b,text in zip(bindings,copy['shortStatements']):b['text']=text
    assert all(b['owner'] in regions for b in bindings)
    assert len(copy['labels'])==len(set(copy['labels'])), 'Duplicate printable labels'
    for value in [copy['headline'],copy['subtitle'],*copy['labels'],*copy.get('shortStatements',[])]:
        if re.search(r'[\u3400-\u9fff]',value):
            raise ValueError('图片文案只能使用英文；请将品牌、车型或自定义卖点中的中文改为英文后重试')
    return copy,dict(policy=POLICY,regions=regions,labelBindings=bindings,copyStructure=copy_structure)
