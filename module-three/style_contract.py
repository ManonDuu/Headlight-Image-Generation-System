"""One user-owned accent, explicit typography and catalog-confirmed default facts."""
import re

REVISION='E31-all-category-trace-audit-20261026'

def theme(color):
    if not isinstance(color,str) or not re.fullmatch(r'#[0-9a-fA-F]{6}',color):raise ValueError('请选择有效主导色')
    c=color.lower();rgb=[int(c[i:i+2],16) for i in (1,3,5)]
    headline_start=c  # Saturated user hue, never a black-mixed shade
    tint='#'+''.join(f'{round(v+(255-v)*.08):02x}' for v in rgb)
    def lum(h):
        values=[int(h[i:i+2],16)/255 for i in (1,3,5)]
        values=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in values]
        return sum(a*b for a,b in zip(values,[.2126,.7152,.0722]))
    levels=[lum(c),lum(tint)]
    white=min(1.05/(v+.05) for v in levels); dark=min((v+.05)/.05 for v in levels)
    label_ink='#ffffff' if white>=3 or white>=dark else '#000000'
    return {'labelText':label_ink,'name':'自选主题色','accent':c,'highlight':tint,'headlineStart':headline_start,
            'policy':'主导色是唯一品牌强调色基准；同色相明暗或透明度过渡，背景按场景自然配色，不套预设深灰底。图形文字只用主色及其明暗变化，不用互补色替换；自然环境可有丰富颜色',
            'backgroundPolicy':'full-bleed natural scene or material surface; no fixed background swatch; scene/material reaches every edge, no white or near-white perimeter, white fade, poster mat or framing band',
            'textPolicy':'entire headline uses accent-to-highlight gradient; supporting copy uses legible white or charcoal; key labels use accent-filled surfaces, not an all-neutral text system'}

TYPOGRAPHY={'family':'Inter','headline':{'family':'Inter','weight':900,'width':'normal, never condensed','maxLines':2,'glyphHeight':0.065,'visualStyle':'heavy solid strokes, flat print; no thin gradient lettering or drop shadow'},
 'subtitle':{'colorPolicy':'One uniform neutral ink for the entire subtitle, opaque near-white on dark backgrounds or deep charcoal on light backgrounds, never faint mid-gray, across every word and line; never switch black/white mid-sentence. Resolve background contrast with placement or a subtle local scrim, not word-by-word recoloring.','family':'Inter','weight':700,'width':'normal','maxLines':2,'lineHeight':1.2,'glyphHeight':0.032},
 'labels':{'family':'Inter','weight':700,'maxLines':2,'minCanvasHeight':0.032},
 'spacing':'文字安全边距 4%，只约束文字位置；主副标题间距至少画布高度 3.5%；背景与场景满幅出血，不留外框',
 'overflow':'按最终文案换行或调整局部布局，禁止擅自改词、压窄字体或缩成不可读小字',
 'hierarchy':'主标题可见字高约副标题两倍；增强字重而非扩大空白标题区。单行主标题的文字区目标约 18%；两行主标题与副标题必须按实际字高排开，不强塞进 18%。优先使用安静场景上的叠放或侧置，禁止挤压主要证据或改成巨大空白顶栏',
 'delivery':'字体是生图视觉规范，不代表已嵌入字体文件或能保证像素级一致'}

def resolved_rating(facts):
    match=re.search(r'\bIP\s*([0-6X][0-9X](?:K)?)\b',facts,re.I)
    if match and match[1].upper()!='XX':return {'value':'IP'+match[1].upper(),'source':'user-input'}
    return {'value':'IP68','source':'user-confirmed-catalog-default'}


