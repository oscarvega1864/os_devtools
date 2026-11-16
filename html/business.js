(()=>{
  // Menu /negocio (os_devtools). Todo el texto por textContent; el servidor valida cada operacion.
  const res=typeof GetParentResourceName==='function'?GetParentResourceName():'os_devtools';
  const post=(name,body={})=>fetch(`https://${res}/${name}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}).catch(()=>{});
  const el=(tag,cls,text)=>{const n=document.createElement(tag);if(cls)n.className=cls;if(text!=null)n.textContent=text;return n;};
  const root=document.getElementById('business'),invite=document.getElementById('businessInvite');
  let data=null,current=null,timer=null,lastMessage=null;
  const nice=alias=>String(alias||'').replace(/_/g,' ');
  const initials=alias=>String(alias||'?').split('_').map(p=>p[0]||'').join('').slice(0,2);
  function button(text,cls,fn,disabled,title){const b=el('button',cls,text);b.type='button';b.disabled=!!disabled;if(title)b.title=title;b.addEventListener('click',fn);return b;}
  function select(options,value){const s=el('select');for(const o of options){const op=el('option',null,o.label);op.value=o.value;s.append(op);}if(value!=null)s.value=value;return s;}
  function stat(label,value,cls){const box=el('div','biz-stat');box.append(el('small',null,label),el('b',cls||null,value));return box;}
  function card(title,extra){const c=el('section','biz-card');const h=el('h2',null,title);if(extra!=null)h.append(el('span',null,extra));c.append(h);return c;}

  function render(message,kind){
    if(message!==undefined)lastMessage={message,kind};
    root.replaceChildren();if(!data)return;
    const list=data.businesses||[];if(!list.some(b=>b.id===current))current=list[0]?.id??null;
    const head=el('div','biz-head');const titles=el('div');titles.append(el('h1',null,'Mis negocios'),el('p',null,'Estructura de rangos, plantilla y contrataciones'));
    head.append(titles,button('ESC ×',null,close));root.append(head);
    if(list.length>1){const tabs=el('div','biz-tabs');for(const b of list)tabs.append(button(b.name,b.id===current?'on':null,()=>{current=b.id;render();}));root.append(tabs);}
    const b=list.find(x=>x.id===current);
    if(!b){root.append(el('p','empty','No eres titular de ningun negocio.'));return;}

    const ready=!!b.job&&b.ranks.length>=data.minRanks;
    const summary=el('div','biz-summary');
    const salaries=b.salaries||{};const every=(data.payMinutes||60)===60?'hora':`${data.payMinutes} min`;const money=n=>'$'+Number(n||0).toLocaleString('es-ES');
    const payroll=b.staff.reduce((sum,s)=>sum+(Number(salaries[s.rank])||0),0);
    summary.append(stat('Job',b.job||'Sin asignar',b.job?'ok':'warn'),stat('Plantilla',`${b.staff.length} ${b.staff.length===1?'persona':'personas'}`),
      stat(`Nóminas por ${every}`,money(payroll)));
    root.append(summary);

    const grid=el('div','biz-grid');
    // Rangos: el 1 es el mas bajo; el ultimo, el mas alto.
    if(b.public)return renderPublic(b);
    const ranks=card('Rangos y sueldos',`${b.ranks.length}/${data.maxRanks} · de menor a mayor`);
    if(!b.ranks.length)ranks.append(el('p','empty','Todavia no hay rangos. Crea al menos '+data.minRanks+'.'));
    b.ranks.forEach((rank,i)=>{
      const row=el('div','rank');row.append(el('span','lvl',String(i+1)));
      const name=el('span','name',rank);if(i===b.ranks.length-1&&b.ranks.length>1)name.append(el('span','tag','más alto'));if(i===0&&b.ranks.length>1)name.append(el('span','tag','de entrada'));
      // Sueldo del rango: se guarda al salir del campo o con Enter.
      const pay=el('label','pay');const amount=el('input');amount.type='number';amount.min='0';amount.max=String(data.maxSalary||10000);amount.step='50';
      amount.value=String(Number(salaries[rank])||0);amount.title=`Sueldo por ${every} conectado (lo paga tu banco)`;
      const save=()=>{const n=Math.floor(Number(amount.value));if(!Number.isFinite(n)||n===(Number(salaries[rank])||0))return;post('businessSalary',{id:b.id,rank,amount:n});};
      amount.addEventListener('change',save);amount.addEventListener('keydown',e=>{if(e.key==='Enter')amount.blur();});
      pay.append(el('span',null,'$'),amount);
      const t=el('div','tools');
      t.append(button('↑','icon',()=>post('businessRank',{id:b.id,op:'move',name:rank,dir:'down'}),i===0,'Bajar de nivel'),
        button('↓','icon',()=>post('businessRank',{id:b.id,op:'move',name:rank,dir:'up'}),i===b.ranks.length-1,'Subir de nivel'),
        button('✕','icon danger',()=>post('businessRank',{id:b.id,op:'remove',name:rank}),false,'Borrar rango'));
      row.append(name,pay,t);ranks.append(row);
    });
    const add=el('div','biz-add');const input=el('input');input.placeholder='Nuevo rango, p. ej. empleado';input.maxLength=20;
    const doAdd=()=>{const v=input.value.trim();if(v)post('businessRank',{id:b.id,op:'add',name:v});};
    input.addEventListener('keydown',e=>{if(e.key==='Enter')doAdd();});
    add.append(input,button('Añadir','primary',doAdd,b.ranks.length>=data.maxRanks));ranks.append(add);
    ranks.append(el('p','note',`El sueldo se paga de tu banco al del empleado por cada ${every} que esté conectado con el job del negocio. Sin saldo, no se paga y os avisa a los dos.`));
    grid.append(ranks);

    const right=el('div');
    const staff=card('Plantilla',`${b.staff.length}`);
    const rankOptions=b.ranks.map(r=>({value:r,label:r}));
    if(!b.staff.length)staff.append(el('p','empty','Todavia no hay nadie contratado.'));
    for(const s of b.staff){
      const row=el('div','person');const who=el('span','who',nice(s.alias));who.append(el('small',null,money(salaries[s.rank])));row.append(el('span','avatar',initials(s.alias)),who);
      const sel=select(rankOptions,s.rank);sel.addEventListener('change',()=>post('businessStaff',{id:b.id,alias:s.alias,op:'rank',rank:sel.value}));
      row.append(sel,button('Despedir','danger',()=>post('businessStaff',{id:b.id,alias:s.alias,op:'fire'})));staff.append(row);
    }
    right.append(staff);

    const hire=card('Contratar');
    if(!ready){
      const reqs=el('ul','reqs');
      const req=(ok,text)=>{const li=el('li',ok?'ok':'no');li.append(el('i',null,ok?'✓':'!'),document.createTextNode(text));reqs.append(li);};
      req(!!b.job,b.job?`Job asignado: ${b.job}`:'El negocio necesita job: un administrador lo pone con /negociojob');
      req(b.ranks.length>=data.minRanks,`Al menos ${data.minRanks} rangos (tienes ${b.ranks.length})`);
      hire.append(reqs);
    } else {
      const players=data.players||[];
      if(!players.length){hire.append(el('p','empty','No hay nadie a menos de 5 m. Acércate a la persona y pulsa Actualizar.'));}
      else{
        const row=el('div','hire');const who=select(players.map(p=>({value:p.id,label:`${nice(p.name)} (${p.id})`})));const rank=select(rankOptions,b.ranks[0]);
        row.append(who,rank,button('Invitar','primary',()=>post('businessInvite',{id:b.id,target:Number(who.value),rank:rank.value})));hire.append(row);
      }
    }
    const foot=el('div','hire-foot');foot.append(el('span',null,'La persona recibe la oferta y la acepta o la rechaza.'),button('Actualizar',null,()=>post('businessRefresh')));
    // Punto de servicio: donde la plantilla ficha con E (la nomina solo cuenta de servicio).
    const duty=card('Punto de servicio');
    duty.append(el('p','empty',b.dutyPoint?'Puesto. La plantilla entra y sale de servicio con E en ese sitio; la nómina solo cuenta de servicio.':'Sin punto: tu plantilla no puede ponerse de servicio ni cobrar.'));
    duty.append(button(b.dutyPoint?'Moverlo aquí':'Poner punto de servicio aquí','primary',()=>post('businessDutyPoint',{id:b.id})));
    right.append(duty);
    hire.append(foot);right.append(hire);
    grid.append(right);root.append(grid);
    const msg=el('div','biz-msg'+(lastMessage?.kind?' '+lastMessage.kind:''),lastMessage?.message||'');root.append(msg);
  }
  // Trabajo publico: rangos y sueldos fijos (los paga el ayuntamiento); los mandos contratan, ascienden y despiden.
  function renderPublic(b){
    const money=n=>'$'+Number(n||0).toLocaleString('es-ES');const myIndex=b.ranks.indexOf(b.myRank);
    const grid=el('div','biz-grid');const ranks=card('Rangos y sueldo por hora',`${b.ranks.length} · de menor a mayor`);
    b.ranks.forEach((r,i)=>{const row=el('div','rank');row.append(el('span','lvl',String(i+1)));const name=el('span','name',r);if(r===b.myRank)name.append(el('span','tag','tú'));
      row.append(name,el('span','pay',money(b.salaries[r])));ranks.append(row);});
    ranks.append(el('p','note','El sueldo lo paga el ayuntamiento por cada hora de servicio (ficha en tu sede con E).'));
    grid.append(ranks);const right=el('div');const staff=card('Plantilla',`${b.staff.length}`);
    for(const s of b.staff){const row=el('div','person');row.append(el('span','avatar',initials(s.alias)),el('span','who',nice(s.alias)));
      const index=b.ranks.indexOf(s.rank);
      if(b.boss&&index<myIndex){const sel=select(b.ranks.slice(0,myIndex).map(r=>({value:r,label:r})),s.rank);sel.addEventListener('change',()=>post('businessStaff',{id:b.id,alias:s.alias,op:'rank',rank:sel.value}));
        row.append(sel,button('Despedir','danger',()=>post('businessStaff',{id:b.id,alias:s.alias,op:'fire'})));}
      else row.append(el('span','tag',s.rank));
      staff.append(row);}
    right.append(staff);
    if(b.boss){const hire=card('Contratar');const players=data.players||[];
      if(!players.length)hire.append(el('p','empty','No hay nadie a menos de 5 m. Acércate y pulsa Actualizar.'));
      else{const row=el('div','hire');const who=select(players.map(p=>({value:p.id,label:`${nice(p.name)} (${p.id})`})));const rank=select(b.ranks.slice(0,myIndex).map(r=>({value:r,label:r})),b.ranks[0]);
        row.append(who,rank,button('Invitar','primary',()=>post('businessInvite',{id:b.id,target:Number(who.value),rank:rank.value})));hire.append(row);}
      const foot=el('div','hire-foot');foot.append(el('span',null,'Solo puedes contratar en rangos por debajo del tuyo.'),button('Actualizar',null,()=>post('businessRefresh')));hire.append(foot);right.append(hire);}
    grid.append(right);root.append(grid);
    root.append(el('div','biz-msg'+(lastMessage?.kind?' '+lastMessage.kind:''),lastMessage?.message||''));
  }
  function close(){root.classList.add('hidden');lastMessage=null;post('businessClose');}
  function showInvite(d){
    invite.replaceChildren();clearTimeout(timer);
    const p=el('p');p.append(document.createTextNode(`${nice(d.from)} te ofrece trabajar en `),el('b',null,d.business),document.createTextNode(' como '),el('b',null,d.rank),document.createTextNode('.'));
    invite.append(p);
    const row=el('div','row');const answer=accept=>{clearTimeout(timer);invite.classList.add('hidden');post('businessAnswer',{accept});};
    row.append(button('Aceptar','primary',()=>answer(true)),button('Rechazar',null,()=>answer(false)));invite.append(row);
    let left=Number(d.seconds)||30;const small=el('small',null,`Caduca en ${left} s`);invite.append(small);
    invite.classList.remove('hidden');
    const tick=()=>{left--;if(left<=0)return answer(false);small.textContent=`Caduca en ${left} s`;timer=setTimeout(tick,1000);};timer=setTimeout(tick,1000);
  }
  window.addEventListener('message',e=>{const m=e.data;if(!m||typeof m!=='object')return;
    if(m.action==='business'){root.classList.toggle('hidden',!m.open);if(m.open)lastMessage=null;return;}
    if(m.action==='businessData'){data=m.data;render(m.message||'',m.kind);}
    else if(m.action==='businessInvite')showInvite(m.data||{});
  });
  window.addEventListener('keydown',e=>{if(e.key==='Escape'&&!root.classList.contains('hidden'))close();});
})();
