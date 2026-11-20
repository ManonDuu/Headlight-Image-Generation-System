"""Module-owned Gemini transport. Exactly one attempt; credentials stay in memory."""
import base64
import json
from .transport import post_once

class GeminiProvider:
    model='gemini-3.1-flash-image'
    def __init__(self,key=None):self.key=key
    def capabilities(self):
        return {'provider':'gemini','model':self.model,'connected':bool(self.key),'liveEnabled':bool(self.key)}
    def generate(self,image_brief,assets,budget):
        if not self.key:raise RuntimeError('Gemini 尚未连接')
        if budget.get('reserveUSD',0)<0.5:raise RuntimeError('预算不足')
        prompt=image_brief['prompt']
        if len(prompt.encode())>64000 or len(assets)>1:raise RuntimeError('输入超过单次预算范围')
        parts=[{'text':prompt}]
        for a in assets:
            parts += [{'text':'Uploaded product: identity reference only; follow productPhotoPolicy'},
                      {'inlineData':{'mimeType':a['mime'],'data':base64.b64encode(a['bytes']).decode()}}]
        # New tasks store their final provider instructions at planning time.
        # This prevents later code changes from silently changing a saved request.
        try:
            packet=json.loads(prompt.splitlines()[-1])
        except (ValueError,IndexError):
            packet={}
        execution=packet.get('providerExecution',{}) if isinstance(packet,dict) else {}
        if execution.get('schema') in ('gemini-art-check-v1','gemini-art-check-v2'):
            if execution['schema']=='gemini-art-check-v2':
                render_brief=execution.get('renderBrief')
                if not isinstance(render_brief,str) or not render_brief.strip():
                    raise RuntimeError('任务缺少冻结的出图指令，请新建任务')
                parts[0]={'text':render_brief}
            final_check=execution.get('finalCheck')
            if not isinstance(final_check,str) or not final_check.strip():
                raise RuntimeError('任务缺少 Gemini 最终设计指令，请新建任务')
            parts.append({'text':final_check})
        else:
            try:
                frozen=json.loads(prompt.splitlines()[-1]);style=frozen['style']
                if frozen.get('setDesign',{}).get('revision')!='E13-gemini-set-light-20261026':raise ValueError('legacy brief')
                accent=style['palette']['accent'];highlight=style['palette']['highlight']
                label=style['typography']['labels']
                final_check=(f"FINAL SET DESIGN CHECK: This image belongs to the same set, not a new design. "
                    f"Graphic gradient endpoints are {accent} and {highlight} ONLY. "
                    "Use this exact color family in headline emphasis, label fills and callouts. "
                    "Environmental colors never replace the graphic theme. No automatic complementary-color headline. "
                    f"Use normal-width Inter-style headline 800, subtitle 600, labels {label['weight']}; "
                    f"label glyph height at least {label['minCanvasHeight']*100:g}% of canvas height. "
                    "Wrap or shorten labels; never thin or shrink text. No outer frame. "
                    "Rich natural scene colors, readable midtones, no gray wash or whole-scene dark overlay. "
                    "For cool-white LED light, keep neutral pavement brightly white with visible texture. "
                    "If no source vehicle is visible, let light enter continuously from the near frame edge; "
                    "no dark foreground gap before a floating bright patch. Broad rounded soft field, no isolated circular hotspot. "
                    "Review these requirements before returning the single image; do not print this checklist.")
                parts.append({'text':final_check})
            except (ValueError,KeyError,TypeError,IndexError):
                pass  # Legacy standalone briefs without a structured set contract.
        body={'contents':[{'role':'user','parts':parts}], 'generationConfig':{'candidateCount':1,'responseModalities':['IMAGE'],'maxOutputTokens':4096,'thinkingConfig':{'thinkingLevel':'MINIMAL'},'imageConfig':{'aspectRatio':image_brief['ratio'],'imageSize':'2K'}}}
        diagnostic={}
        self.last_diagnostic=diagnostic
        try:
            raw=post_once('https://generativelanguage.googleapis.com/v1beta/models/'+self.model+':generateContent',json.dumps(body).encode(),self.key,diagnostic)
        except Exception as exc:
            error=RuntimeError(str(exc) if isinstance(exc,RuntimeError) else '模型连接中断，结果未知；未自动重试')
            error.diagnostic=dict(diagnostic)
            raise error from None
        validation_reason='invalid-json'
        try:
            data=json.loads(raw);cs=data.get('candidates',[])
            diagnostic['candidateCount']=len(cs)
            diagnostic['finishReasons']=[c.get('finishReason') for c in cs if c.get('finishReason') in ('STOP','MAX_TOKENS','SAFETY','RECITATION','OTHER','IMAGE_SAFETY','IMAGE_PROHIBITED_CONTENT','NO_IMAGE')]
            diagnostic['promptBlocked']=bool(data.get('promptFeedback',{}).get('blockReason'))
            validation_reason='candidate-or-finish-reason'
            if len(cs)!=1 or cs[0].get('finishReason')!='STOP':raise ValueError()
            images=[p['inlineData'] for p in cs[0].get('content',{}).get('parts',[]) if 'inlineData' in p and not p.get('thought')]
            diagnostic['imagePartCount']=len(images)
            validation_reason='missing-or-multiple-images'
            if len(images)!=1:raise ValueError()
            validation_reason='invalid-image-data'
            mime=images[0]['mimeType'];blob=base64.b64decode(images[0]['data'],validate=True)
            sig={'image/png':b'\x89PNG\r\n\x1a\n','image/jpeg':b'\xff\xd8\xff'}
            if mime not in sig or not blob.startswith(sig[mime]) or not 100<len(blob)<20*1024*1024:raise ValueError()
            return {'bytes':blob,'mime':mime,'usage':data.get('usageMetadata',{}),'diagnostic':diagnostic}
        except (ValueError,KeyError,TypeError):
            diagnostic['validationFailure']=validation_reason
            error=RuntimeError('模型未返回完整有效图片（'+validation_reason+'），未自动重试；本次可能已计费')
            error.diagnostic=dict(diagnostic)
            raise error from None
