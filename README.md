# os_devtools — Herramientas de PRUEBA exclusivamente

Recurso standalone orientado al FXServer local. **No instalar en servidores públicos o de producción**: es un banco de pruebas, no un framework RP ni una economía transaccional de producción. No incluye inventario ni integraciones con OS Security todavía.

## Instalación
1. Copia la carpeta `os_devtools` a `resources/[local]/os_devtools`.
2. Añade en `server.cfg` (antes del ensure):
   ```cfg
   add_ace group.admin osdev.admin allow
   ensure os_devtools
   ```
3. Asegúrate de que tu licencia FiveM está en el grupo admin mediante la configuración ACE que ya utilices. Alternativamente, en entorno DEV, ejecuta `add_principal identifier.license:TU_LICENSE group.admin` (sustituyendo por tu identificador real, nunca compartas la licencia). Usa txAdmin/console para administrar.
4. Conecta dos jugadores si quieres probar `/pagar` o `/ceder` entre personas.
5. El recurso crea su propio `data.json`. Haz copias de seguridad. **No cambies el archivo con el recurso en marcha.**

## Identidad
- `/setpj 1 oscar_vega` asigna el personaje de prueba `oscar_vega` al jugador ID 1. No altera su identidad FiveM real.
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
- Los comandos de administración usan `osdev.admin`, salvo `/pagar`, `/ceder`, `/dinero`, `/misbienes` y `/mispropiedades`, que requieren personaje registrado.
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
- Al ejecutar `/setpj <id> <alias>` se vincula el personaje y aparece su efectivo.
- Si el usuario no tiene personaje activo, se muestra `--` en efectivo.
- Se actualiza al cambiar el saldo, pagar o recibir un pago. Reconciliación cada 15 segundos.
- `/hud` permite ocultar y volver a mostrar la interfaz en el cliente.
- Es un HUD de solo lectura: el cliente no puede cambiar saldos mediante la interfaz.
- NUI local en `html/`; no se requieren librerías ni servicios externos.
- Si reemplazas la v0.1.0, **conserva `data.json`**. No hace falta migración de datos.


## v0.1.2 — Conservación de comandos y diagnóstico de /pagar
- Se mantienen todos los comandos de la v0.1.1 y sus nombres. Se añade `/oscomandos` como recordatorio en el chat.
- `/pagar <idJugador|alias> <cantidad>` exige dos **personajes distintos registrados**. Si estás solo con el personaje `oscar_vega`, `/pagar oscar_vega 100` se rechazará correctamente.
- Para preparar dos personajes de prueba con una sola cuenta, estando conectado como ID 1, ejecuta `/setpj 1 cliente_prueba`, después `/setpj 1 oscar_vega`. El alias `cliente_prueba` quedará registrado; usa `/pagar cliente_prueba 100` para enviarle efectivo sin estar conectado. Esta práctica es solo para el banco de pruebas.
- Mensajes específicos si falta el personaje del destinatario, si el ID no está conectado, si faltan fondos o si se intenta pagar al propio personaje.
- **Persistencia:** no se modifica el esquema de `data.json`. Antes de actualizar, haz copia de seguridad de tu archivo `data.json` en la instalación existente. No sustituir ni eliminar ese archivo; el paquete no incluye `data.json`.
- Si el inventario se desarrolla después, no modificar los registros ni los comandos de este recurso sin pruebas de regresión.
