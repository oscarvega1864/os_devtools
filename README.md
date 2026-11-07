# OS Devtools 0.1.3-pretest.1 — Autorización OSCAR

Recurso standalone orientado al FXServer local. **No instalar en servidores públicos o de producción**: es un banco de pruebas, no un framework RP ni una economía transaccional de producción. No incluye inventario.

Se conserva la implementación `0.1.3-pretest` existente, incluida su identidad
automática, HUD y posiciones. `/setpj` sigue retirado. La capa común de autorización
admite ACE y delegaciones temporales explícitas sobre autenticación observada de
txAdmin. OS Security dispone de un adaptador opcional tras verificar su contrato.
Consultar [investigación, permisos y validación](docs/authorization.md).

## Instalación
1. Copia la carpeta `os_devtools` a `resources/[local]/os_devtools`.
2. Para la vía ACE, la configuración tradicional es (no se modifica automáticamente):
   ```cfg
   add_ace group.admin osdev.admin allow
   ensure os_devtools
   ```
3. Alternativa sin altas individuales en `server.cfg`: autenticar al empleado en el menú de txAdmin y, desde su consola administrativa, ejecutar `osautorizar <id> <perfil> <minutos> CONFIRMAR`. La asignación es explícita porque txAdmin 8.1.2 no expone un export público de permisos granulares. El mero estado de administrador no concede acceso global.
4. Conecta dos jugadores si quieres probar `/pagar` o `/ceder` entre personas.
5. Se conserva el almacenamiento pretest en `data.json` y `data_backup.json`. La capa de autorización no migra esos archivos; sus delegaciones viven solo en RAM. **No editar datos en marcha ni mezclarlos con snapshots de prototipos anteriores.**

## Identidad
- Se mantiene la identidad automática pretest por `license` y las vinculaciones anteriores, incluido `oscar_vega`. La identidad de autorización es nativa y no depende del alias RP.
- `/ospermisos` muestra diagnóstico propio y enmascarado. `osrevocar <id>` revoca una delegación, desde consola u `oscar.auth.manage`.
- `/setjob oscar_vega gruppe6 vigilante`
- `/setduty oscar_vega on`
- `/dinero`: muestra **dinero en mano** y **banco**.
- `/misbienes` o `/mispropiedades`: muestra dinero y todo lo propio.
- `/verpropiedades oscar_vega`: consulta administrativa de otro personaje.

## Economía
- `/setmoney oscar_vega 1000 cash`
- `/setmoney oscar_vega 5000 bank`
- `/givemoney oscar_vega 100 cash`
- `/removemoney oscar_vega 20 cash`
- `/pagar 2 50`: paga 50 $ **en efectivo** al personaje activo del jugador 2.
- `/pagar oscar_vega 50`: también admite alias del personaje, incluso desconectado.
- No se permite transferir a uno mismo, saldos negativos ni pagos sin fondos.

## Activos
- `/crearpropiedad 200 casa Villa_Mirror 50000` crea en tu posición y **rechaza ID repetido**.
- `/crearnegocio ltd mirror oscar_vega 30$` crea negocio con ID secuencial.
- `/setpropiedad 200 oscar_vega`
- `/setnegocio 1 oscar_vega`
- `/crearvehiculo sultan 0 111 fijo oscar_vega`
- `/crearvehiculo sultan 0` crea uno temporal.
- `/setvehiculo 1 oscar_vega`
- `/recuperarvehiculo 1` genera una copia física del registro si no se conoce entidad existente. Los vehículos fijos persisten **como registro**, no reaparecen automáticamente tras reiniciar.
- `/ceder 2`: **cede el vehículo registrado en el que estás como conductor**, al personaje del jugador 2. No cede automáticamente dinero, propiedades o negocios.
- `/setcolor 0 111`, `/listliveries`, `/setlivery 0 native`, `/setlivery 0 mod48` (solo estando al volante, guardado únicamente en vehículos registrados).
- `/listvehiculos`, `/listnegocios`, `/listpropiedades`.
- `/infovehiculo 1`, `/infonegocio 1`, `/infopropiedad 200`.

