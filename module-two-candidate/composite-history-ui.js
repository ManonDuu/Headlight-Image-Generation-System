'use strict';
// Read-only integration for saved layered results; never starts a model call.
const previousCompositeDisplay=display;
display=function(s){
 const ready=previousCompositeDisplay(s);let panel=$('compositeAssets');
 if(!panel){panel=document.createElement('div');panel.id='compositeAssets';$('acceptance').after(panel);}
 panel.replaceChildren();panel.hidden=s.workflow!=='reference-layer-composite';
 if(!panel.hidden){
  const note=document.createElement('p');note.textContent='此记录为真实背景＋本地 Inter 文字合成，包含执行者校正；不是旧的整图直出，也不表示自动流程已全面验收。';panel.append(note);
  const button=document.createElement('button');button.textContent='下载原始无字背景';button.onclick=async()=>{button.disabled=true;try{const asset=await blob('/api/task/'+s.id+'/background'),hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await asset.arrayBuffer()))).map(v=>v.toString(16).padStart(2,'0')).join('');if(hash!==s.backgroundHash)throw Error('背景校验失败');download('background-'+s.id+'.jpg',asset);}catch(e){say(e.message);}finally{button.disabled=false;}};panel.append(button);
  const text=document.createElement('p');text.textContent='合成文字：'+s.composition.texts.join(' / ');panel.append(text);
 }
 return ready;
};
const previousCompositeNew=newTask.onclick;
newTask.onclick=async()=>{await previousCompositeNew();if(!job&&$('compositeAssets')){$('compositeAssets').replaceChildren();$('compositeAssets').hidden=true;}};
