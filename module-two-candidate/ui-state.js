// Pure display policy: failed/unknown outcomes never imply retry or acceptance.
var UIState = {
  derive:function(s) {
    var ready=s.state==='generated_pending_review' && s.hasImage && s.hasResult;
    return {capturedAt:s.capturedAt,state:s.state,approval:s.approvalConsumed?'已消费，不可复用':'未消费；界面不能执行',
      localImage:ready?'已有原始 JPEG，待人工检查':'无可验收的生成图片',
      remoteResult:ready?'已返回结果；质量尚未验收':'未知：未保存成功响应，不能推断未计费',
      visualAcceptance:ready?'待人工验收':'无法开展：缺少成功生成结果',
      canRetry:false,canAutoAccept:false,showImage:ready,
      connection:s.connectionOK?'基础 HTTPS 可达；账户与模型权限未测':'未取得成功的基础 HTTPS 证据'};
  }
};
