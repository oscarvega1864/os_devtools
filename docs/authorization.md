# Autorización OSCAR y txAdmin

## Investigación y causa raíz

El manifiesto instalado de `monitor` declara **txAdmin 8.1.2**. Se inspeccionaron
su manifiesto, `resource/sv_admins.lua`, `resource/menu/server/sv_functions.lua` y
la documentación oficial. No se modifica txAdmin para exponer funciones internas.

`txAdmin:events:adminAuth` informa `netid`, `isAdmin` y nombre opcional; **no
incluye los permisos granulares del administrador**. `adminsUpdated` avisa de
cambios de personal/permisos y fuerza reautenticación. `PlayerHasTxPermission`
existe dentro del runtime de `monitor`, pero no está exportada. No se usa la ruta
HTTP privada de ese recurso, sus credenciales ni se lee `admins.json` desde OSCAR.

El rechazo previo ocurría porque `osdev.admin` es distinto de los permisos de
txAdmin: aparecer en Admins no incorpora a `group.admin`. La configuración revisada
ya concedía el ACE específico al grupo; repetir esa línea no incorpora al personal
que no herede de él. `/ospermisos` permite comprobar la autorización efectiva de
la conexión que produce el rechazo. El nombre de un jugador/administrador no es
una prueba de permisos; los permisos de vMenu tampoco se traducen automáticamente.

**No hay una API pública granular verificada para gestionar todo exclusivamente
desde Admins.** La solución implementa la alternativa explícita permitida por la
solicitud: asignar capacidades OSCAR concretas desde la consola administrativa,
sobre una autenticación observada de txAdmin. No confunde propietario y moderador.

