var ModuleFlow={
  newTask:function(){return {state:'draft',attempted:false,sourceHash:null,request:null,result:null,acceptance:'not-evaluated'};},
  freeze:function(t,request,hash){if(t.state!=='draft')throw Error('任务已冻结');if(!hash||!request.input[1].data)throw Error('缺少素材');t.request=request;t.sourceHash=hash;t.state='frozen';},
  mock:function(t,outcome){if(t.state!=='frozen'||t.attempted)throw Error('禁止重复执行');t.attempted=true;t.state=outcome==='success'?'mock-completed':'stopped';t.acceptance='not-evaluated';},
  receive:function(t,response){if(t.state!=='frozen'||t.attempted)throw Error('此任务已执行；请勿覆盖记录');t.attempted=true;try{t.result=Provider.parse({http:200,body:response});t.state='generated-pending-review';}catch(e){t.state='stopped';throw e;}},
  review:function(t,verdict,note){if(t.state!=='generated-pending-review')throw Error('没有真实结果可验收');if(['accepted','rejected'].indexOf(verdict)<0||!note.trim())throw Error('填写结论和依据');t.acceptance=verdict;t.reviewNote=note;}
};
