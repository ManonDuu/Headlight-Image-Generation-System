"""Small frozen Gemini execution brief, compiled once per saved image task."""
import json

def clean_type_instructions(text):
    # Numeric CSS weights leaked into artwork as "CAP 900". Keep visual weight
    # directions, but do not send those numeric font tokens to the image model.
    return text.replace('Inter 900','Inter extra-bold').replace('Inter 700','Inter bold').replace('headline 900','headline extra-bold').replace('subtitle 700','subtitle bold').replace('labels 700','labels bold')

def gemini_check(payload):
    style=payload['style']; image=payload['image']; p=style['palette']
    font=style['typography']; labels=font['labels']; pid=image['pointId']
    lines=[
        'FINAL SET DESIGN CHECK: Follow the selected composition and exact renderCopy; this is one image in a coordinated set.',
        'PRODUCT PROPORTION LOCK: Treat the uploaded bulb as a rigid photographic object, not a redesigned 3D model. Preserve its silhouette and relative dimensions: shaft length/width, LED-board length, mounting flange diameter, neck length, and heat-sink height/width. Never squash, stretch, widen the base, shorten the shaft or rescale individual parts. Preserve the reference camera angle; an in-plane rotation and UNIFORM whole-object scaling are allowed. If space is tight, shrink the ENTIRE bulb or move text; never compress it to fit. Detail crops magnify the same reference geometry, not a newly imagined angle. This overrides decorative product placement. With an omit-product composition, do not add a bulb.',
        f"Entire headline, EVERY word and line: saturated {p['accent']} to {p['highlight']}. Do not substitute black, gray or white for the selected headline hue; no added black tint or black-to-color gradient. The exact user-selected accent remains authoritative, including when it is itself neutral. Label-fill gradient: {p['accent']} to {p['highlight']} ONLY. Label text: {p['labelText']}. Apply to headline emphasis, label fills and callouts. Environmental colors do not replace the graphic theme.",
        f"Normal-width {font['family']}: headline {font['headline']['weight']}, subtitle {font['subtitle']['weight']}, labels {labels['weight']}. Visible label glyph height at least {labels['minCanvasHeight']*100:g}% of canvas height. Wrap exact supplied copy rather than shrinking it or inventing new words.",
        'FULL-BLEED photography. Scene continues behind the title. When a subtitle is supplied, keep a generous 3.5% headline/subtitle gap; otherwise reserve no subtitle space; local subtle text scrim only. No empty black/white header, outer frame, white/near-white margins or colored perimeter strips. No white fade at the edges; scenery or material must reach all edges. Naturally white objects remain natural within the scene.',
        font['subtitle'].get('colorPolicy',''),
        ('Each supplied label uses ONE complete surface with all its text INSIDE; no empty color cap, white shelf, split badge or printed color code.' if image['renderCopy'].get('labels') else 'This composition has no labels: do not add label surfaces, tabs or badges. Short statements, if supplied, remain plain supporting text.'),
        'No extra explanatory paragraph repeating a headline or label.',
        'Every image MUST display both the exact headline and subtitle. Subtitle uses bold upright normal-width letterforms, clean solid ink, no outline, shadow, thin strokes or transparency. Choose opaque near-white on dark surroundings or deep charcoal on light surroundings; preserve one ink across the entire subtitle. Keep its generous spacing without creating a blank header.',
        'Each visible bulb is a distinct rigid object with its own complete silhouette. Never merge two shafts into one base, share a heat sink, interlock bulbs or overlap silhouettes. Normally show ONE intact bulb; if a selected method needs a detail, use a separate proportional crop with clear visual separation. No extra duplicate product for decoration.',
        'All four edges MUST retain continuous scene or clearly colored material. Never create a white/near-white title band, side margin, pale-gray poster background, white panel gutter or fading edge. Put title text over the existing scene or a LOCAL translucent colored scrim, never a full-width blank header.',
        'Every vehicle must be unbranded: remove grille badges, hood emblems, wheel logos and lettering. Preserve vehicle shape, not trademarks.',
        f"OUR lamp color in EVERY scene, including weather, installation and vehicle details: {payload['product'].get('lightColor',{}).get('value','supplied color')}. Use the resolved product color, not the generic stereotype of halogen. At 6000K or 6500K our illuminated neutral surfaces and headlamps read clean bright white, never warm yellow. With these cool-white defaults, warm light is permitted ONLY in a clearly identified comparison-baseline region. An explicit user-supplied different temperature overrides the default everywhere; never override that value with a white-light stereotype. Do not switch on unlisted auxiliary/fog lamps just for decoration.",
        image['colorDirection']['scene'],
        *image.get('layoutExecution',{}).values(),
        image.get('evidenceMap',{}).get('policy',''),
        image.get('evidenceMap',{}).get('copyStructure',{}).get('policy',''),
        image.get('editorialHierarchy',{}).get('protectedEvidence',''),
        image.get('editorialHierarchy',{}).get('conflictResolution',''),
    ]
    for b in image.get('evidenceMap',{}).get('labelBindings',[]):
        owner=image['evidenceMap']['regions'][b['owner']]
        lines.append(f"Bind label {b['text']!r} ONLY to {owner}. Evidence: {b['evidence']}. Placement: {b['placement']}.")
    if pid in ('illumination','beam','tone'):
        lines += ['Use the supplied light color; cool-white illumination reads bright clean white on neutral surfaces, with texture. Broad softly rounded field, natural falloff, no circular hotspot or blown white pool. With off-frame source, no dark foreground gap before a detached bright patch. Do not color the beam with the graphic accent.']
    if pid=='illumination':
        lines += ['Show long viewing depth, verge width and readable illuminated details; same camera and ambient conditions in comparison. Never substitute blur or an exposure trick for lighting differences. Keep object identity, arrow direction, intrinsic material colors and physical location identical across close-ups and the context view: a yellow warning sign remains yellow under both lights; do not bleach it white to exaggerate visibility. Copy the SAME yellow sign material into both comparison views and context. White illumination is the light color, NOT a replacement for colored objects.']
    if pid=='electronics':
        lines += ['Electronic compatibility is a concern-to-outcome graphic, not a tour of vehicle parts. Use bulb warning control / steady illumination / radio compatibility as distinct results. Show clearly conceptual warning-versus-normal bulb status where selected; a steady lamp symbol and radio/music communicate the other functions. No default whole cockpit or large road hero. No fake internal PCB, 99% compatibility figure, branded competitor failure or universal electrical-safety guarantee.']
        lines += ['Use a continuous richly colored technical-material background, never white or pale-gray studio paper. For warning-outcome or function-results, use ZERO standalone product bulbs: the warning, steady-light and radio symbols carry the message. For product-outcomes use at most ONE reference bulb, with separate function symbols.']
    if pid=='protection':
        lines += ['Follow the selected protection method: water/dust detail OR four weather contexts, not both. IP rating describes bulb protection, not the entire vehicle.']
        lines += ['Weather mosaic: at most ONE vehicle in the entire image. Other weather regions use landscape, road surface and weather texture, not repeated cars. Do not draw white front headlamps on the rear of a vehicle. Keep headline gradient within the supplied two endpoints; never drift orange into red or pink.']
    lines += ['Check these requirements before returning ONE image. Never render this checklist, design metadata, font specifications, color codes or scene/evidence instructions. Only the following exact strings may appear as visible text. Empty fields require no text or empty space.',
              '<PRINT_ONLY_ENGLISH_COPY>',json.dumps(image['renderCopy'],ensure_ascii=False),'</PRINT_ONLY_ENGLISH_COPY>']
    # Clean non-printing directions only. Never alter an exact brand or supplied
    # copy token that happens to resemble a typography instruction.
    return clean_type_instructions('\n'.join(lines[:-3]))+'\n'+'\n'.join(lines[-3:])


