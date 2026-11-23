-- Sugerencias del chat (/ + nombre) con ayuda y parametros. Los permisos se siguen comprobando en el servidor.
local P=function(name,help) return {name=name,help=help} end
local DEST='idJugador, alias o char:ID'
local SUGGESTIONS={
    {'/dinero','Muestra tu dinero en mano, banco y empleo',{}},
    {'/misbienes','Lista tus vehiculos, negocios y propiedades',{}},
    {'/mispropiedades','Resumen de tus bienes',{}},
    {'/hud','Muestra u oculta el HUD de ID y dinero',{}},
    {'/pagar','Paga efectivo a otro personaje',{P('destino',DEST),P('cantidad','Dinero en mano a enviar')}},
    {'/ceder','Cede el vehiculo que conduces',{P('destino',DEST)}},
    {'/darllaveprop','Da una copia de la llave de tu propiedad',{P('idPropiedad','Numero de la propiedad'),P('destino',DEST)}},
    {'/darllaveh','Da una copia de la llave-tarjeta de tu vehiculo',{P('idVehiculo','ID del vehiculo (/misbienes)'),P('destino',DEST)}},
    {'/darllavenegocio','Da una copia de la llave de tu negocio',{P('idNegocio','ID del negocio'),P('destino',DEST)}},
    {'/quitarllaveprop','Cambia la cerradura de tu propiedad: las copias dejan de servir',{P('idPropiedad','Numero de la propiedad')}},
    {'/quitarllaveh','Cambia la cerradura de tu vehiculo: las copias dejan de servir',{P('idVehiculo','ID del vehiculo')}},
    {'/quitarllavenegocio','Cambia la cerradura de tu negocio: las copias dejan de servir',{P('idNegocio','ID del negocio')}},
    {'/llave','[admin] Da la llave de un bien a un personaje',{P('tipo','propiedad, negocio o vehiculo'),P('id','ID del bien'),P('destino',DEST)}},
    {'/negocio','Menu de tus negocios: rangos, plantilla y contratar',{}},
    {'/trabajo','Tu trabajo publico (policia, sheriff, FIB, bomberos, EMS): rangos, sueldos y plantilla',{}},
    {'/puntotrabajo','[admin] Anade un punto de servicio de un trabajo publico aqui',{P('job','police, sheriff, fib, fire o ems'),P('nombre','Nombre del punto (opcional)')}},
    {'/negociojob','(admin) Pone el job de un negocio',{P('idNegocio','ID del negocio'),P('job','Nombre del job')}},
    {'/personaje','Sin argumentos lista tus personajes; con uno, lo selecciona',{P('personaje','alias o char:ID (opcional)')}},
    {'/personajes','Abre el selector para cambiar de personaje o crear uno nuevo',{}},
    {'/disenarpj','Abre el disenador de aspecto del personaje (cara, pelo y ropa)',{}},
    {'/guardarpos','Guarda tu posicion actual',{}},
    {'/ultimaubicacion','Muestra tus ultimas posiciones guardadas',{}},
    {'/guardarropa','Guarda la ropa y el aspecto actuales en tu personaje',{}},
    {'/setmoney','[admin] Fija el saldo',{P('destino',DEST),P('cantidad','Importe'),P('cuenta','cash o bank (opcional)')}},
    {'/givemoney','[admin] Anade dinero',{P('destino',DEST),P('cantidad','Importe'),P('cuenta','cash o bank (opcional)')}},
    {'/removemoney','[admin] Retira dinero',{P('destino',DEST),P('cantidad','Importe'),P('cuenta','cash o bank (opcional)')}},
    {'/setjob','[admin] Asigna empleo y rango',{P('destino',DEST),P('job','Empleo'),P('rango','Rango')}},
    {'/setduty','[admin] Entra o sale de servicio',{P('destino',DEST),P('estado','on u off')}},
    {'/crearpropiedad','[admin] Crea una propiedad en tu posicion',{P('numero','ID de la propiedad'),P('precio','Precio')}},
    {'/crearnegocio','[admin] Crea un negocio en tu posicion',{P('tipo','bar, ltd, discoteca, seguridad, medico, restaurante, compraventa'),P('nombre','Una o varias palabras'),P('precio','Precio')}},
    {'/borrarpropiedad','[admin] Borra una propiedad (y sus armarios)',{P('id','ID de la propiedad'),P('confirmar','escribe confirmar para borrarla')}},
    {'/borrarnegocio','[admin] Borra un negocio o una faccion',{P('id','ID del negocio'),P('confirmar','escribe confirmar para borrarlo')}},
    {'/borrarvehiculo','[admin] Borra un vehiculo creado (sin nada: en el que estas)',{P('vehiculo','ID o matricula (opcional)'),P('confirmar','escribe confirmar para borrarlo')}},
    {'/crearvehiculo','[admin] Crea un vehiculo delante de ti',{P('modelo','Nombre del modelo'),P('color1','0-159'),P('color2','0-159 (opcional)'),P('modo','temporal o fijo (opcional)'),P('destino',DEST..' (opcional)')}},
    {'/setpropiedad','[admin] Asigna una propiedad',{P('numero','ID'),P('destino',DEST)}},
    {'/setnegocio','[admin] Asigna un negocio',{P('id','ID'),P('destino',DEST)}},
    {'/setvehiculo','[admin] Asigna un vehiculo',{P('id','ID'),P('destino',DEST)}},
    {'/recuperarvehiculo','[admin] Recupera un vehiculo registrado delante de ti',{P('id','ID')}},
    {'/setcolor','[admin] Cambia el color del vehiculo que conduces',{P('color1','0-159'),P('color2','0-159 (opcional)')}},
    {'/setcar','[staff] reparar | livery | gas | negocio | faccion',{P('opcion','reparar, livery, gas, negocio o faccion'),P('valor','segun la opcion'),P('vehiculo','ID o matricula (vacio: el tuyo)')}},
    {'/setlivery','[admin] Cambia la livery del vehiculo que conduces',{P('indice','Numero'),P('tipo','native o mod48 (opcional)')}},
    {'/listliveries','[admin] Liveries del vehiculo que conduces',{}},
    {'/listvehiculos','[admin] Lista vehiculos',{}},
    {'/listnegocios','[admin] Lista negocios',{}},
    {'/listpropiedades','[admin] Lista propiedades',{}},
    {'/infovehiculo','[admin] Datos de un vehiculo',{P('id','ID')}},
    {'/infonegocio','[admin] Datos de un negocio',{P('id','ID')}},
    {'/infopropiedad','[admin] Datos de una propiedad',{P('numero','ID')}},
    {'/verpropiedades','[admin] Bienes de un personaje',{P('destino',DEST)}},
    {'/crearpersonaje','[admin] Crea un personaje para una cuenta',{P('idJugador','Jugador conectado'),P('alias','Alias nuevo')}},
    {'/seleccionarpersonaje','[admin] Selecciona un personaje de esa cuenta',{P('idJugador','Jugador conectado'),P('personaje','alias o char:ID')}},
    {'/vincularpersonaje','[admin] Vincula un personaje heredado',{P('idJugador','Jugador conectado'),P('personaje','alias o char:ID'),P('confirmar','CONFIRMAR')}},
    {'/importarropa','[admin] Importa un XML de Menyoo desde data/',{P('destino',DEST),P('archivo','Nombre sin .xml')}},
    {'/setspawn','[admin] Fija la proxima aparicion en tu posicion',{P('destino',DEST)}},
    {'/tpusuario','[admin] Te lleva junto a un jugador',{P('idJugador','Jugador conectado')}},
    {'/policianpc','Estado; [admin] on u off activa o desactiva la policia NPC',{P('estado','on u off (opcional)')}},
    {'/npcs','Estado; [admin] on u off activa o desactiva peatones y trafico',{P('estado','on u off (opcional)')}},
    {'/ospermisos','Diagnostico de tus permisos',{}},
    {'/oscomandos','Lista de comandos de os_devtools',{}}
}
-- Con el HUD de Devtools apagado (setr osdev_hud false), /hud es de otro recurso (Oxide HUD).
if GetConvar('osdev_hud','true')=='false' then
    for i=#SUGGESTIONS,1,-1 do if SUGGESTIONS[i][1]=='/hud' then table.remove(SUGGESTIONS,i) end end
end
CreateThread(function()
    for _,s in ipairs(SUGGESTIONS) do TriggerEvent('chat:addSuggestion',s[1],s[2],s[3]) end
end)
AddEventHandler('onClientResourceStop',function(name)
    if name~=GetCurrentResourceName() then return end
    for _,s in ipairs(SUGGESTIONS) do TriggerEvent('chat:removeSuggestion',s[1]) end
end)
