(()=>{
  // Concesionario: catalogo con precio, color y forma de pago. El servidor valida la compra.
  const res=typeof GetParentResourceName==='function'?GetParentResourceName():'os_devtools';
  const post=(n,b={})=>fetch(`https://${res}/${n}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b)}).catch(()=>{});
  const el=(t,c,x)=>{const n=document.createElement(t);if(c)n.className=c;if(x!=null)n.textContent=x;return n;};
  // Zona libre de la pantalla para mover la camara de la vista previa (arrastrar: girar y altura; rueda: zoom).
  const drag=document.createElement('div');drag.className='dealer-drag hidden';drag.append(Object.assign(document.createElement('span'),{textContent:'Arrastra para girar la cámara · arriba y abajo cambia la altura · rueda para acercar'}));document.body.append(drag);
  const root=document.createElement('section');root.className='biz hidden';root.setAttribute('aria-label','Concesionario');document.body.append(root);
  let dragging=null,pending={dx:0,dy:0},sending=false;
  const flush=()=>{if(sending||(!pending.dx&&!pending.dy))return;sending=true;const b=pending;pending={dx:0,dy:0};post('dealerCamera',b).finally(()=>{sending=false;flush();});};
  drag.addEventListener('pointerdown',e=>{dragging={x:e.clientX,y:e.clientY};drag.setPointerCapture(e.pointerId);drag.classList.add('grab');});
  drag.addEventListener('pointermove',e=>{if(!dragging)return;pending.dx+=e.clientX-dragging.x;pending.dy+=e.clientY-dragging.y;dragging={x:e.clientX,y:e.clientY};flush();});
  const stop=()=>{dragging=null;drag.classList.remove('grab');};drag.addEventListener('pointerup',stop);drag.addEventListener('pointercancel',stop);
  drag.addEventListener('wheel',e=>{e.preventDefault();post('dealerCamera',{wheel:e.deltaY<0?1:-1});},{passive:false});
  // Colores de la paleta de GTA (aproximados) para la muestra.
  const SWATCH={0:'#0d1116',1:'#1c1d21',4:'#545b62',27:'#c00e1a',38:'#f78616',55:'#4d8b3e',64:'#47578f',88:'#ffcf20',111:'#ffffff',112:'#c1c1c1'};
  let data=null,color=null,msg=null,pick=null,account='cash';
  // Vista previa en el juego: el modelo marcado y el color elegido.
  const preview=()=>{if(data&&pick)post('dealerPreview',{model:pick,color});};
  const money=n=>'$'+Number(n||0).toLocaleString('es-ES');
  function render(){
    root.replaceChildren();if(!data)return;
    root.classList.toggle('side',!!data.preview);drag.classList.toggle('hidden',!data.preview);
    const head=el('div','biz-head');const t=el('div');t.append(el('h1',null,data.label),el('p',null,'Toca un vehículo para verlo y elige el color. Sale a tu nombre, con su llave, en el punto de entrega.'));
    const x=el('button',null,'ESC ×');x.addEventListener('click',close);head.append(t,x);root.append(head);
    const opts=el('div','biz-summary');
    const colors=el('div','biz-stat');colors.append(el('small',null,'Color'));const sw=el('div');sw.style.cssText='display:flex;gap:6px;flex-wrap:wrap;margin-top:4px';
    for(const c of data.colors||[]){const b=el('button');b.style.cssText=`width:26px;height:26px;padding:0;border-radius:50%;background:${SWATCH[c]||'#777'};border:2px solid ${c===color?'#7fc98e':'rgba(255,255,255,.2)'}`;b.title=`Color ${c}`;b.addEventListener('click',()=>{color=c;render();preview();});sw.append(b);}
    colors.append(sw);
    const pay=el('div','biz-stat');pay.append(el('small',null,'Pagar con'));const sel=el('select');[['cash','Efectivo'],['bank','Tarjeta']].forEach(([v,l])=>{const o=el('option',null,l);o.value=v;sel.append(o);});sel.value=account;sel.addEventListener('change',()=>{account=sel.value;});pay.append(sel);
    opts.append(colors,pay,el('div','biz-stat'));root.append(opts);
    const list=el('div','biz-card');list.append(el('h2',null,'Catálogo'));
    for(const v of data.catalog||[]){const row=el('div','person dealer-row'+(v.model===pick?' sel':''));row.append(el('span','who',v.label),el('b',null,money(v.price)));
      row.addEventListener('click',()=>{if(pick===v.model)return;pick=v.model;msg=null;render();preview();});
      const buy=el('button','primary','Comprar');buy.addEventListener('click',e=>{e.stopPropagation();const pay=account;if(pick!==v.model){pick=v.model;preview();}msg={text:'Procesando…'};render();post('dealerBuy',{model:v.model,color,account:pay,price:Number(v.price).toLocaleString('es-ES')});});
      row.append(buy);list.append(row);}
    root.append(list);
    root.append(el('div','biz-msg'+(msg?.kind?' '+msg.kind:''),msg?.text||''));
  }
  // Panel de administracion: un concesionario por pestaña; precio editable por modelo, añadir, quitar y mover puntos.
  let adminData=null,adminId=null,adminMsg=null;
  function renderAdmin(){
    root.replaceChildren();if(!adminData)return;
    const list=adminData.dealers||[];if(!list.some(d=>d.id===adminId))adminId=list[0]?.id;
    const head=el('div','biz-head');const t=el('div');t.append(el('h1',null,'Concesionarios'),el('p',null,'Precios, modelos y puntos. Los cambios se guardan al momento.'));
    const x=el('button',null,'ESC ×');x.addEventListener('click',close);head.append(t,x);root.append(head);
    const tabs=el('div','biz-tabs');for(const d of list){const b=el('button',d.id===adminId?'on':null,d.label);b.addEventListener('click',()=>{adminId=d.id;renderAdmin();});tabs.append(b);}root.append(tabs);
    const d=list.find(v=>v.id===adminId);if(!d)return;
    const act=(op,a,b,c)=>post('dealerAdmin',{op,id:d.id,a,b,c});
    const pts=el('div','biz-card');pts.append(el('h2',null,'Puntos'));
    const prow=el('div','hire-foot');const b1=el('button',null,'Mover el mostrador aquí');b1.addEventListener('click',()=>act('counter'));const b2=el('button',null,'Mover la entrega aquí');b2.addEventListener('click',()=>act('delivery'));
    const b3=el('button',null,'Mover la vista previa aquí');b3.addEventListener('click',()=>act('preview'));
    prow.append(el('span',null,`Mostrador ${d.counter.x.toFixed(1)}, ${d.counter.y.toFixed(1)} · Entrega ${d.delivery.x.toFixed(1)}, ${d.delivery.y.toFixed(1)}`),b1,b2,b3);pts.append(prow);root.append(pts);
    const cat=el('div','biz-card');cat.append(el('h2',null,`Catálogo (${d.catalog.length})`));
    for(const v of d.catalog){const row=el('div','person');const who=el('span','who',v.label);who.append(el('small',null,v.model));
      const price=el('input');price.type='number';price.min='0';price.step='500';price.value=String(v.price);price.style.width='120px';
      price.addEventListener('change',()=>act('price',v.model,Number(price.value)));
      const rm=el('button','danger','Quitar');rm.addEventListener('click',()=>act('remove',v.model));
      row.append(who,el('span',null,'$'),price,rm);cat.append(row);}
    const add=el('div','biz-add');const m=el('input');m.placeholder='modelo (spawn)';const l=el('input');l.placeholder='Nombre visible';const p=el('input');p.type='number';p.placeholder='Precio';p.style.width='110px';
    const ab=el('button','primary','Añadir');ab.addEventListener('click',()=>act('add',m.value.trim(),l.value.trim(),Number(p.value)));add.append(m,l,p,ab);cat.append(add);
    root.append(cat);root.append(el('div','biz-msg'+(adminMsg?.kind?' '+adminMsg.kind:''),adminMsg?.text||''));
  }
  function close(){root.classList.add('hidden');root.classList.remove('side');drag.classList.add('hidden');data=null;adminData=null;pick=null;post('dealerClose');}
  window.addEventListener('message',e=>{const m=e.data;if(!m||typeof m!=='object')return;
    if(m.action==='dealer'){data=m.data;color=(data.colors||[])[0]??0;msg=null;account='cash';pick=(data.catalog||[])[0]?.model||null;root.classList.remove('hidden');render();preview();}
    else if(m.action==='dealerPreview'&&data&&m.ok===false){msg={text:'Ese modelo no está instalado en el servidor.',kind:'error'};render();}
    else if(m.action==='dealerAdmin'){adminData=m.data;data=null;drag.classList.add('hidden');adminMsg=m.message?{text:m.message,kind:m.kind}:null;root.classList.remove('hidden');renderAdmin();}
    else if(m.action==='dealerResult'&&data){msg={text:m.text||'',kind:m.ok?'success':'error'};render();}
  });
  window.addEventListener('keydown',e=>{if(e.key==='Escape'&&(data||adminData))close();});
})();