## Alcance y limitaciones
- Los comandos administrativos usan permisos efectivos por operación: economía, empleos, activos o consultas. `osdev.admin` conserva acceso general a Devtools. `/pagar`, `/ceder`, `/dinero`, `/misbienes` y `/mispropiedades` siguen siendo personales.
- Los precios de propiedades y negocios son metadatos; `/setpropiedad`, `/setnegocio` y `/setvehiculo` **asignan gratis** y no cobran.
- Esta primera edición presenta listados en el chat, no NUI visual.
- El sistema guarda un único JSON con escritura de recurso. Para alta concurrencia, compras con inventario, transacciones entre recursos o producción se necesita una base de datos con transacciones atómicas; **no usar este ejemplo como economía de producción**.
- Los vehículos los genera el cliente autorizado. Si tienes `sv_entityLockdown strict`, puede que no se creen: se necesita un adaptador de spawn autorizado desde servidor. Se ha mantenido la creación en cliente para compatibilidad simple con el servidor DEV.
- No incorpora `/setextras`, compra de activos, tarjetas, garajes, zonas editables ni integración real de jobs externos.
- `/ceder` requiere que el personaje sea propietario; para reasignación administrativa utiliza `/setvehiculo`.
- Los registros temporales se limpian al arrancar el recurso. Los IDs no se reutilizan.


## HUD (v0.1.1)
- Aparece en la esquina superior derecha: **ID de sesión** de FiveM y **DINERO EN MANO** del personaje activo.
- No muestra el dinero del banco. Se consulta con `/dinero`.
- Al resolver automáticamente la identidad se muestra el efectivo del personaje vinculado.
- Si el usuario no tiene personaje activo, se muestra `--` en efectivo.
- Se actualiza al cambiar el saldo, pagar o recibir un pago. Reconciliación cada 15 segundos.
- `/hud` permite ocultar y volver a mostrar la interfaz en el cliente.
- Es un HUD de solo lectura: el cliente no puede cambiar saldos mediante la interfaz.
- NUI local en `html/`; no se requieren librerías ni servicios externos.
- Si reemplazas la v0.1.0, **conserva `data.json`**. No hace falta migración de datos.


## v0.1.2 — Conservación de comandos y diagnóstico de /pagar
- Se conservan los comandos de economía, empleos y activos. `/setpj` está retirado en la versión pretest. `/oscomandos` muestra los comandos actuales.
- `/pagar <idJugador|alias> <cantidad>` exige dos **personajes distintos registrados**. Si estás solo con el personaje `oscar_vega`, `/pagar oscar_vega 100` se rechazará correctamente.
- Para probar pagos, conectar dos cuentas de prueba con identidad automática; también se conservan los pagos a alias registrados desconectados. `/pagar` nunca crea destinatarios nuevos.
- Mensajes específicos si falta el personaje del destinatario, si el ID no está conectado, si faltan fondos o si se intenta pagar al propio personaje.
- **Persistencia:** no se modifica el esquema de `data.json`. Antes de actualizar, haz copia de seguridad de tu archivo `data.json` en la instalación existente. No sustituir ni eliminar ese archivo; el paquete no incluye `data.json`.
- Si el inventario se desarrolla después, no modificar los registros ni los comandos de este recurso sin pruebas de regresión.


## 0.1.3-pretest (paquete de integración)
- **No usar /setpj**: identidad por `license:` y conservacion de `bindings` anteriores. Las asociaciones antiguas no se reescriben.
- `/ospermisos` consulta ACE del jugador real, no del principal introducido manualmente.
- `/guardarpos`, `/ultimaubicacion`, `/setspawn <jugador|alias>` y ubicacion de muerte registrada por separado.
- Restauracion de posicion en evento `playerSpawned` (requiere prueba con spawnmanager del servidor).
- Exports GetCharacterId(playerSource) y GetCharacterByAlias(alias), para `os_inventory`.
- **No concede ACE** por ser admin de txAdmin. Comprobar licencia real del jugador y `add_principal identifier.license:... group.admin`.
- No contiene `data.json`: conservar el archivo existente del servidor y realizar copia antes de actualizar.
- Quedan pendientes pruebas reales con jugadores, muerte, reconexion y reinicio. No utilizar en produccion.