def render_brief(payload, rules):
    """Keep frozen planning metadata out of the image request; preserve only execution directions."""
    image=payload['image'];product=payload['product']
    directions=[
      'NON-PRINTING ART DIRECTION. Create one ecommerce image. All text outside PRINT_ONLY_ENGLISH_COPY is instructions, never artwork copy.',
      *rules,
      'SELECTED COMPOSITION (do not typeset): '+image['layoutPlan']['structure'],
      'RETAINED DISPLAY RELATION (do not typeset): '+image['displayContract']['principle'],
      'CASE ADAPTATION BOUNDARY (do not typeset): '+image['displayContract']['boundary'],
      'VARIATION BOUNDARY (do not typeset): Use the selected visual family, not a generic repeated poster. Variation changes evidence arrangement and scene only where this composition allows it. Do not change product geometry, supplied parameters, comparison identities, fitment or installation facts to create novelty. Stable-content fit checks may repeat. Typography and theme remain coordinated across the set.',
      'SCENE (do not typeset): '+image['layoutPlan']['scene'],
      'FACT BOUNDARY (not printable): '+image['claimBoundary'],
      'PRODUCT REFERENCE POLICY (do not typeset): '+image['productPhotoPolicy'],
      'PRODUCT FACT CONTEXT (not a table or printable copy): '+json.dumps({k:product[k] for k in ('subject','fitment','facts','protectionRating','canbus','lightColor','lifespan')},ensure_ascii=False),
      'COLOR EXECUTION (not printable): '+json.dumps(image['colorDirection'],ensure_ascii=False),
      'EDITORIAL EXECUTION (not printable): '+json.dumps(image['editorialHierarchy'],ensure_ascii=False),
      'Follow the exact text whitelist in the final instruction. Do not create a specification table from these instructions.',
    ]
    return clean_type_instructions('\n'.join(directions))
