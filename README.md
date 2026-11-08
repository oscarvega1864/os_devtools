# OS Devtools 0.1.3

Herramientas standalone para GTA V Legacy / FXServer local: identidad, economía de pruebas, empleos, activos, HUD, posiciones y respawn. No necesita frameworks ni inventario. La autorización OSCAR del hotfix se conserva: ser administrador txAdmin no concede automáticamente permisos ACE.

## Identidad y destinatarios

Se distinguen conexión temporal, cuenta nativa verificada, ID persistente `oschar_0000000001` y alias único. El ID del personaje no cambia al reconectar con otro server ID. Se conservan los alias y las titularidades existentes. El HUD muestra ID de conexión y efectivo del personaje activo; `/hud` conserva su preferencia mediante KVP.

La identidad inicial es automática. **`/setpj` permanece retirado por la instrucción posterior de identidad automática**; `/setuser` conserva únicamente el aviso informativo. La gestión explícita usa estos comandos:

| Comando | Acceso y efecto |
| --- | --- |
| `/personaje` | Personal: lista personajes propios y sus IDs. |
| `/personaje <alias\|char:ID>` | Selecciona un personaje de la misma cuenta; guarda primero la posición anterior. |
| `/crearpersonaje <idJugador> <alias>` | `osdev.identity`: crea un personaje para esa cuenta; no sustituye al activo si ya existe. |
| `/seleccionarpersonaje <idJugador> <alias\|char:ID>` | `osdev.identity`: selecciona un personaje ya perteneciente a la cuenta. |
| `/vincularpersonaje <idJugador> <alias\|char:ID> CONFIRMAR` | `osdev.identity`: vincula un personaje heredado sin propietario; registra la intervención. No reasigna personajes de otra cuenta. |

Un personaje heredado sin cuenta no se entrega al primero que conecte. Se bloquea la creación automática de identidades nuevas mientras queden personajes heredados sin vincular, para evitar inventarios vacíos sustitutos. Revisar su propietario y vincular explícitamente, o crear de forma administrativa un personaje nuevo. Una asociación a otra cuenta exige una migración auditada específica; no hay comando de apropiación.

Todos los destinatarios comunes aceptan `2` (jugador conectado), `oscar_vega` o `alias:oscar_vega` (personaje registrado) y `char:oschar_0000000001` (ID persistente explícito). Un número desnudo siempre es conexión; para un alias numérico usar `alias:123`. No se crean destinatarios por errores de escritura. En `/setvehiculo 1 2`, el primer número es el vehículo y el segundo, el jugador.

## Comandos conservados

| Área / permiso efectivo | Comandos |
| --- | --- |
| Personal | `/dinero`, `/misbienes`, `/mispropiedades`, `/hud`, `/pagar <destinatario> <cantidad>`, `/ceder <destinatario>` estando al volante del vehículo propio. |
| `osdev.economy` | `/setmoney <destino> <cantidad> [cash\|bank]`, `/givemoney ...`, `/removemoney ...`. |
| `osdev.jobs` | `/setjob <destino> <job> <rango>`, `/setduty <destino> on\|off`. |
| `osdev.assets` | `/crearpropiedad <numero> <precio>`, `/crearnegocio <tipo> <nombre> <precio>`, `/crearvehiculo <modelo> <color1> [color2] [temporal\|fijo] [destino]`. |
| `osdev.assets` | `/setpropiedad <idBien> <destino>`, `/setnegocio ...`, `/setvehiculo ...`, `/recuperarvehiculo <id>`, `/setcolor <color1> [color2]`, `/setlivery <índice> [native\|mod48]`, `/listliveries`. |
| `osdev.inspect` | `/verpropiedades <destino>`, `/listvehiculos`, `/listnegocios`, `/listpropiedades`, `/infovehiculo <id>`, `/infonegocio <id>`, `/infopropiedad <id>`. |
| Diagnóstico | `/oscomandos`, `/ospermisos`. |

`osdev.admin` autoriza todas las categorías Devtools. Los perfiles OSCAR permiten separar identidad, economía, empleos, activos y consultas. [Autorización y operación de txAdmin](docs/authorization.md).

Ejemplos: `/setmoney 2 5000 bank`, `/setjob oscar_vega gruppe6 vigilante`, `/setpropiedad 200 2`, `/pagar 2 50`. Los pagos transfieren efectivo entre personajes distintos; no admiten negativos, exceso de fondos o desbordamiento. La asignación administrativa de bienes no cobra sus precios.

