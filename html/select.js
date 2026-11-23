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

  // Asiento estable a partir del ID del personaje (oschar_0000000003 -> 3C) y codigo de barras por alias.
  const seat=id=>{const n=Number(String(id||'').replace(/\D/g,''))||0;return `${n%30+1}${'ABCDEF'[n%6]}`;};
  const barcode=text=>{let h=7,x=0,stops=[];for(const ch of String(text))h=(h*31+ch.charCodeAt(0))>>>0;
    while(x<100){h=(h*1103515245+12345)>>>0;const w=1+(h>>>16)%3,gap=1+(h>>>8)%3;stops.push(`#000 ${x}% ${x+w}%`,`transparent ${x+w}% ${x+w+gap}%`);x+=w+gap;}
    return `linear-gradient(90deg,${stops.join(',')})`;};
  const plate={root:$('selPlate'),kicker:$('plateKicker'),name:$('plateName'),job:$('plateJob')};
  function showPlate(c){
    if(!c||state.mode!=='connect'){plate.root.classList.add('hidden');return;}
    plate.kicker.textContent=c.dead?'Herido · aparecerá en el hospital':c.active?'Último viaje':'Pasajero';
    plate.name.textContent=titleCase(c.alias);plate.job.textContent=jobLabel(c.job,c.rank);
    plate.root.classList.remove('hidden');plate.root.style.animation='none';void plate.root.offsetWidth;plate.root.style.animation='';
  }
  function setMessage(text,kind){msg.textContent=text||'';msg.className='sel-message'+(kind?' '+kind:'');}
  function setBusy(value){busy=value;root.classList.toggle('busy',value);refreshButtons();}
  function refreshButtons(){
    const chosen=state.characters.find(c=>c.alias===selected);
    enter.disabled=busy||!chosen||(state.mode==='switch'&&chosen.active);
    enter.textContent=state.mode==='switch'?(chosen&&chosen.active?'En uso':'Cambiar'):'Embarcar';
    const full=state.characters.length>=state.maxCharacters;
    newBtn.classList.toggle('hidden',!state.allowCreate||creating);
    newBtn.disabled=busy||full;
    count.textContent=`${state.characters.length}/${state.maxCharacters} pasajeros`+(full&&state.allowCreate?' · completo':'');
  }
  function select(alias,scroll){
    const changed=selected!==alias;selected=alias;
    // Al entrar, el cliente muestra al personaje en la escena (ped local con su aspecto).
    if(changed&&alias&&state.mode==='connect')post('selectPreview',{alias});
    if(changed)showPlate(state.characters.find(c=>c.alias===alias));
    for(const card of list.children){const on=card.dataset.alias===alias;card.classList.toggle('selected',on);card.setAttribute('aria-selected',on);if(on&&scroll)card.scrollIntoView({block:'nearest'});}
    refreshButtons();
  }
  function render(){
    list.replaceChildren();
    if(!state.characters.length){list.append(el('div','empty',state.allowCreate?'Aún no tienes personajes. Crea el primero.':'No hay personajes en esta cuenta.'));}
    state.characters.forEach((c,i)=>{
      const card=el('div','pass'+(c.dead?' dead':''));card.dataset.alias=c.alias;card.setAttribute('role','option');card.style.animationDelay=`${i*60}ms`;
      const main=el('div','pass-main');
      main.append(el('div','pass-label','Pasajero'));
      const name=el('div','pass-name',titleCase(c.alias));name.append(el('span','pass-alias',c.alias));main.append(name);
      const fields=el('div','pass-fields');
      [['Ocupación',jobLabel(c.job,c.rank)],['Último destino',c.place||'—'],['Último vuelo',ago(c.lastSeen)||'—']].forEach(([label,value])=>{
        const f=el('div');f.append(el('div','pass-label',label),el('div','v',value));fields.append(f);});
      main.append(fields);
      const stamps=el('div','stamps');
      if(c.active)stamps.append(el('span','stamp last',state.mode==='switch'?'En uso':'Último viaje'));
      if(c.dead)stamps.append(el('span','stamp dead','Herido · hospital'));
      if(c.duty)stamps.append(el('span','stamp duty','De servicio'));
      if(stamps.children.length)main.append(stamps);
      const stub=el('div','pass-stub');
      const top=el('div');top.append(el('div','pass-label','Asiento'),el('div','seat',seat(c.characterId)));
      const cash=el('div');cash.append(el('div','cash','$'+money.format(c.cash||0)),el('div','bank','Banco $'+money.format(c.bank||0)));
      const code=el('div','barcode');code.style.backgroundImage=barcode(c.alias);
      stub.append(top,cash,code);
      card.append(main,stub);
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
    $('selTitle').textContent=state.mode==='switch'?'Cambiar de pasajero':'¿Con quién viajas hoy?';
    $('selSubtitle').textContent=state.mode==='switch'?'Tu posición actual se guarda antes del cambio.':'Elige una tarjeta de embarque: son los personajes de tu cuenta.';
    selected=null;
    closeBtn.classList.toggle('hidden',state.mode!=='switch');
    toggleCreate(false);setBusy(false);render();
    setMessage(data.message||'',data.message?'ok':'');
  }
  function hide(){state.open=false;plate.root.classList.add('hidden');root.classList.add('hidden');document.body.classList.remove('selecting');toggleCreate(false);setBusy(false);}
  function choose(){
    if(enter.disabled||!selected)return;
    setBusy(true);setMessage(state.mode==='switch'?'Cambiando de pasajero…':'Embarcando…');post('selectCharacter',{alias:selected});
  }
  function toggleCreate(on){
    creating=on;create.classList.toggle('hidden',!on);
    if(on){first.value='';last.value='';$('selXml').value='';document.querySelector('input[name=selMode][value=design]').checked=true;$('selXml').classList.add('hidden');updateAlias();setMessage('');setTimeout(()=>first.focus(),30);}
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
  document.querySelectorAll('input[name=selMode]').forEach(r=>r.addEventListener('change',()=>{$('selXml').classList.toggle('hidden',r.value!=='xml'||!r.checked);}));
  create.addEventListener('submit',e=>{
    e.preventDefault();
    const a=clean(first.value),b=clean(last.value);
    if(a.length<2||b.length<2||a.length>16||b.length>16){setMessage('Nombre y apellido: de 2 a 16 letras cada uno.','error');return;}
    const xmlMode=document.querySelector('input[name=selMode]:checked')?.value==='xml';const xml=$('selXml').value.trim();
    if(xmlMode&&!xml.includes('<OutfitPedData')){setMessage('Pega un XML de Menyoo (debe contener OutfitPedData).','error');return;}
    if(xml.length>65536){setMessage('El XML es demasiado grande.','error');return;}
    setBusy(true);setMessage(xmlMode?'Creando personaje con el XML…':'Creando personaje…');post('createCharacter',xmlMode?{first:a,last:b,xml}:{first:a,last:b});
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
