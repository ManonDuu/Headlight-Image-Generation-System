ObjC.import('Foundation');
function run(args){
  function read(p){return ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(p,$.NSUTF8StringEncoding,null));}
  eval(read(args[0]+'/frozen-draft.js'));
  function element(){return {children:[],style:{},checked:false,textContent:'',append:function(x){this.children.push(x);},replaceChildren:function(){this.children=[];},setAttribute:function(){}};}
  var nodes={},checks=[element(),element(),element()];
  ['overlay','regions','texts','detail','textRows','missing','prompt','params','summary','confirmation'].forEach(function(id){nodes[id]=element();});
  nodes.regions.checked=true;
  var document={getElementById:function(id){return nodes[id];},createElement:element,querySelectorAll:function(){return checks;}};
  new Function('document','FROZEN',read(args[0]+'/review.js'))(document,FROZEN);
  function check(x){if(!x)throw Error('preview assertion failed');}
  check(nodes.overlay.children.length===5);
  nodes.texts.checked=true;nodes.texts.onchange();check(nodes.overlay.children.length===14);
  nodes.overlay.children[1].onclick();check(nodes.detail.textContent.indexOf('1051')>=0);
  check(nodes.textRows.children.length===8);
  nodes.summary.onclick();check(nodes.confirmation.textContent.indexOf('3 项未复核')>=0);
  checks.forEach(function(c){c.checked=true;});nodes.summary.onclick();check(nodes.confirmation.textContent.indexOf('历史方案复核摘要')===0);
  var html=read(args[0]+'/review.html');check(html.indexOf("connect-src 'none'")>=0);
  check(html.indexOf('disabled>真实生图已锁定')>=0);
  return 'PASS preview logic: 5 regions, 9 text/bar boxes, 8 text rows, detail clicks, review summary, network CSP and disabled real action. DOM fixture, not browser screenshot.';
}
