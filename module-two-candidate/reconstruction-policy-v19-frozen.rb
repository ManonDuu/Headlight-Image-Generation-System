require_relative 'reference-image-brief-v19-frozen'
# Isolated candidate. No network, credentials, production integration or history migration.
module ReconstructionPolicyV19Frozen
 VERSION='reference-inspired-20261022.9'
 MODES=%w[preserve-reference custom ai-rewrite remove-all-copy].freeze
 LAYOUTS=%w[keep-reference auto-layout].freeze
 TONES=%w[keep-reference adjust-color].freeze
 RATIOS=%w[follow-reference 1:1 12:15 4:5 3:4 16:9 5:4 4:3 9:16 2:3 3:2 custom].freeze
 FORBIDDEN=/headlights?/i
 def self.compile(options, source_copy:nil, source_conflicts:[])
  o=Marshal.load(Marshal.dump(options))
  mode=o.fetch('mode');layout=o.fetch('layoutMode');tone=o.fetch('layoutTone');mod=o.fetch('module','reference-reconstruction')
  raise 'Unknown copy mode' unless MODES.include?(mode)
  raise 'Unknown layout mode' unless LAYOUTS.include?(layout)
  raise 'Unknown palette mode' unless TONES.include?(tone)
  raise 'Unknown module' unless %w[reference-reconstruction product-replacement].include?(mod)
  ratio=o.fetch('output').fetch('aspectRatio');raise 'Unknown ratio' unless RATIOS.include?(ratio)
  raise 'Native size resolution required before sending' if ratio=='custom' && !%w[width height].all?{|k|o['output'][k].is_a?(Integer)&&o['output'][k]>0}
  raise 'Choose a valid graphic accent color' if tone=='adjust-color' && !o.fetch('color','').match?(/\A#[0-9a-fA-F]{6}\z/)
  # Inactive values never become instructions or conflict sources.
  o.delete('color') if tone=='keep-reference'
  o.delete('customCopy') unless mode=='custom'
  %w[brandName productParameters].each{|k|o.delete(k)} if mode=='remove-all-copy'
  custom=o.fetch('customCopy','');brand=o.fetch('brandName','');facts=o.fetch('productParameters','')
  raise 'Complete custom copy is required' if mode=='custom'&&custom.strip.empty?
  %w[customCopy brandName productParameters].each{|k|raise "Forbidden term in #{k}" if o.fetch(k,'').match?(FORBIDDEN)}
  conflicts=[]
  if mode=='custom'
   pattern=/\bIP\s*\d+\b|[+-]?\d+(?:\.\d+)?\s*(?:°\s*C|K\b|W\b|V\b|A\b|LM\b|LUMENS?\b|%|HOURS?\b)/i
   tokens=lambda{|s|s.scan(pattern).map{|v|v.upcase.gsub(/\s+/,'')}}
   kind=lambda{|v|v.start_with?('IP') ? 'IP' : v.sub(/\A[+-]?\d+(?:\.\d+)?/,'')}
   tokens.call(custom).each do |v|
    same=tokens.call(facts).select{|f|kind.call(f)==kind.call(v)}
    conflicts<<'Custom copy conflicts with supplied parameter: '+v if !same.empty?&&!same.include?(v)
   end
   custom.scan(/(?:brand|品牌)\s*[:：]\s*([^\n,，;；]+)/i).flatten.each do |v|
    conflicts<<'Custom copy conflicts with explicit brand' if brand.strip.empty?||v.strip!=brand.strip
   end
  end
  conflicts.concat(source_conflicts) if mode=='preserve-reference'
  if mode=='preserve-reference' && source_copy
   conflicts<<'Source wording contains a forbidden term' if source_copy.any?{|s|s.match?(FORBIDDEN)}
  end
  # Brand/parameter replacement is a proposed text change, not a silent preserve-mode exception.
  if mode=='preserve-reference' && source_copy && !brand.strip.empty? && !source_copy.any?{|text|text.include?(brand.strip)}
   conflicts<<'Supplied brand is absent from source wording; resolve whether to substitute or leave copy unchanged'
  end
  rules=[];add=lambda{|id,text|rules<<{'id'=>id,'constraint'=>text}}
  add.call('goal','Learn the reference selling-point communication, broad visual style and useful composition. Create a new coherent design, not a pixel replica. Preserve the core selling intent without inventing or strengthening product facts.')
  add.call('scope','Each selected option controls only its own dimension. Copy determines visible wording; layout determines composition; palette determines graphic colors; ratio determines canvas shape. Unlocked design decisions may be creative. Never infer an extra user choice from a different option.')
  copy=case mode
  when 'preserve-reference'
   'Extract all reference overlay copy and preserve its wording, spelling, capitalization and punctuation exactly. Necessary line wrapping may change. Brand substitutions, unsupported claims and forbidden wording are pre-generation conflicts: propose the exact change and obtain resolution before any image request. Never silently delete, replace or rewrite a source phrase. Uncertain OCR must not be guessed.'
  when 'custom'
   'customCopy is the COMPLETE visible overlay wording. Preserve every character, case and punctuation; allow only necessary line wrapping. Add no reference captions, brand names or parameter text beyond this complete copy. Other fields are consistency evidence, not permission to append copy. Resolve factual or brand conflicts before any image request.'
  when 'ai-rewrite'
   'Infer the reference core selling intent and rewrite naturally where useful. No mandatory difference quota or per-block rewrite quota. Keep meaningful comparison categories. Use supplied facts as available evidence, not mandatory additional selling points. Do not inherit unconfirmed numerical, certification, compatibility or warranty claims. Use Title Case for headlines and Sentence case for subtitles; protect acronyms, model codes and units. Use supplied brand identity in uppercase only when an overlay brand is appropriate.'
  else
   'Remove all added overlay text, numbers, labels, scales and brands. Add no text, including supplied metadata. Preserve physical product printing. Rebalance remaining visual content naturally; deleted text leaves no mandatory empty container.'
  end
  add.call('copy',copy)
  if mode=='ai-rewrite'
   add.call('copy-density','Keep rewritten copy concise and suited to the reference information density. Prefer one core benefit headline of 3-6 English words and, only if useful, a complementary subtitle of 5-10 words. These are default targets, not mandatory quotas; preserve necessary meaning and model codes. Keep labels short, remove repetition and do not invent extra captions or brand slots to fill space. Internally compose and shorten wording before rendering. If space is tight, simplify rewritten copy and rebalance the design rather than shrinking type or crowding the image. Use Title Case headlines, Sentence case subtitles and preserve technical acronyms. This instruction applies only to AI rewriting, never verbatim or no-copy modes.')
  end
  add.call('design-learning','Infer the reference distinctive design relationships: information hierarchy, reading flow, image/text grouping and useful treatments such as frames, caption rails, callouts or scene-led whitespace. Under reference layout, make that inspiration recognizable while redesigning freely; under auto-layout, use useful inspiration without preserving its arrangement. Do not force a border, split comparison, checklist, subtitle or extra text onto every image. Respect selected copy mode: design devices do not authorize adding or rewriting words.')
  add.call('visual-meaning','Expand the core selling intent into relevant believable scenes where useful. When meaning depends on a direction, sequence, light distribution or spatial relationship, retain that essential relationship as far as the illustration reasonably permits. This is gentle semantic guidance, not exact beam geometry, coordinates, a specialized optical simulation or an automatic rejection gate. Do not exaggerate darkness, exposure, glare or other conditions just to dramatize a benefit. Keep scenes natural and text/background contrast readable. Creative scene expansion never authorizes new product capabilities, measurements or guarantees.')
  add.call('layout',layout=='keep-reference' ? 'Use the reference main composition, reading direction and visual emphasis as guidance. Reasonably rearrange groups, label treatment, spacing, font sizes and line wrapping for a balanced new design. No original coordinates, alignment axes, container count, centering rule or font-size ratios are mandatory. Preserve meaningful image-to-label associations.' : 'Choose the clearest composition for the selected content and canvas. You may change group positions, reading arrangement, alignment and label treatment. Original partitions and alignment are not constraints. Preserve meaningful image-to-label associations.')
  add.call('palette',tone=='adjust-color' ? "Use #{o['color']} as the principal graphic accent for permitted text, decoration and graphic elements. Combine with neutral support colors for legibility; not every word must have that color. Never tint photographic scenes, physical products or emitted light." : 'Learn the reference overall graphic palette for permitted text and decoration, allowing neutral support colors and balanced contrast. Do not copy its photographic color cast onto new scenes or recolor physical products or emitted light.')
  add.call('canvas',"Requested canvas choice: #{ratio}. Resolve to a supported native size before sending; disclose any approximate ratio or unsupported custom size. Recompose for the resolved canvas instead of stretching or clipping essential content. No requirement to extend the old canvas or retain original region geometry.")
  add.call('typography','Use a clean Inter-like sans serif direction when overlay text is permitted. Prioritize legibility, balanced hierarchy and coherent title groups. No reference letter-height matching, original line count or universal label centering. Font appearance is a generation instruction, not an embedded-font guarantee. Exact copy policies override automatic capitalization. In no-copy mode add no glyphs.')
  add.call('scene',mod=='reference-reconstruction' ? 'Create new scenes that serve the same selling intent. Decorative imagery may be changed, simplified or omitted. Do not require original photographic region count, exact camera side, subject occupancy or original scene boundaries. When panels compare performance under otherwise equivalent conditions, keep their environment, viewpoint, weather and ambient conditions comparable and change only the intended compared property. Panels showing different use contexts, weather or scenes may deliberately differ; do not mistake a multi-scene montage for a controlled performance comparison. Never fabricate numerical performance results.' : o['sceneMode']=='keep' ? 'Preserve non-target background content, camera and lighting. Layout may rearrange overlays without changing that scene. Integrate the supplied target product naturally.' : 'Rebuild appropriate surroundings for the selling intent. In comparisons, preserve equivalent conditions between the newly generated views. Integrate the supplied target product naturally.')
  if mod=='product-replacement'
   raise 'Product scene choice required' unless %w[keep change].include?(o['sceneMode'])
   add.call('identity','Only the supplied real product asset defines target shape, parts, proportions, material, color and physical markings. Creative freedom does not authorize redesigning the product. This identity requirement is unverified until actual pixels are inspected; fail rather than substitute an approximate product.')
  else
   raise 'Reference reconstruction has no scene keep/change option' if o.key?('sceneMode')
   add.call('identity','Do not introduce or redesign a physical product asset. Inputs requiring exact product replacement belong to the separate product module.')
  end
  add.call('forbidden','Never output headlight or headlights in any capitalization. For verbatim modes, conflicting source or supplied wording must be resolved before generation, never silently rewritten.')
  if mode=='ai-rewrite'
   add.call('brand',brand.strip.empty? ? 'Remove reference overlay brands and logos; invent no brand. Preserve physical product markings.' : 'Use only the supplied own brand for appropriate overlays; remove competing overlay brands. Do not invent a new branding slot merely because brand data exists.')
   add.call('rewrite-claims',facts.strip.empty? ? 'AI REWRITE FINAL COPY CHECK: no target-product parameters have been supplied. Delete ALL source performance numbers, units, multipliers, numerical distance pins, measurement scales and their claim-bearing labels from the reconstructed overlay. Reading a number in the reference never confirms it. Replace the numerical claim block with a concise qualitative benefit headline and optional short supporting phrase, preserving selling intent and designed hierarchy. Do not transcribe the source statistics, correct only their spelling, or recolor them as a substitute for rewriting. Ordinary step numbering is allowed only for actual ordered instructions, not invented measurements.' : 'AI REWRITE FINAL COPY CHECK: only explicitly supplied productParameters can authorize performance numbers and units. Remove source statistics, numerical distance pins and claim-bearing scales that do not match those supplied facts. Where a parameter block is removed, redesign it with concise qualitative selling-point copy rather than carrying source numbers over. Do not add confirmed parameters merely to fill space.')
  end
  add.call('facts','Reference claims are not evidence of target-product performance. Never invent or strengthen numerical, compatibility, certification, warranty or safety claims. A supplied fact is not a request to display it. Preserve physical markings. Conflicting exact text must be resolved before generating, not silently edited.')
  if mode=='ai-rewrite'
   add.call('copy-case','AI REWRITE LETTER CASE PRIORITY: render the main headline in mixed case, capitalizing the first letter of EVERY ordinary English word and using lowercase for the remaining letters, including short words such as And, Of, The and For. Never render a headline in ALL CAPITALS, small caps or an uppercase-only font; choose a font with visibly distinct lowercase glyphs. Subtitle: capitalize only the first word and proper names, with ordinary remaining words lowercase. Preserve genuine technical acronyms (LED, USB), model codes and unit notation. Reference brand names are NOT technical acronyms; letter-case handling does not authorize retaining a reference brand. Brand use follows the separate brand rule and supplied brandName only. These letter-case requirements override the reference typography and any bold, condensed, industrial or advertising style. Check the actual rendered letter shapes before returning. Examples demonstrate casing only, not required wording: headline See Further And Wider; subtitle See road details more clearly. Do not print these examples unless independently appropriate to the selling intent.')
  end
  add.call('delivery','Return one completed image. No automatic retry, paid post-generation review or silent repair. Record actual output limitations; a valid request does not prove image compliance.')
  rules=ReferenceImageBriefV19Frozen.refine(rules,o) if mod=='reference-reconstruction'
  pending=mode=='preserve-reference'&&source_copy.nil?
  state=conflicts.empty? ? (pending ? 'needs-source-copy-review' : 'ready-for-visual-test') : 'needs-copy-resolution'
  {'version'=>VERSION,'state'=>state,'conflicts'=>conflicts.uniq,'effectiveOptions'=>o,'rules'=>rules,'sourceCopy'=>source_copy,'modelCalls'=>0,'productionIntegrated'=>false,'sendAllowed'=>state=='ready-for-visual-test','data'=>{'customCopy'=>mode=='custom' ? custom : nil,'brandName'=>brand,'productParameters'=>facts}}
 end
end
