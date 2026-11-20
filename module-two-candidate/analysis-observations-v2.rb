# Analysis request builder. Does not change historical plan bytes or dispatch.
require_relative 'fresh-analysis-flow'
module AnalysisObservationsV2
 INSTRUCTION=<<~TEXT
  OBSERVATION REVISION 2 (overrides ambiguous grouping instructions):
  ANALYSIS STAGE: shared policies describe final-image behavior. Any shared instruction to return/draw an image applies to the later image stage only; this stage returns the JSON schema exclusively. Preserve copy/factual/layout constraints; make no image, review call or retry.
  productPresent means a separately pictured physical lamp/bulb product body (the sold item), not a vehicle, hood, road, beam, scene object, product name or label. Do not infer a bulb from copy or illumination. With no visible physical lamp body, productPresent=false and productVisibleBounds is the zero rectangle.
  Observe positions against the complete ORIGINAL input raster. Do not use a mentally resized preview as source coordinates. sourceGeometry, sourceBox, textGroups, panels and pointers are ALL source pixels; text[].box and fontSize alone use OUTPUT pixels. A label below a scene remains below that full scene; do not compress scene heights. Text can contain multiple colors within one line; preserve observed color transitions in fillStops and declare fillDirection horizontal or vertical. Neutral text can be gray, not always white.
  In ai-rewrite, productParameters are available facts, not mandatory display copy. Retain source topic; omit unsubstantiated numeric claims and their dependent qualifiers rather than replacing them with unrelated facts. custom is verbatim; remove-all-copy is empty. Keep user input distinct from reference observations and model suggestions.
  Keep each visually distinct source text block separate even when colors match. A sourceStructure.textGroups item has exactly ONE blockId. Return fillStops as an empty array for solid text or ordered {at:0..1,color:#RRGGBB} stops for an observed vertical gradient. Return outline {color:#RRGGBB,width:source-pixel-width}; width=0 means no visible outline. These are source observations, not an invented decoration preset. Preserve actual source line breaks and distinguish subtitle, main heading, large feature value, explanation and panel label in evidence marketingFunction; final canonical roles remain title/subtitle/body/brand.
  For every block, give its own source-pixel region, perspective quad, italic, weight and palette/color. Slanted baselines are not horizontal rectangles; do not assign one shared quad or color to the whole text collection. Source regions locate pixels, not final rendering coordinates. Host computes line wrapping and font sizes from measured glyphs; do not shrink titles to fit arbitrary output guesses.
  REFERENCE TYPOGRAPHY: Preserve the observed relative glyph sizes of main title, subtitle and labels, with approximate proportional fitting rather than exact font cloning. Text colors and observed text gradients come from each corresponding source text role. A selected layout/decorative palette changes ONLY non-text backgrounds, frames and label fills; it MUST NOT recolor any text or invent a contrasting label text color. This overrides any shared palette instruction for reference-reconstruction.
  A percentage and its explanatory line are separate source meaning units even when one visual group contains both. Preserve both units in evidence; host handles unsupported claims conservatively without inventing substitute copy.
  productVisibleBounds covers the ENTIRE physical object, including socket, connector and lower base, not just the emitter. Exclude outer glow, cast shadow and padding. This is an approximate source observation; host corroborates with local pixels and original replacement alpha. ProductSlot is only an advisory output region and must not contradict source visible height. Do not describe local segmentation as a model result. Panels describe scene regions, including UNFRAMED comparisons. Empty panels means a single continuous scene only. Record every visible scene region, without a two-panel limit. Assign each region a unique lower-case sceneRole key (letters, digits, hyphens). labelBounds must be null when no label container exists; never invent a label or its text. For each panel observe sceneBounds excluding label strip, borderWidth (0 when no border), labelRadius, labelFillStops (horizontal gradient stops), and labelPointer (empty or three source-pixel points). Do not invent frames; a bottom full-width strip stays at the bottom. All bounds describe actual source pixels.
  Return sourceStructure.decorations for necessary non-text layout illustrations and pictograms (for example weather symbols), using simple rounded-rect, ellipse, polygon or path primitives in source pixels; approximate the recognizable shape, not exact tracing. Empty array explicitly means none. Do not include scene objects, letters, logos, unsupported numeric/claim graphics, or panel borders/label fills already described in panels. Fill unused points/commands with empty arrays; bounds encloses each primitive. Keep every eligible illustration distinct from scene content so the local renderer can retain it.
  Do not invent source text, facts, viewpoint, skew or style when uncertain. Record available observations faithfully rather than a visually convenient grouping. No final-image drawing is requested.
 TEXT
 def self.strip_descriptions(value)
  case value
  when Hash;value.delete('description');value.each_value{|v|strip_descriptions(v)}
  when Array;value.each{|v|strip_descriptions(v)}
  end
 end
 def self.check_lengths!(body)
  prompt=body.fetch('contents')[0].fetch('parts')[0].fetch('text')
  schema_bytes=JSON.generate(body.dig('generationConfig','responseFormat','text','schema')).bytesize
  raise ArgumentError,'Analysis prompt too long after observation instructions; no request sent' if prompt.bytesize>24000
  raise ArgumentError,'Analysis schema too long; no request sent' if schema_bytes>18000
 end
 def self.prepare(frozen)
  prepared=FreshAnalysisFlow.prepare(frozen);plan=prepared['plan'];body=JSON.parse(plan['body'])
  prompt=body['contents'][0]['parts'][0]['text']
  # Keep every policy constraint, omit only trace/audit metadata from the wire.
  full=JSON.generate(plan.fetch('frozen').fetch('trace').fetch('ruleBindings'))
  constraints=plan['frozen']['trace']['ruleBindings'].map{|r|r.fetch('constraint')}.uniq
  prompt=prompt.sub("Shared policies: #{full}","Shared policy constraints: #{JSON.generate(constraints)}")
  prompt += "\n"+INSTRUCTION+"\nOUTPUT ECONOMY: Return compact JSON, without indentation, blank lines, Markdown or commentary. Preserve COMPLETE sourceText (including case and line breaks), final copy, facts and all required typography/geometry. Use short IDs consistently. coreIntent and marketingFunction are concise semantic phrases, not repeated source sentences or explanations; matching rewrite metadata repeats the same short phrase. omissionReason is empty for render actions and a short reason for omit actions. Do not echo policies, the request, or reasoning. Never omit a required block or coordinate to save tokens."
  body['contents'][0]['parts'][0]['text']=prompt
  body.dig('generationConfig','responseFormat','text','schema','properties','sourceStructure','required') << 'decorations'
  group=body.dig('generationConfig','responseFormat','text','schema','properties','sourceStructure','properties','textGroups','items')
  group['properties']['fillStops']={'type'=>'array','maxItems'=>4,'items'=>{'type'=>'object','properties'=>{'at'=>{'type'=>'number'},'color'=>{'type'=>'string'}},'required'=>%w[at color]}}
  group['properties']['outline']={'type'=>'object','properties'=>{'color'=>{'type'=>'string'},'width'=>{'type'=>'number'}},'required'=>%w[color width]}
  group['properties']['fillDirection']={'type'=>'string','enum'=>%w[horizontal vertical]}
  group['required']+=%w[fillStops outline fillDirection]
  group['properties']['blockIds']['minItems']=1;group['properties']['blockIds']['maxItems']=1
  panel=body.dig('generationConfig','responseFormat','text','schema','properties','sourceStructure','properties','panels','items');panel['required']+=%w[sceneBounds borderWidth labelRadius labelFillStops labelPointer]
  # Descriptions duplicate explicit prompt units; types, enums and required fields remain.
  strip_descriptions(body.dig('generationConfig','responseFormat','text','schema'))
  check_lengths!(body)
  plan['body']=JSON.generate(body);plan['binding']['requestHash']=Digest::SHA256.hexdigest(plan['body']);plan['binding']['observationRevision']=2;plan['binding']['analysisCompactRevision']=1
  prepared.merge('liveEnabled'=>false,'modelCalls'=>0,'validationState'=>'offline-only-unvalidated-by-model')
 end
end