Los comandos físicos utilizan la posición del administrador; el destinatario solo decide la titularidad. Los vehículos siguen generándose mediante cliente autorizado, con colores, liveries, matrícula e ID del registro. La recuperación bloquea peticiones simultáneas del mismo registro. Sus registros, incluidos los temporales, se conservan sin reciclar IDs; las entidades temporales conocidas se retiran al detener el recurso. Los fijos no reaparecen automáticamente tras reiniciar. Un servidor con entity lockdown estricto necesita un adaptador de creación autorizado desde servidor.

## Mensajes

- Confirmaciones, errores y avisos cortos se muestran como notificación compacta si `os_notify` está iniciado (éxito, error, aviso o información); si no, en el chat. No es una dependencia obligatoria.
- Listados y diagnósticos (`/misbienes`, `/oscomandos`, `/ospermisos`, `/list*`, `/info*`, `/personaje`, `/ultimaubicacion`, `/dinero`) van siempre al chat.
- Todos los comandos tienen sugerencia con ayuda y parámetros al escribir `/` (`client/suggestions.lua`).

## Propiedades y negocios

- `/crearpropiedad <numero> <precio>`: el administrador elige el número; se guardan precio, coordenadas exactas y heading, sin nombre, tipo ni propietario. Etiqueta visible `Propiedad #200`. Un número existente se rechaza con `La propiedad ID 200 ya existe.` Las propiedades antiguas conservan su tipo y nombre.
- `/crearnegocio <tipo> <nombre> <precio>`: ID automático, sin propietario. Tipos: `bar`, `ltd`, `discoteca`, `seguridad`, `medico`, `restaurante`, `compraventa`. El nombre admite varias palabras (3–40 caracteres, sin `~`, `<`, `>`). Ejemplo: `/crearnegocio ltd LTD Mirror Park 30000`.
- `/setpropiedad <numero> <destino>` y `/setnegocio <id> <destino>` asignan el titular.
- Cada negocio de un tipo conocido tiene un blip con su nombre; sprite y color por categoría en `config/business.lua`. Los blips se envían al entrar y solo cuando cambian los negocios; el cliente mantiene uno por ID, sin duplicados al reconectar.

## Vehículos

Requiere OneSync. El servidor crea todos los vehículos de Devtools con `CREATE_VEHICLE_SERVER_SETTER`; ninguno depende de un network ID guardado.

- `/crearvehiculo <modelo> <color1> [color2] [temporal|fijo] [destino]`: el cliente del administrador solo informa del tipo del modelo (automóvil, moto, barco, helicóptero, avión, submarino). Un modelo inexistente no crea registro. El vehículo aparece 4 m delante, con matrícula `OS000123`, colores y un state bag `osdev` (ID, matrícula, colores, livery) que aplica quien controla la entidad.
- Fijos: modo huérfano `KeepEntity`; posición guardada cada 30 s si se movió más de 1 m o giró más de 5°, y al parar el recurso o apagar el servidor. Tras reiniciar el servidor se recrean en esa posición. Antes de crear se busca la entidad por state bag o matrícula, así que reiniciar solo el recurso no duplica.
- Temporales: se retiran al parar el recurso y no se restauran.
- Fijos antiguos sin tipo guardado: se completa el tipo cuando entra un administrador (`osdev.assets`) y entonces se restauran.
- `/recuperarvehiculo <id>`: rechaza duplicados; si no existe, lo recrea delante del administrador.
- Trenes no admitidos; remolques se crean como automóvil.

## Policía NPC

`/policianpc on|off` (`osdev.admin`; sin argumentos muestra el estado). El ajuste se guarda en el registro, se aplica al momento a todos los jugadores y a los que entren después. Valor inicial: `NpcPoliceDefault` en `config/core.lua` (`true` = GTA normal).

- `off`: nivel de búsqueda máximo 0 y limpieza continua, la policía ignora al jugador y se desactivan los despachos policiales y militares (1, 2, 4, 6–10, 12–15; la tabla oficial numera 12–15 de forma ambigua y se cubren todos).
- No se borran entidades ni se impide crear policía ambiental; ambulancias (5), bomberos (3) y bandas (11) no se tocan. No afecta a policías jugadores ni a las alertas de OS Security.
- Al parar el recurso con la policía desactivada, cada cliente restablece el comportamiento normal de GTA.

## Peatones y tráfico

`/npcs on|off` (`osdev.admin`; sin argumentos muestra el estado), independiente de `/policianpc`. Se guarda, se aplica a todos al momento y a quien entre después. Valor inicial: `AmbientNpcsDefault` en `config/core.lua`.

- `off`: densidad 0 cada fotograma para peatones, peatones de escenario, tráfico, vehículos aleatorios y aparcados; sin camiones de basura ni barcos aleatorios. Los NPC que ya existen no se borran: desaparecen al alejarse.
- Los vehículos de Devtools, de vMenu y los jugadores no se ven afectados.

