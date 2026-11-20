# Recovered source contract; no OCR, post-rendering or invented body-case rule.
module SharedTypography
 FORBIDDEN=/headlights?/i
 SOURCE={'thread'=>'01a11b37-b428-7612-b8d2-06748385001c','message'=>'msg_0952881dc1436861016ac7844ce968819a9d8dd347353971a6','case'=>'typography-policy.v3.1.json A38–40 / K35','font'=>'S08 Inter regular and italic assets','customOverride'=>'2026-10-08 subsequent user confirmation'}.freeze
 def self.contract(o)
  mode=o.fetch('mode')
  {'source'=>SOURCE,'title'=>mode=='ai-rewrite' ? 'Title Case' : 'not-applied',
   'subtitle'=>mode=='ai-rewrite' ? 'Sentence case' : 'not-applied',
   'body'=>'no-separate-case-convention-recovered','brand'=>mode=='ai-rewrite'&&!o.fetch('brandName','').strip.empty? ? 'UPPERCASE' : 'no-auto-case',
   'custom'=>'verbatim-including-case-line-breaks-only','protected'=>'supplied brands/acronyms/model identifiers/confirmed parameter notation; brand uppercase exception only in AI rewrite',
   'font'=>'Inter','fontAssetsLocal'=>false,'rendering'=>'model-instruction-only-not-embedded-font-rendering',
   'roleStructure'=>'existing roles/count/order/module/line structure; no template-added roles',
   'heightAdaptation'=>{'guideline'=>[0.8,1.2],'referenceRatioFirst'=>true,'automaticPixelRejection'=>false},
   'length'=>'no-universal-word-or-character-cap','acceptance'=>'overall-usability; minor differences advisory; no paid automatic scan'}
 end
 def self.constraint(o)
  text='Typography: use Inter regular/italic for ordinary generated text. Match each role separately: weight, measured visible glyph height (not fontSize or bbox height), line count and line spacing; no global font size or horizontal stretching. Preserve the title group position, proportions and spacing together. Use 0.8–1.2 reference letter-height adaptation as guidance, prioritizing the observed title/subtitle ratio and minimal readability adjustment, not strict pixel rejection. For scene-projected text preserve glyph style, italic treatment, weight, letter spacing and quadrilateral perspective. Do not guess fixed font sizes or weights. '
  case o['mode']
  when 'ai-rewrite'
   text+='Apply Title Case to titles and Sentence case to subtitles. No independent body-case convention is supplied. Protect supplied brand identity, acronyms (such as LED, HID, IP), model identifiers and confirmed parameter/unit notation from automatic case conversion. '
   text+='The reference defines existing text roles, count, hierarchy, order, module ownership, line count and structure. Keep existing roles; rewriting is assessed across the entire image, so one natural wording change suffices and other sentences may stay unchanged. Preserve meaning and selling intent; case, punctuation and line breaks alone do not count. do not add a template subtitle or split selling-point lines into extra roles. If copy does not fit, shorten equivalently first, then minimally adapt. Use only safe qualitative descriptions when facts are absent; do not inherit numerical, certification, technical or comparison-object claims. No universal word or character cap is specified. '
   text+=o.fetch('brandName','').strip.empty? ? 'No brand was supplied: remove overlay brands; do not inherit reference brands. ' : 'Render the supplied own-brand overlay in UPPERCASE, the explicit exception to brand case preservation. '
  when 'preserve-reference'
   text+='Preserve reference wording and letter case exactly, except separately disclosed user brand substitutions or unsupported-claim omissions. Inter changes font, never wording or case. '
  when 'custom'
   text+='Custom copy overrides automatic title, subtitle and brand capitalization: preserve every supplied character and case, allowing necessary line breaks only. '
  else
   text+='Remove-all-copy mode adds no overlay text; capitalization and font instructions do not authorize new text. '
  end
  text+'Reference font/style inheritance excludes letter case: AI title/subtitle case rules override reference capitalization; custom copy retains its exact case. Protect only user-supplied or confirmed facts; never restore unsupported reference parameters. Forbidden-word checks take priority over all casing and font instructions. Font identity is an instruction, not a verified embedded-font rendering guarantee.'
 end
end