def color_direction(category, palette):
    """Assign graphic color roles separately from photographic exposure."""
    scene = {
      'electronics': 'Bright polished technical-commercial imagery with clear material highlights and the chosen theme color. Functional warning/normal-state details and readable result graphics are the focus, not a whole cockpit. No mandatory day or night background. If a real light-output inset is used, show headlights ON at night. Keep rich color and readable midtones; circuit decoration stays subordinate and never impersonates the actual product internals.',
      'protection': 'Keep rain atmospheric but preserve blue-gray water reflections, natural green surroundings and warm earth; snow stays clean with detail, dust retains warm ochre. Use only environments in the selected composition, not additional panels.',
          'fitment': 'Bright natural daylight vehicle scene with rich sky, foliage and material colors; retain authentic vehicle shape. No night grading.',
      'coverage': 'Bright daylight vehicle details with clear lamp positions and rich natural colors. No invented light output for unlisted positions.',
      'lifespan': 'Coherent richly colored commercial product scene, warm/cool material contrast and a subordinate time motif. Keep scale consistent; no engine-bay collage or oversized installed bulb. No invented aging timeline.',
      'thermal': 'Bright commercial product photography with clean metallic highlights and rich natural material colors. Do not add outdoor scenery just for color.',
      'size': 'Clearly colored commercial material surface with readable midtones, crisp product edges and natural metal highlights. No white or near-white studio sweep, pale-gray perimeter, unnecessary landscape or gloomy grade.',
      'installation': 'Well-lit realistic workspace with visible hands and components only when supported. Warm and cool material contrast, no gloomy garage.',
    }.get(category, 'Use vivid natural green foliage, rich deep-blue evening sky and warm earth where present, with clean highlights and readable midtones. Avoid gray-brown desaturation, muddy shadows and a global black veil. Night lighting remains night; color enhancement must not tint the white LED beam or change the matched ambient exposure of comparison scenes.')
    return {
      'accent': palette['accent'], 'highlight': palette['highlight'], 'labelText':palette['labelText'],
      'headlineStart': palette['headlineStart'],
      'headline': 'Apply the selected saturated accent-to-highlight gradient to EVERY word of the headline, including all lines. Do not replace the chosen hue with neutral black, charcoal, gray or white words. Respect an explicitly selected neutral accent; never add a black-to-color gradient or black tint. Do not add or repeat text.',
      'labels': 'Use accent-to-highlight filled or translucent gradient surfaces for the primary existing label group, with the supplied labelText color and bold Inter 700 text, visible glyph height at least 3.2 percent of the canvas height (about 65 px at 2048 px). Wrap the supplied labels instead of shrinking them or inventing new copy. Comparison-baseline identifiers MUST use a neutral treatment; our identity and primary benefits use the theme. Secondary labels may stay neutral. Do not reduce theme color to thin lines or tiny dots.',
      'gradient': 'Headline gradient starts at accent and ends at highlight; label fills use accent to highlight. Keep the first 60 percent of the title close to the saturated selected accent; never fade to pastel, cyan or white. These role-specific endpoints are authoritative. Keep the chosen hue. Use at least one readable same-hue gradient in headline or labels. Text glyphs stay opaque; opacity fades belong behind text. No metallic bevels or neon glow.',
      'scene': scene,
      'balance': 'Theme color must be recognizable in the title and any existing supporting graphics at thumbnail size. An annotation zone is optional; never create one just for color. Natural scene colors remain independent; do not make the whole image monochrome blue. Retain vivid natural/material midtones and local warm-cool richness; avoid large milky gray backgrounds and desaturated white title cards. No fixed color-area quota, outer border, empty header or extra cards.',
      'setConsistency': 'Use one primary label family across the set; secondary annotations use the same font without adding another card. Consistency does not require identical label counts or positions: single-piece softly rounded rectangular gradient tabs, consistent padding and corners, bold normal-width text centered INSIDE the colored surface with visible inset padding. Each label is ONE surface, not an empty colored cap plus a black text box below. No detached captions, layered shadows or blank color strips. Thin plain leaders only when they terminate on relevant evidence. No per-image switching to italic type, beveled pills or glowing badges. Preserve the selected composition; label positions follow evidenceMap ownership, never a decorative ordering.'
    }