Fuentes oficiales: [eventos](https://github.com/citizenfx/txAdmin/blob/master/docs/events.md#txadmineventsadminauth),
[permisos](https://github.com/citizenfx/txAdmin/blob/master/docs/permissions.md),
[emisión del evento](https://github.com/citizenfx/txAdmin/blob/master/resource/sv_admins.lua),
[función interna](https://github.com/citizenfx/txAdmin/blob/master/resource/menu/server/sv_functions.lua).

## Operación sin editar server.cfg por cada incorporación

1. Dar de alta al empleado en txAdmin → Admins, con sus permisos limitados reales.
2. Iniciar `os_devtools` antes de que se autentique en el menú oficial `/tx`.
3. Un operador verifica la conexión y su identidad y, desde Live Console, asigna:

   ```text
   osautorizar 2 finance 10 CONFIRMAR
   ```

4. El jugador ejecuta `/ospermisos`; muestra ACE nativo y permiso efectivo por
   categoría, incluyendo su proveedor. Revocar desde consola con:

   ```text
   osrevocar 2
   ```

Los comandos de gestión solo aceptan consola o el ACE separado `oscar.auth.manage`.
`osdev.admin` no autoriza a delegar perfiles. El ID se utiliza para localizar la
conexión, pero cada delegación se liga también a su identificador persistente y
se invalida si cambia. No se persisten principales `player.N`. Verificar al usuario
conectado antes de confirmar; no identificarlo por el nombre visible.

Solo operadores de confianza deben tener Live Console/`console.write`: esa consola
ya controla el servidor. El servicio no puede inferir los roles definidos en el panel.

| Perfil | Permisos |
| --- | --- |
| `oscar_admin` | Administración de Devtools, Security e Inventory, solo mediante asignación explícita. |
| `finance` | `osdev.economy`: setmoney, givemoney, removemoney. |
| `jobs` | `osdev.jobs`: setjob, setduty. |
| `assets` | `osdev.assets` y `osdev.inspect`: crear/asignar bienes, vehículos, aspecto, setspawn y consultas. |
| `observer` | `osdev.inspect`: consultas administrativas; sin mutaciones. |
| `devtools_admin` | `osdev.admin`: administración general de Devtools. |
| `security_admin` | `ossecurity.admin`: contrato administrativo existente de OS Security. |
| `inventory_admin` | `osinventory.admin`: giveitem, removeitem, inspectinventory. |

Un perfil nuevo sustituye al anterior; no acumula capacidades. Duración de 1 a
60 minutos, limitada además por la prueba de autenticación, que caduca a los 15
minutos. No se renueva automáticamente por usar comandos.

## Revocación y límites

- Un cambio de personal, permisos o identificadores en Admins invalida **todas**
  las pruebas/delegaciones txAdmin. Reautenticar y volver a asignar únicamente
  los perfiles aprobados: el evento no permite deducir cuáles deben conservarse.
- También se invalidan al desconectar, cambiar identidad, caducar, retroceder el
  reloj, detener/cambiar de versión `monitor` o reiniciar el broker/servidor.
- El servicio debe estar activo antes de la autenticación. Si no observó el evento,
  reautenticar de forma normal; si el menú no emite otro, reconectar. No disparar
  eventos internos manualmente ni reiniciar `monitor` para forzarlo.
- Con el menú txAdmin deshabilitado puede no existir autenticación observable.
  En ese caso usar ACE o un proveedor externo autorizado; no se simula un login.
- El evento acredita una autenticación observada para un ID de conexión, no una
  consulta síncrona de la lista actual ni un token granular. La revisión explícita
  del operador y la vinculación al identificador actual siguen siendo obligatorias.
- La documentación oficial advierte de notificaciones perdidas mientras el servidor
  está detenido. Por eso no se persisten delegaciones. La revocación inmediata
  depende de recibir el evento; la caducidad limita estados observados obsoletos.
- Retirar a alguien de txAdmin no elimina un ACE independiente dado por otro
  sistema. Para revocación total, retirarlo también de esa vía. El diagnóstico
  distingue qué proveedor sigue autorizando. El broker no modifica ACL ajenas.
- Una versión no verificada de txAdmin desactiva su vía. Revisar contrato y
  pruebas antes de cambiar `VerifiedTxVersion`. ACE sigue funcionando.

No se escriben permisos en `server.cfg` ni en datos RP. La auditoría imprime
acción, conexión, perfil y una identidad enmascarada, sin nombres ni identificadores
completos. Las denegaciones y diagnósticos se limitan por tiempo. No hay eventos de
cliente para conceder perfiles o registrar proveedores.

## Arquitectura y contratos comprobados

| Archivo | Responsabilidad |
| --- | --- |
| `config/authorization.lua` | Perfiles, consumidores, límites, versión y proveedores. Solo servidor. |
| `server/auth_identity.lua` | Identificadores nativos validados; sin depender del alias RP. |
| `server/authorization_hub.lua` | Resolución común, pruebas, delegaciones y revocación. |
| `server/auth_boot.lua` | Eventos locales, comandos y exports con comprobación de recurso llamante. |
| `server.lua` | Guard por categoría de operación y diagnóstico propio. |
| `tests/authorization_spec.lua`, `tests/wiring_spec.lua` | Modelo de permisos y conexión de scripts reales con nativos simulados. |

Prioridad de identidad de autorización: `license`, `license2`, `fivem`. Los dos
primeros requieren 40 caracteres hexadecimales; Cfx.re, decimal positivo. Se rechazan
identificadores contradictorios o conexiones inexistentes. Esta identidad de seguridad
no renombra ni migra los personajes existentes.

```lua
-- Solo servidor. El recurso llamante debe estar autorizado para ese permiso.
local allowed = exports.os_devtools:HasOscarPermission(source, 'ossecurity.admin')
```

OS Security tenía un contrato real `ossecurity.admin`, verificado antes de editarlo.
Su adaptador opcional conserva ACE, consulta solo ese permiso y falla cerrado si
el export no está disponible o no devuelve `true` literal. No necesita Devtools
para funcionar con ACE; `AdminAuthorizationResource=false` desactiva el adaptador.
No concede ítems, `ossecurity.g6.operations`, perfiles G6, propiedad de dispositivos
ni vídeo remoto. Las validaciones existentes permanecen vigentes.

En la revisión final apareció una implementación `os_inventory 0.1.0-pretest`.
Se verificaron su manifiesto y `server/main.lua`: giveitem, removeitem e
inspectinventory comparten `osinventory.admin`. Solo después se añadió su consumidor
y un adaptador opcional para ese contrato exacto. No se modificaron identidades,
objetos, persistencia, NUI ni APIs RP. Esto no completa la fase general del inventario.

Proveedores externos están deshabilitados por defecto. Tras configurar el nombre
exacto del recurso y sus permisos en `ExternalProviders`, ese recurso puede registrar:

```lua
exports.os_devtools:RegisterOscarAuthorizationProvider(function(source, principal, permission)
    return false -- Sustituir por su comprobacion real de servidor.
end)
```

El callback se consulta en cada operación, acepta solo `true` literal y está limitado
a sus permisos configurados. Se elimina al detener el recurso; debe registrarse
de nuevo al arrancar. No aceptar nombres, roles o permisos declarados por clientes.

## Conservación de la versión pretest

Se preservaron los cambios existentes de `server.lua`, `client.lua` y el manifiesto,
según la instrucción de continuar sobre `0.1.3-pretest`. La capa de autorización
no cambia su almacenamiento, posiciones, dinero, empleos ni activos al conceder
permisos. No activa otra migración ni mezcla `data.json` con snapshots anteriores.
El almacenamiento y la fase completa de posiciones siguen pendientes de revisión.

Los borradores previos se conservaron en `.tools/pending-hotfix-identity` y
`.tools/pending-0.1.3`, fuera de Git. No borrar datos reales ni promover un snapshot
antiguo sobre el estado actual al retomarlos.

## Pruebas y validación pendiente

Node.js 22+ y Wasmoon solo se usan para desarrollo:

```powershell
npm.cmd ci --ignore-scripts --no-audit --no-fund
npm.cmd test
node tests/run.cjs --codec 'E:\Fivem-DEV\server\citizen\scripting\lua\json.lua'
```

Pasan 31 pruebas: 17 del servicio y 14 de conexión. Cubren administrador ACE,
segundo administrador txAdmin, moderador, jugador normal, eliminación, reconexión,
reinicio, cambios en caliente, suplantación, exports, pagos y conservación de campos
pretest. Los eventos, nativos y archivos se simulan; dkjson heredado y el códec de
desarrollo no sustituyen al RapidJSON nativo.

Comprobación manual en el servidor local respaldado:

1. Iniciar Devtools antes de autenticar al personal; después Inventory y Security
   si se usan sus adaptadores. Si ya están iniciados, reiniciarlos manualmente
   en ese orden para cargar el código nuevo. No se cambia server.cfg.
2. Conectar propietario, segundo administrador, moderador y jugador normal.
   Autenticar personal mediante `/tx` y revisar `/ospermisos`.
3. Asignar desde Live Console `finance` al segundo y `observer` al moderador.
   Verificar que solo ejecutan sus categorías. Un usuario normal no debe poder
   ejecutar `osautorizar` ni modificar saldos/bienes.
4. Comprobar `/pagar`, `/dinero`, `/misbienes` y HUD para usuarios normales.
5. Cambiar permisos/eliminar un administrador en Admins: las delegaciones deben
   desaparecer. Reautenticar y asignar solo lo aprobado; probar `osrevocar`.
6. Reconectar y reiniciar el servidor: no recuperar delegaciones temporales.
7. Asignar `security_admin`, comprobar `osdev list`/`osmaint`, revocar y comprobar
   denegación. No debe abrir una tablet sin su ítem y autorización G6.
   Probar `inventory_admin` con giveitem/removeitem/inspectinventory, revocar y
   comprobar denegación. El perfil nuevo sustituye al anterior; `oscar_admin`
   permite probar los tres dominios cuando se haya aprobado expresamente.
8. Probar un ACE independiente: debe conservarse tras revocar la delegación;
   retirarlo por su propia vía si se quiere revocación total.

No se ha realizado una validación controlada en FXServer/cliente. La existencia de
archivos creados por el recurso durante el trabajo no demuestra el funcionamiento
de la nueva autorización, sus eventos nativos o los comandos dentro del juego.
