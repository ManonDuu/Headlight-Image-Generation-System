'use strict';
// Server is the sole durable store. No IndexedDB mirror, provider calls or retries.
globalThis.InternalReferenceServer=(()=>{
 async function encode(r){const out=structuredClone(r);for(const [obj,key] of [[out,'reference'],[out,'output'],[out.assets,'background']])if(obj?.[key] instanceof Blob){const b=obj[key],bytes=new Uint8Array(await b.arrayBuffer());let raw='';for(let i=0;i<bytes.length;i+=32768)raw+=String.fromCharCode(...bytes.subarray(i,i+32768));obj[key]={base64:btoa(raw),mime:b.type};}return out;}
 function decode(r){for(const [obj,key] of [[r,'reference'],[r,'output'],[r.assets,'background']])if(obj?.[key]?.base64)obj[key]=new Blob([Uint8Array.from(atob(obj[key].base64),c=>c.charCodeAt(0))],{type:obj[key].mime});return r;}
 class Store {
  constructor(token,endpoint='/api/internal/reference'){if(!token)throw Error('本地会话令牌必需。');this.token=token;this.endpoint=endpoint;}
  async call(payload){const response=await fetch(this.endpoint,{method:'POST',headers:{'Content-Type':'application/json','X-Session-Token':this.token},body:JSON.stringify(payload)});const result=await response.json();if(!response.ok)throw Error(result.error||'内部历史请求失败。');return result;}
  async read(id){return decode(await this.call({op:'read',id}));}
  async write(record,revision){return (await this.call({op:'write',record:await encode(record),revision})).revision;}
  async list(){return this.call({op:'list'});}
  async prepareProvider(originalTaskId,stage='layout-copy',layout=null){return this.call({op:'provider-prepare',originalTaskId,stage,layout});}
  async mockProposal(originalTaskId,fixtures){return this.call({op:'provider-mock-propose',originalTaskId,fixtures});}
  async download(id,hash){const r=await fetch(`/api/internal/reference/${encodeURIComponent(id)}/image?hash=${encodeURIComponent(hash)}`,{headers:{'X-Session-Token':this.token}});if(!r.ok)throw Error((await r.json()).error);const blob=await r.blob();await ProductCanvasFoundation.download({blob,manifest:{outputHash:hash}},`INTERNAL-${id}.png`);}
 }
 async function fromFrozen({token,frozen,reference,policy,fixtureOnly=false}){
  return ReferenceWorkflow.Workflow.create({enabled:true,store:new Store(token),frozen,reference,policy,fixtureOnly});
 }
 async function reviewedProposal(task,proposal,{reviewer,note}){
  if(proposal.state!=='assets-awaiting-human-review'||!reviewer?.trim()||!note?.trim())throw Error('必须核对模型提案后明确确认；不自动标记验收。');
  const p=proposal.package,background=new Blob([Uint8Array.from(atob(p.background.base64),c=>c.charCodeAt(0))],{type:p.background.mime});
  await task.supply({background,plan:p.plan,evidence:{sourceHash:p.sourceHash,backgroundHash:p.backgroundHash,planHash:p.planHash,reviewer,note,sceneReconstructed:true,oldCopyAbsent:true,layoutReviewed:true,factsReviewed:true,copyReviewed:true}});
 }
 return Object.freeze({Store,fromFrozen,reviewedProposal,productionEnabled:false});
})();