## Posición, muerte y aparición

- `/guardarpos` y `/ultimaubicacion`: personales; posición viva válida, desconexión y muerte se distinguen.
- `/setspawn <destino>`: `osdev.assets`; asigna la posición actual del administrador para la próxima aparición. No falsea la última posición real del destinatario.
- `/tpusuario <idJugadorConectado>`: `osdev.assets`; mueve al administrador hasta el jugador, validando entidad y bucket. Se audita.

`config/core.lua` define spawn inicial, hospital, buckets permitidos, comprobación vital (1 s) y respaldo de posiciones (60 s). Un único recorrido global comprueba jugadores; las posiciones modificadas se guardan en un solo lote. Se evita escribir por movimientos inferiores al umbral y por coordenadas inválidas/cero. Se guardan heading, bucket, fecha Unix y motivo al guardar manualmente, cambiar personaje, desconectar, detener el recurso y recibir el aviso de apagado de txAdmin. No es posible garantizar un último guardado ante caída abrupta del proceso.

La muerte se verifica mediante entidad y salud del servidor; el aviso del cliente solo solicita esa comprobación. Se conserva un historial acotado de 64 eventos con ID secuencial y causa `unknown`, sin inventar una causa. `lastDeathPosition` no sustituye a `lastValidPosition` ni a `lastLogoutPosition`.

### Apariencia

Cada personaje guarda su modelo, los 12 componentes de ropa, accesorios (sombrero, gafas, orejas, reloj, pulsera) y, en `mp_m_freemode_01`/`mp_f_freemode_01`, herencia facial, 20 rasgos, 13 superposiciones, pelo y ojos.

- Guardado automático cada 10 s solo si el aspecto cambió (mínimo 8 s entre escrituras en el servidor). `/guardarropa` guarda al momento.
- El servidor rechaza guardados durante una aparición, con el personaje muerto o con datos fuera de rango; así un aspecto anterior no se escribe sobre el personaje recién seleccionado.
- Al aparecer, modelo y ropa se aplican con la pantalla en negro y se reaplican sobre el ped definitivo. Solo se aplican variaciones que existen en ese modelo.
- Si el modelo guardado ya no existe (mod retirado), se usa `mp_m_freemode_01` sin borrar los datos y se bloquea el guardado automático hasta usar `/guardarropa`.
- Un personaje sin aspecto guardado aparece con `mp_m_freemode_01` por defecto.
- `importarropa <destinatario> <archivo>` (`osdev.identity`, también desde consola): importa un XML de Menyoo (`OutfitPedData`) copiado en `data/<archivo>.xml`, carpeta excluida de Git. Importa modelo, ropa, accesorios, herencia, rasgos, superposiciones, pelo y ojos; los tatuajes no se importan y se avisa. Se audita como `import_appearance` y, si el personaje está conectado, se aplica en el sitio; durante 15 s se ignoran sus guardados automáticos para que no pisen lo importado.

`config/spawn.lua`: `Mode='spawnmanager'` exige iniciar el recurso oficial antes de Devtools. Devtools desactiva su auto-spawn, solicita la aparición mediante su API y confirma la posición desde el servidor. Espera colisiones, libera controles tras error/timeout y permite un único intento de respaldo; tras morir utiliza el hospital. No se deben activar dos dueños del respawn. Con `Mode='external'` Devtools no ejecuta apariciones: el recurso dueño puede consultar `GetCharacterSpawn` y usar el evento local de cambio de personaje. Ese adaptador externo no se implementa aquí.

