'use strict';
var overlay=document.getElementById('overlay');
function draw(){
  overlay.replaceChildren();
  var boxes=[];
  if(document.getElementById('regions').checked) boxes=boxes.concat(FROZEN.regions);
  if(document.getElementById('texts').checked) boxes=boxes.concat(FROZEN.text.map(function(t){return {name:t.text,box:t.box,note:t.action,text:true};}),[{name:'温度条',box:FROZEN.temperatureBar,note:'保留功能刻度与蓝红关系',text:true}]);
  boxes.forEach(function(r){
    var b=document.createElement('button');b.className='box'+(r.text?' text-box':'');b.setAttribute('aria-label',r.name);
    b.style.left=(r.box[0]/12)+'%';b.style.top=(r.box[1]/15)+'%';b.style.width=(r.box[2]/12)+'%';b.style.height=(r.box[3]/15)+'%';
    var label=document.createElement('span');label.textContent=r.name;b.append(label);
    b.onclick=function(){document.getElementById('detail').textContent=r.name+' · [x,y,w,h] = ['+r.box.join(', ')+'] px · '+r.note+'。坐标为人工估读草稿。';};overlay.append(b);
  });
}
document.getElementById('regions').onchange=draw;document.getElementById('texts').onchange=draw;draw();
document.getElementById('textRows').replaceChildren();
document.getElementById('missing').replaceChildren();
FROZEN.text.forEach(function(t){var row=document.createElement('tr');[t.text,t.action,t.box.join(' / '),t.font].forEach(function(s){var cell=document.createElement('td');cell.textContent=s;row.append(cell);});document.getElementById('textRows').append(row);});
FROZEN.missing.forEach(function(s){var li=document.createElement('li');li.textContent=s;document.getElementById('missing').append(li);});
document.getElementById('prompt').textContent=FROZEN.prompt;
document.getElementById('params').textContent=JSON.stringify(FROZEN.call,null,2);
document.getElementById('summary').onclick=function(){
  var n=Array.from(document.querySelectorAll('.reviewCheck')).filter(function(e){return e.checked;}).length;
  document.getElementById('confirmation').textContent=(n===3?'历史方案复核摘要：':'仍有 '+(3-n)+' 项未复核。\n')+'冻结草稿 '+FROZEN.version+'；原参考图与新提示词；gemini-3.1-flash-image，2K / 4:5，4096 输出 tokens，minimal 思考；1 次，0 重试，180 秒超时；原预算 $0.26。\n此次批准已消费，任务 stopped，远端结果未知。本页只能复核信息，不能授权或启动重试。';
};
