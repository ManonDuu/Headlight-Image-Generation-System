// Build one portable local HTML; no server, remote resources or browser access.
ObjC.import('Foundation');
function run(args){
  var root=args[0];
  function read(p){return ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(root+'/'+p,$.NSUTF8StringEncoding,null));}
  function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}
  eval(read('frozen-draft.js'));
  eval(read('ui-state.js'));
  var fm=$.NSFileManager.defaultManager;
  function exists(p){return Boolean(fm.fileExistsAtPath(root+'/'+p));}
  var job='review-pack-02/';
  var status=exists(job+'status')?read(job+'status').trim():'missing';
  var diag=exists('diagnostics/connectivity-host-20261017.txt')?read('diagnostics/connectivity-host-20261017.txt'):'';
  var state=UIState.derive({capturedAt:new Date().toISOString(),state:status,
    approvalConsumed:exists('live-attempts/approved-review-pack-02-20261016-one-call'),
    hasImage:exists(job+'output.jpg'),hasResult:exists(job+'result.json'),
    connectionOK:diag.indexOf('curl_exit=0')>=0 && diag.indexOf('tls_verify=0')>=0});
  $(JSON.stringify(state,null,2)).writeToFileAtomicallyEncodingError(root+'/current-state.json',true,$.NSUTF8StringEncoding,null);
  var html=read('review.html').replace("script-src 'self'","script-src 'unsafe-inline'");
  var stateRows=[['当前尝试',state.state],['一次批准',state.approval],['生成图片',state.localImage],['远端结果 / 实际费用',state.remoteResult],['人工验收',state.visualAcceptance],['当前基础连接',state.connection]].map(function(r){return '<tr><th>'+esc(r[0])+'</th><td>'+esc(r[1])+'</td></tr>';}).join('');
  var panel='<section class="panel"><h2>当前运行状态</h2><p class="muted">本地只读快照 '+esc(state.capturedAt)+' · 重新构建页面才刷新，不轮询网络。</p><table>'+stateRows+'</table><p>历史预计费用约 $0.102–$0.110；原批准预算 $0.26。它们不是本次已发生费用。</p><p>没有重试按钮；失败不会触发新请求。批准账本和冻结请求保持不变。</p></section>';
  if(state.showImage){var image64=ObjC.unwrap($.NSData.dataWithContentsOfFile(root+'/'+job+'output.jpg').base64EncodedStringWithOptions(0));panel+='<section class="panel"><h2>原始生成结果 · 未修改</h2><img alt="待人工验收的原始生成图" src="data:image/jpeg;base64,'+image64+'"></section>';}
  else panel+='<section class="panel"><h2>图片结果与人工验收</h2><p>尚无生成结果。下面两张是参考素材和历史 02C 样例，不是这次输出。</p><table><tr><th>结构相似 / 场景差异</th><td>未评估</td></tr><tr><th>功能标注 / 字体 / 位置</th><td>未评估</td></tr><tr><th>亮度 / 光束 / 证明关系</th><td>未评估</td></tr><tr><th>总体结论</th><td>未验收；离线测试不能替代图片验收</td></tr></table></section>';
  html=html.replace('<!-- CURRENT_STATE -->',panel);
  [FROZEN.reference.path,FROZEN.example.path].forEach(function(path){
    var mime=/jpg$/.test(path)?'image/jpeg':'image/png';
    var b64=ObjC.unwrap($.NSData.dataWithContentsOfFile(root+'/'+path).base64EncodedStringWithOptions(0));
    html=html.replace('src="'+path+'"','src="data:'+mime+';base64,'+b64+'"');
  });
  // Static fallback keeps the complete review readable even if scripting is off.
  var boxes=FROZEN.regions.map(function(r){var b=r.box;return '<button class="box" aria-label="'+esc(r.name)+'" style="left:'+b[0]/12+'%;top:'+b[1]/15+'%;width:'+b[2]/12+'%;height:'+b[3]/15+'%"><span>'+esc(r.name)+'</span></button>';}).join('');
  html=html.replace('<div id="overlay" class="overlay"></div>','<div id="overlay" class="overlay">'+boxes+'</div>');
  var rows=FROZEN.text.map(function(t){return '<tr>'+[t.text,t.action,t.box.join(' / '),t.font].map(function(s){return '<td>'+esc(s)+'</td>';}).join('')+'</tr>';}).join('');
  html=html.replace('<tbody id="textRows"></tbody>','<tbody id="textRows">'+rows+'</tbody>');
  html=html.replace('<ul id="missing"></ul>','<ul id="missing">'+FROZEN.missing.map(function(s){return '<li>'+esc(s)+'</li>';}).join('')+'</ul>');
  html=html.replace('<pre id="prompt"></pre>','<pre id="prompt">'+esc(FROZEN.prompt)+'</pre>');
  html=html.replace('<pre id="params"></pre>','<pre id="params">'+esc(JSON.stringify(FROZEN.call,null,2))+'</pre>');
  html=html.replace('<script src="frozen-draft.js"></script>','<script>'+read('frozen-draft.js')+'</script>');
  html=html.replace('<script src="review.js"></script>','<script>'+read('review.js')+'</script>');
  if(!$(html).writeToFileAtomicallyEncodingError(root+'/review-standalone.html',true,$.NSUTF8StringEncoding,null))throw Error('write-failed');
  var app=read('module-one.html').replace('<pre id="previous"></pre>','<pre id="previous">'+esc('状态：'+state.state+'\n批准：'+state.approval+'\n结果：'+state.remoteResult+'\n图片：'+state.localImage+'\n验收：'+state.visualAcceptance+'\n连接：'+state.connection)+'</pre>').replace('<!-- SCRIPTS -->','<script>'+read('frozen-draft.js')+'\n'+read('provider-core.js')+'\n'+read('module-flow.js')+'\nvar CURRENT_STATE='+JSON.stringify(state)+';\n'+read('module-one.js')+'</script>');
  if(!$(app).writeToFileAtomicallyEncodingError(root+'/module-one-standalone.html',true,$.NSUTF8StringEncoding,null))throw Error('write-failed');
  return 'Built self-contained local review with static fallback and no network capability.';
}
