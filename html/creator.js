// Disenador de personaje. La pagina propone valores; el cliente los acota al ped y devuelve el
// estado real y los limites (cantidad de peinados, prendas y texturas del modelo actual).
(()=>{
  const resource=typeof GetParentResourceName==='function'?GetParentResourceName():'os_devtools';
  const post=(name,data)=>fetch(`https://${resource}/${name}`,{method:'POST',headers:{'Content-Type':'application/json; charset=UTF-8'},body:JSON.stringify(data||{})}).then(r=>r.json()).catch(()=>({}));
  const root=document.getElementById('creator');
  const FEATURES=['Nariz: ancho','Nariz: altura','Nariz: longitud','Nariz: puente','Nariz: punta','Nariz: desvío','Cejas: altura','Cejas: profundidad',
    'Pómulos: altura','Pómulos: ancho','Mejillas','Ojos: apertura','Labios: grosor','Mandíbula: ancho','Mandíbula: forma','Mentón: altura',
    'Mentón: longitud','Mentón: ancho','Mentón: hoyuelo','Cuello: grosor'];
  const TABS=[['heritage','Herencia'],['face','Rasgos'],['hair','Pelo'],['clothes','Ropa']];
  let state=null,limits=null,tab='heritage',sending=false,queued=false,camera='body',heading=0,open=false;

  const el=(tag,cls,text)=>{const n=document.createElement(tag);if(cls)n.className=cls;if(text!=null)n.textContent=text;return n;};
  const get=(path)=>path.split('.').reduce((o,k)=>o==null?o:o[k],state);
  const set=(path,value)=>{const keys=path.split('.');let o=state;keys.slice(0,-1).forEach(k=>o=o[k]);o[keys[keys.length-1]]=value;};
  const limitOf=(path)=>{
    if(!limits)return 0;
    const map={'hair.style':limits.hair,'hair.color':limits.hairColors,'hair.highlight':limits.hairColors,'eyebrows.style':limits.eyebrows,'beard.style':limits.beard,'eyebrows.color':64,'beard.color':64,father:46,mother:46,eyes:32};
    if(path in map)return map[path];
    const m=path.match(/^(clothes|props)\.(\w+)\.(d|t)$/);return m&&limits[m[1]][m[2]]?limits[m[1]][m[2]][m[3]]:0;
  };

  function send(){
    if(sending){queued=true;return;}
    sending=true;
    post('creatorApply',state).then(res=>{
      sending=false;
      if(res&&res.state){state=res.state;limits=res.limits;refresh();}
      if(queued){queued=false;send();}
    });
  }
  function change(path,value){set(path,value);
    // Al cambiar de prenda, la textura vuelve a la primera.
    const m=path.match(/^(clothes|props)\.(\w+)\.d$/);if(m)set(`${m[1]}.${m[2]}.t`,0);
    send();
  }

  function slider(label,path,min,max,step,format){
    const row=el('label','cr-row');const head=el('div','cr-label');const name=el('span',null,label);const val=el('span','cr-val');head.append(name,val);
    const input=el('input');input.type='range';input.min=min;input.max=max;input.step=step;input.dataset.path=path;
    input.addEventListener('input',()=>{change(path,Number(input.value));val.textContent=format(Number(input.value));});
    row.append(head,input);row.update=()=>{const v=get(path);if(document.activeElement!==input)input.value=v;val.textContent=format(v);};return row;
  }
  function stepper(label,path,min,opts={}){
    const row=el('div','cr-row');const head=el('div','cr-label');head.append(el('span',null,label));
    const box=el('div','cr-step');const prev=el('button','cr-arrow','‹');const value=el('span','cr-stepval');const next=el('button','cr-arrow','›');
    prev.type=next.type='button';
    const move=d=>{const count=limitOf(path);const span=count-min;if(span<=0)return;let v=get(path)+d;if(v<min)v=count-1;if(v>count-1)v=min;change(path,v);row.update();};
    prev.addEventListener('click',()=>move(-1));next.addEventListener('click',()=>move(1));
    box.append(prev,value,next);row.append(head,box);
    row.update=()=>{const v=get(path),count=limitOf(path);
      value.textContent=v<0?(opts.none||'Ninguno'):count>0?`${v+1} / ${count}`:'—';
      prev.disabled=next.disabled=count-min<=1;};
    return row;
  }
  const pct=v=>`${Math.round(v*100)}%`;
  const signed=v=>(v>0?'+':'')+Math.round(v*100);

  let controls=[];
  function section(title){const s=el('div','cr-section');if(title)s.append(el('div','cr-section-title',title));return s;}
  function build(){
    const body=root.querySelector('.cr-body');body.replaceChildren();controls=[];
    const add=(parent,c)=>{parent.append(c);controls.push(c);};
    if(tab==='heritage'){
      const s=section('Padres');add(s,stepper('Padre','father',0));add(s,stepper('Madre','mother',0));body.append(s);
      const m=section('Mezcla');add(m,slider('Parecido (padre ↔ madre)','shapeMix',0,1,0.01,pct));add(m,slider('Tono de piel (padre ↔ madre)','skinMix',0,1,0.01,pct));
      add(m,stepper('Color de ojos','eyes',0));body.append(m);
    }else if(tab==='face'){
      const s=section(null);FEATURES.forEach((name,i)=>add(s,slider(name,`features.${i}`,-1,1,0.01,signed)));body.append(s);
    }else if(tab==='hair'){
      const h=section('Pelo');add(h,stepper('Peinado','hair.style',0));add(h,stepper('Color','hair.color',0));add(h,stepper('Mechas','hair.highlight',0));body.append(h);
      const b=section('Cejas');add(b,stepper('Forma','eyebrows.style',0));add(b,slider('Intensidad','eyebrows.opacity',0,1,0.01,pct));add(b,stepper('Color','eyebrows.color',0));body.append(b);
      if(state.sex==='male'){const f=section('Barba');add(f,stepper('Estilo','beard.style',-1,{none:'Sin barba'}));add(f,slider('Intensidad','beard.opacity',0,1,0.01,pct));add(f,stepper('Color','beard.color',0));body.append(f);}
    }else{
      [['top','Chaqueta / camiseta'],['undershirt','Prenda interior'],['arms','Brazos / guantes'],['legs','Pantalón'],['shoes','Calzado']].forEach(([key,label])=>{
        const s=section(label);add(s,stepper('Modelo',`clothes.${key}.d`,0));add(s,stepper('Variante',`clothes.${key}.t`,0));body.append(s);});
      [['hat','Sombrero'],['glasses','Gafas']].forEach(([key,label])=>{
        const s=section(label);add(s,stepper('Modelo',`props.${key}.d`,-1,{none:'Ninguno'}));add(s,stepper('Variante',`props.${key}.t`,0));body.append(s);});
    }
    refresh();
  }
  function refresh(){
    if(!state)return;
    root.querySelectorAll('.cr-sex button').forEach(b=>b.classList.toggle('on',b.dataset.sex===state.sex));
    root.querySelectorAll('.cr-tabs button').forEach(b=>b.classList.toggle('on',b.dataset.tab===tab));
    controls.forEach(c=>c.update());
  }
  function randomize(){
    const r=(n)=>Math.floor(Math.random()*Math.max(n,1));
    state.father=r(46);state.mother=r(46);state.shapeMix=Math.round(Math.random()*100)/100;state.skinMix=Math.round(Math.random()*100)/100;
    state.features=state.features.map(()=>Math.round((Math.random()*0.8-0.4)*100)/100);
    state.eyes=r(8);state.hair.style=r(limits.hair);state.hair.color=r(Math.min(limits.hairColors,20));state.hair.highlight=state.hair.color;
    state.eyebrows.style=r(limits.eyebrows);state.eyebrows.color=state.hair.color;state.eyebrows.opacity=0.8;
    if(state.sex==='male'){state.beard.style=Math.random()<0.4?-1:r(limits.beard);state.beard.color=state.hair.color;state.beard.opacity=0.9;}
    send();
  }

  function layout(){
    root.replaceChildren();
    const panel=el('div','cr-panel');
    const head=el('header','cr-head');head.append(el('div','cr-brand','OSCAR · CREADOR'),el('h2',null,'Diseña tu personaje'));
    const sex=el('div','cr-sex');[['male','Hombre'],['female','Mujer']].forEach(([v,l])=>{const b=el('button',null,l);b.type='button';b.dataset.sex=v;
      b.addEventListener('click',()=>{if(state.sex===v)return;state.sex=v;send();build();});sex.append(b);});
    const tabs=el('nav','cr-tabs');TABS.forEach(([id,label])=>{const b=el('button',null,label);b.type='button';b.dataset.tab=id;b.addEventListener('click',()=>{tab=id;build();});tabs.append(b);});
    head.append(sex,tabs);
    const body=el('div','cr-body');
    const foot=el('footer','cr-foot');const rnd=el('button','btn ghost','Aleatorio');rnd.type='button';rnd.addEventListener('click',randomize);
    const done=el('button','btn primary','Terminar');done.type='button';done.addEventListener('click',()=>{done.disabled=true;post('creatorFinish');});
    foot.append(rnd,done);panel.append(head,body,foot);
    const dock=el('div','cr-dock');const views=el('div','cr-views');
    [['face','Cara'],['body','Cuerpo']].forEach(([v,l])=>{const b=el('button',null,l);b.type='button';b.dataset.view=v;b.classList.toggle('on',v===camera);
      b.addEventListener('click',()=>{camera=v;views.querySelectorAll('button').forEach(x=>x.classList.toggle('on',x.dataset.view===v));post('creatorView',{mode:v,heading});});views.append(b);});
    const rotate=el('input','cr-rotate');rotate.type='range';rotate.min=-180;rotate.max=180;rotate.value=0;
    rotate.addEventListener('input',()=>{heading=(Number(rotate.value)+360)%360;post('creatorView',{heading});});
    const hint=el('span','cr-hint','Girar');dock.append(views,hint,rotate);
    root.append(panel,dock);
  }
  window.addEventListener('message',e=>{
    const d=e.data;if(!d||d.action!=='creator')return;
    if(!d.open){open=false;root.classList.add('hidden');document.body.classList.remove('designing');return;}
    state=d.state;limits=d.limits;tab='heritage';camera='body';heading=0;open=true;
    layout();build();root.classList.remove('hidden');document.body.classList.add('designing');
  });
})();