API oficial usada: [setAutoSpawn](https://docs.fivem.net/docs/resources/spawnmanager/functions/setAutoSpawn/), [spawnPlayer](https://docs.fivem.net/docs/resources/spawnmanager/functions/spawnPlayer/).

## Arquitectura y persistencia

| Archivo | Responsabilidad |
| --- | --- |
| `server.lua`, `client.lua`, `html/` | Comandos de economía/activos, integración nativa y HUD conservados. |
| `server/state.lua` | Validación, migración v1 → v2 y resolutor único. |
| `server/core.lua` | Cuenta/personaje, selección, posiciones, muerte y sesión de aparición. |
| `server/identity_commands.lua` | Comandos de identidad/posición, eventos y exports. |
| `server/storage.lua`, `server/storage/`, `server/lib/` | Adaptador de archivos, códec, snapshots alternos y verificación de escritura. |
| `client/spawn_controller.lua`, `client/spawn.lua` | Ciclo asíncrono con generaciones, confirmación y spawnmanager. |
| `config/authorization.lua`, `server/auth_*.lua`, `server/authorization_hub.lua` | Autorización granular OSCAR conservada. |

En el primer arranque de esta versión se valida el `data.json` actual y se conserva su contenido exacto en `data/migration-013-source.json` antes de escribir. Los cambios siguientes utilizan `data/core.a.json` y `data/core.b.json`, con revisiones consecutivas. Se preservan dinero, empleo, aliases, bindings, IDs y propietarios de activos. Los antiguos `data/state.*` de borradores no se activan ni se modifican. **No volver a ejecutar la versión pretest sobre estos datos**: su `data.json` queda como origen histórico y ya no refleja las operaciones nuevas.

Cada operación copia, valida, serializa, comprueba el viaje de ida/vuelta, escribe el slot alterno y relee sus bytes antes de publicarla. Acepta `true` o `1` del native `SaveResourceFile`; envía la longitud real en bytes. Fallos ambiguos, cambios externos y corrupción bloquean nuevas operaciones. Al reiniciar se usa la revisión más reciente solo si la secuencia de snapshots es válida. Un slot corrupto se conserva y exige recuperación manual desde una copia verificada; no se rebobina silenciosamente dinero al snapshot anterior. No hay garantía de fsync ni transacciones distribuidas con otros recursos. No editar ni mezclar datos en marcha.

## Exports de identidad, solo servidor

`config/core.lua → IdentityReaders` autoriza explícitamente recursos lectores (`os_inventory` preparado). Otros recursos reciben rechazo.

```lua
local active = exports.os_devtools:GetActiveCharacter(source)
-- {characterId='oschar_...', alias='...', source=2, connected=true, spawning=false}
local character = exports.os_devtools:ResolveCharacter('char:oschar_0000000001')
-- {characterId, alias, connected, source?}; no cuenta, dinero ni bienes globales.
local status = exports.os_devtools:GetIdentityStatus() -- {ready, version, provider}
local spawn = exports.os_devtools:GetCharacterSpawn(source) -- lectores autorizados
```

El evento local de servidor `osdev:characterChanged(source, dtoOrNil)` permite invalidar sesiones. No está registrado como evento de red; un consumidor siempre debe volver a consultar el personaje efectivo. `GetCharacterId(source)` conserva **el alias** por compatibilidad pretest; para el ID estable usar `GetActiveCharacter().characterId`. `GetCharacterByAlias(alias)` conserva su contrato anterior. No se crea dependencia circular con Inventory.

## Instalación y pruebas

No se modifica `server.cfg`, txData ni el servidor automáticamente. Desde la configuración administrada por el operador: `add_ace group.admin osdev.admin allow`, iniciar `spawnmanager` y después `ensure os_devtools`. Si otro recurso controla spawn, configurar antes `Mode='external'`.

```powershell
npm.cmd ci --ignore-scripts --no-audit --no-fund
npm.cmd test
node tests/run.cjs --codec 'E:\Fivem-DEV\server\citizen\scripting\lua\json.lua'
```

57 casos Lua 5.4 con Wasmoon: autorización, comandos anteriores, pagos, tipos de destinatario, migración, selección, pertenencia de cuenta, posiciones, muerte, reconexión/reinicio, colisiones/timeout, snapshots y fallos de escritura. Se verificó además en modo lectura la conservación al migrar una copia local de datos existentes. Wasmoon, el códec de desarrollo y dkjson no equivalen al RapidJSON nativo ni a ejecutar FXServer.

Pendiente ejecutar en FiveM, con copia de seguridad y dos cuentas de prueba:

1. Consultar `/personaje`, `/dinero`, `/misbienes` y `/ospermisos`; confirmar datos anteriores y HUD.
2. Crear `/crearpersonaje 1 segundo_test`, seleccionarlo, comprobar separación de saldos y volver al anterior. Intentar seleccionar un personaje de otra cuenta y repetir sin permisos.
3. Desde el admin: `/setmoney 2 5000 cash`, `/setjob 2 gruppe6 vigilante`, asignar un bien existente a 2. Comparar titularidades, `/pagar 2 50` y dinero en ambas cuentas.
4. `/guardarpos`, moverse, esperar 60 s, desconectar y reconectar con otro ID. Confirmar posición, heading, bucket e ID de personaje conservados.
5. Morir: comprobar hospital y `/ultimaubicacion`; reconectar muerto y repetir con latencia de OneSync. Probar `/setspawn 2` y `/tpusuario 2`.
6. Reiniciar el recurso y el servidor de prueba; revisar saldos, bienes, posiciones, snapshots y preferencias de HUD. Validar también falta/reinicio de spawnmanager y colisiones en las ubicaciones configuradas.

No se ha realizado una ejecución controlada de estos casos en FiveM en esta entrega. No se ha hecho push ni se avanza a otra fase.