def editorial_hierarchy(category):
    """Art-direction decisions: visual evidence first, stable style, varied composition."""
    evidence={
      'illumination':'The illuminated LED road, distant landmarks and verge remain unobscured. Comparator is secondary; compute dominance AFTER placing text, not before.',
      'beam':'Keep the continuous light field, near-to-far transition and soft perimeter visible. Do not lay a row of tabs across the lit pavement.',
      'tone':'Preserve illuminated neutral materials so actual light color is readable; graphic gradients never tint the comparison surfaces.',
      'electronics':'Make warning-control and normal-operation outcomes instantly readable. Decorative circuits, product render or background never overpower the benefit explanations.',
      'protection':'Preserve the selected weather regions or material details. Rating supports the evidence; never substitute a huge IP badge for the scene.',
      'installation':'Keep the installation overview stages distinct: removal, fitting and lights-on verification. Preserve action-to-result reading order. Unknown sockets use conceptual symbols, never invented physical interfaces; keep the actual reference bulb proportional.',
      'size':'Keep product silhouette and required clearance or dimension endpoints unobscured.',
      'thermal':'Keep actual visible cooling surfaces and their relationships visible, without unrelated technical ornaments.',
      'fitment':'Vehicle identity and exact fitment scope remain readable. Long fitment text belongs in a structured information region, not a gigantic subtitle.',
      'coverage':'Keep lamp positions and their exact supplied mappings legible, without crossing leaders.',
      'lifespan':'Keep the selected use/structure story clear; no oversized unsupported number or decorative timeline.',
    }
    return {
      'readingOrder':'One clear benefit headline, the main visual evidence, then brief supporting explanations. Both headline and scene are strong; neither should erase the other.',
      'protectedEvidence':evidence.get(category,'Preserve the chosen selling-point evidence.'),
      'typeHierarchy':'Headline is heavy and about twice the subtitle glyph height; subtitle is subordinate but readable. Align their left edges or share one deliberate centered axis. No alternating alignment within the same text group.',
      'placement':'Choose a quiet corner or side area in the selected composition. Do not turn every image into a fixed top banner. Keep the title away from the vanishing point, product detail or action. Preserve selected region counts and method.',
      'annotations':'Group labels with their actual evidence. Keep one primary tab style; secondary annotations can be flat text with a short leader. Never add extra labels to fill space. No crossing leader lines, disconnected color strips or floating shadows.',
      'contrast':'Resolve text contrast locally: choose neutral light/dark supporting text and a subtle local scrim. Do not darken or desaturate the whole scene. The title hue must still match the selected theme.',
      'restraint':'Maintain rich scene color and one graphic theme. Use gradients only for hierarchy, not on every object. No decorative ribbons, thick panel borders, giant badges or empty color fields.',
      'conflictResolution':'Protect evidence and readable copy before decorative symmetry. If text does not fit, wrap it or move its group into a quiet area; do not shrink letters, stretch the font, cover the hero, remove independent subpoints or invent new wording.',
    }


def resolved_light_color(facts, product_type):
    match=re.search(r'\b(\d{4,5})\s*K\b',facts,re.I)
    value=int(match[1]) if match else (6000 if product_type=='halogen' else 6500)
    return {'kelvin':value,'value':str(value)+'K','source':'user-input' if match else 'user-confirmed-catalog-default'}


def resolved_lifespan(facts):
    """Catalog default; explicit lifespan hours retain their bounds and qualifiers."""
    value=r'(?P<qual>up to|at least|over|more than|最高|最长|至少|超过)?\s*(?P<num>\d[\d,]*(?:\.\d+)?)\s*(?P<scale>k|万)?\s*(?P<plus>\+)?\s*(?:hours?|hrs?|小时|h\b)\s*(?P<after>\+|以上)?'
    labelled=re.search(r'(?:lifespan|rated life|service life|寿命)\s*[:：]?\s*'+value,facts,re.I)
    candidates=list(re.finditer(value,facts,re.I))
    match=labelled or (candidates[0] if len(candidates)==1 and not re.search(r'test|testing|测试|老化|baseline|对照',facts,re.I) else None)
    if not match:return {'hours':5000,'qualifier':'plus','value':'5000+ Hours','source':'user-confirmed-catalog-default'}
    number=float(match['num'].replace(',',''))
    number*=10000 if match['scale']=='万' else 1000 if (match['scale'] or '').lower()=='k' else 1
    number=int(number) if number.is_integer() else number
    qualifier=(match['qual'] or '').lower()
    prefixes={'up to':'Up To ','最高':'Up To ','最长':'Up To ','at least':'At Least ','至少':'At Least ','over':'Over ','more than':'Over ','超过':'Over '}
    plus=bool(match['plus'] or match['after'])
    text=match['num'] if not match['scale'] else str(number)
    return {'hours':number,'qualifier':qualifier or ('plus' if plus else 'specified'),'value':prefixes.get(qualifier,'')+text+('+' if plus else '')+' Hours','source':'user-input'}
