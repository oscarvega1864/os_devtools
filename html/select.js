// Selector de personaje. Solo presenta datos y envia alias o nombre; el servidor decide.
(()=>{
  const $=id=>document.getElementById(id);
  const root=$('selector'),list=$('selList'),enter=$('selEnter'),create=$('selCreate'),first=$('selFirst'),last=$('selLast');
  const msg=$('selMessage'),count=$('selCount'),newBtn=$('selNew'),closeBtn=$('selClose'),aliasHint=$('selAlias');
  const money=new Intl.NumberFormat('es-ES',{maximumFractionDigits:0});
  const resource=typeof GetParentResourceName==='function'?GetParentResourceName():'os_devtools';
  const post=(name,data)=>fetch(`https://${resource}/${name}`,{method:'POST',headers:{'Content-Type':'application/json; charset=UTF-8'},body:JSON.stringify(data||{})}).catch(()=>{});
  let state={open:false,mode:'connect',characters:[],allowCreate:false,maxCharacters:1},selected=null,busy=false,creating=false;

  const titleCase=s=>s.split('_').filter(Boolean).map(w=>w[0].toUpperCase()+w.slice(1)).join(' ');
  const initials=s=>s.split('_').filter(Boolean).slice(0,2).map(w=>w[0].toUpperCase()).join('')||'?';
  const jobLabel=(job,rank)=>{
    if(!job||job==='unemployed')return 'Sin empleo';
    const j=titleCase(String(job));return rank&&rank!=='-'?`${j} · ${titleCase(String(rank))}`:j;
  };
  const ago=seconds=>{
    if(!Number.isFinite(seconds))return null;
    const diff=Math.max(0,Date.now()/1000-seconds);
    if(diff<90)return 'hace un momento';
    if(diff<3600)return `hace ${Math.round(diff/60)} min`;
    if(diff<86400)return `hace ${Math.round(diff/3600)} h`;
    const days=Math.round(diff/86400);return days===1?'ayer':days<30?`hace ${days} días`:new Date(seconds*1000).toLocaleDateString('es-ES');
  };
  // Igual que el servidor: letras A-Z, 2-16 por parte; se quitan acentos y la ñ pasa a n.
  const clean=v=>v.normalize('NFD').replace(/[̀-ͯ]/g,'').replace(/[^A-Za-z]/g,'').toLowerCase();
  const el=(tag,cls,text)=>{const n=document.createElement(tag);if(cls)n.className=cls;if(text!=null)n.textContent=text;return n;};

  function setMessage(text,kind){msg.textContent=text||'';msg.className='sel-message'+(kind?' '+kind:'');}
  function setBusy(value){busy=value;root.classList.toggle('busy',value);refreshButtons();}
  function refreshButtons(){
    const chosen=state.characters.find(c=>c.alias===selected);
    enter.disabled=busy||!chosen||(state.mode==='switch'&&chosen.active);
    enter.textContent=state.mode==='switch'?(chosen&&chosen.active?'En uso':'Cambiar'):'Entrar';
    const full=state.characters.length>=state.maxCharacters;
    newBtn.classList.toggle('hidden',!state.allowCreate||creating);
    newBtn.disabled=busy||full;
    count.textContent=`${state.characters.length}/${state.maxCharacters} personajes`+(full&&state.allowCreate?' · límite alcanzado':'');
  }
  function select(alias,scroll){
    selected=alias;
    for(const card of list.children){const on=card.dataset.alias===alias;card.classList.toggle('selected',on);card.setAttribute('aria-selected',on);if(on&&scroll)card.scrollIntoView({block:'nearest'});}
    refreshButtons();
  }
  function render(){
    list.replaceChildren();
    if(!state.characters.length){list.append(el('div','empty',state.allowCreate?'Aún no tienes personajes. Crea el primero.':'No hay personajes en esta cuenta.'));}
    state.characters.forEach((c,i)=>{
      const card=el('div','card'+(c.dead?' dead':''));card.dataset.alias=c.alias;card.setAttribute('role','option');card.style.animationDelay=`${i*45}ms`;
      card.append(el('div','avatar'+(c.gender==='female'?' female':c.gender==='other'?' other':''),initials(c.alias)));
      const who=el('div','who');who.append(el('div','name',titleCase(c.alias)));
      const meta=el('div','meta');meta.append(el('span','alias',c.alias),document.createTextNode(' · '+jobLabel(c.job,c.rank)));who.append(meta);
      const chips=el('div','chips');
      if(c.active)chips.append(el('span','chip last',state.mode==='switch'?'En uso':'Último usado'));
      if(c.dead)chips.append(el('span','chip dead','Herido · hospital'));
      if(c.duty)chips.append(el('span','chip duty','De servicio'));
      if(c.place)chips.append(el('span','chip',c.place));
      const seen=ago(c.lastSeen);if(seen)chips.append(el('span','chip',seen));
      if(chips.children.length)who.append(chips);
      card.append(who);
      const m=el('div','money');m.append(el('div','cash',money.format(c.cash||0)),el('div','bank','Banco $'+money.format(c.bank||0)));card.append(m);
      card.addEventListener('click',()=>select(c.alias));
      card.addEventListener('dblclick',()=>{select(c.alias);choose();});
      list.append(card);
    });
    const keep=state.characters.find(c=>c.alias===selected);
    select(keep?selected:(state.characters[0]&&state.characters[0].alias),false);
  }
  function open(data){
    state={open:true,mode:data.mode==='switch'?'switch':'connect',characters:Array.isArray(data.characters)?data.characters:[],allowCreate:!!data.allowCreate,maxCharacters:Number(data.maxCharacters)||1};
    root.classList.remove('hidden');root.classList.toggle('switch',state.mode==='switch');document.body.classList.add('selecting');
    $('selTitle').textContent=state.mode==='switch'?'Cambiar de personaje':'Elige tu personaje';
    $('selSubtitle').textContent=state.mode==='switch'?'Tu posición actual se guarda antes del cambio.':'Personajes asociados a tu cuenta';
    closeBtn.classList.toggle('hidden',state.mode!=='switch');
    toggleCreate(false);setBusy(false);render();
    setMessage(data.message||'',data.message?'ok':'');
  }
  function hide(){state.open=false;root.classList.add('hidden');document.body.classList.remove('selecting');toggleCreate(false);setBusy(false);}
  function choose(){
    if(enter.disabled||!selected)return;
    setBusy(true);setMessage(state.mode==='switch'?'Cambiando de personaje…':'Entrando…');post('selectCharacter',{alias:selected});
  }
  function toggleCreate(on){
    creating=on;create.classList.toggle('hidden',!on);
    if(on){first.value='';last.value='';updateAlias();setMessage('');setTimeout(()=>first.focus(),30);}
    refreshButtons();
  }
  function updateAlias(){
    const a=clean(first.value),b=clean(last.value);
    aliasHint.textContent='alias: '+(a||b?`${a||'nombre'}_${b||'apellido'}`:'—');
    $('selCreateBtn').disabled=busy||a.length<2||b.length<2;
  }
  enter.addEventListener('click',choose);
  newBtn.addEventListener('click',()=>toggleCreate(true));
  $('selCancel').addEventListener('click',()=>toggleCreate(false));
  closeBtn.addEventListener('click',()=>post('selectClose'));
  first.addEventListener('input',updateAlias);last.addEventListener('input',updateAlias);
  create.addEventListener('submit',e=>{
    e.preventDefault();
    const a=clean(first.value),b=clean(last.value);
    if(a.length<2||b.length<2||a.length>16||b.length>16){setMessage('Nombre y apellido: de 2 a 16 letras cada uno.','error');return;}
    setBusy(true);setMessage('Creando personaje…');post('createCharacter',{first:a,last:b});
  });
  window.addEventListener('keydown',e=>{
    if(!state.open)return;
    if(e.key==='Escape'){if(creating){toggleCreate(false);}else if(state.mode==='switch'){post('selectClose');}return;}
    if(creating||busy)return;
    const i=state.characters.findIndex(c=>c.alias===selected);
    if(e.key==='ArrowDown'||e.key==='ArrowUp'){
      e.preventDefault();const n=state.characters.length;if(!n)return;
      const next=(i+(e.key==='ArrowDown'?1:-1)+n)%n;select(state.characters[next].alias,true);
    }else if(e.key==='Enter'){e.preventDefault();choose();}
  });
  window.addEventListener('message',event=>{
    const data=event.data;if(!data)return;
    if(data.action==='select'){data.open?open(data):hide();}
    else if(data.action==='selectError'&&state.open){setBusy(false);updateAlias();setMessage(data.message,'error');}
    else if(data.action==='selectBusy'&&state.open){setBusy(true);}
  });
  post('selectReady');
})();
