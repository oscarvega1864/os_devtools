# Changelog

## Sin publicar

- Los avisos `[OSCAR AUTH]` de dar o quitar el grupo de txAdmin ya no salen en el chat de quien usa `/adminservicio`:
  se escriben fuera del comando y solo llegan a la consola del servidor.

## 0.1.11 — Admins de txAdmin solo de servicio

- El grupo `group.admin` de los admins de txAdmin solo se da **de servicio** (`/adminservicio` de os_admin) mientras
  os_admin esté arrancado (`TxAdminRequiresDuty`). Export `IsTxAdmin` (solo para os_admin).

## 0.1.10 — Datos para el menú de inicio de os_hud

- `GetCharacterStats` da más datos para el menú de inicio de os_hud: posición de propiedades y negocios, modelo, tipo
  y posición real de los vehículos en la calle, plantilla de los negocios, información del trabajo público (rangos,
  sueldo, puntos de servicio) y la lista de trabajos públicos. Nuevo export `GetDealerList` (concesionarios).

## 0.1.9 — Armarios, conjuntos y vista previa del concesionario

- **Armarios en propiedades**: `/armario <idPropiedad>` pone un armario donde estás (`/armario borrar` quita el
  cercano). Junto a él, E abre el diseñador solo con la ropa (si tienes la llave de la propiedad). Se pueden guardar
  hasta 10 **conjuntos** por personaje y ponérselos después; Cancelar deja la ropa con la que se entró.
- Más prendas en el diseñador: máscara, mochila, collar/corbata, reloj y pulsera.
- **Concesionario**: la vista previa es fija y el jugador mueve la cámara arrastrando para verla.
- **Arreglado**: un vehículo creado con `/crearvehiculo` sin dueño da la llave a quien lo crea (aviones incluidos);
  `/setcar livery` acepta solo índices enteros.
- **Datos más seguros**: armarios, conjuntos y puntos de trabajo se guardan con copia `.bak` y comprobación; un
  archivo dañado no borra los datos. Guardar o borrar conjuntos tiene un límite de frecuencia.

## 0.1.8 — Trabajos, concesionarios, llaves, menú de negocio y /setcar

- **`/setcar`**: `reparar [id|matrícula]` (también a distancia: lo repara quien tiene el coche cargado o, si nadie,
  se recrea en el sitio), `livery <n> [native|mod48]` (guardada en los vehículos registrados), `gas <0-100>` y
  `negocio|faccion meter|sacar <id>`: los coches de la flota los usan el titular y la plantilla sin llave.
- Concesionarios con **vista previa**: el coche elegido aparece en el escaparate con el color marcado y una cámara
  gira alrededor; el catálogo pasa a un panel lateral. `/concesionarios` permite mover el punto de vista previa.
  Corregido: pagar con tarjeta cobraba en efectivo.
- **Subpermisos de bienes** (`osdev.assets.properties`, `.businesses`, `.factions`, `.vehicles`, `.dealers`); el hub de
  autorización sigue la cadena de permisos padre. `/puntotrabajo` pide `osdev.jobs`.
- Envío a la web del panel (vía os_admin) de bienes, plantillas, personajes y la auditoría. Export `GetVehiclePlate`.

- **Trabajos públicos** (`config/jobs.lua`): LSPD, BCSO, FIB, Bomberos y EMS no son negocios. Rangos fijos, sueldo por
  rango que paga el ayuntamiento por hora de servicio, puntos de servicio en sus sedes (E) y `/trabajo` para que los
  mandos contraten, asciendan y despidan por debajo de su rango. `/puntotrabajo` (admin) añade sedes. `/setjob` valida
  los rangos de estos trabajos.
- **Concesionarios**: PDM (coches normales), Luxury Autos (deportivos, lujo y clásicos), Sanders (motos y bicis), Larry's RV
  (furgonetas, pickups, todoterreno, caravanas), Puerta del Sol (barcos) y Elitás (helicópteros y avionetas).
  `/concesionarios` (admin): precios, añadir o quitar modelos y mover mostrador y entrega (`data/dealerships.json`).
- **Concesionarios** (`config/dealerships.lua`): catálogo, color, pago en efectivo o con tarjeta (lector); el coche sale
  a tu nombre con matrícula y llave en la entrega. Tipos de negocio **policía** y **facción** (sin blip).
- Con **os_life** arrancado, al morir no se reaparece solo (exports `ReviveCharacter` y `RespawnAtHospital`).
- **Llaves como objetos de os_inventory**: para entrar hace falta llevar la llave, también al titular. Al asignar
  (`/setpropiedad`, `/setnegocio`, `/setvehiculo`), crear un vehículo con titular o cederlo, la cerradura cambia y el
  nuevo titular recibe su llave. `/darllaveprop`, `/darllaveh` y `/darllavenegocio <id> <jugador>` dan una **copia**;
  `/quitarllaveprop|h|negocio <id>` **cambia la cerradura** (las copias dejan de servir) y el titular recibe una nueva.
  `/llave <propiedad|negocio|vehiculo> <id> <jugador>` (admin) para llaves perdidas. `HasAssetAccess` = llevar la llave.
- Vehículos **clásicos** (`config/classic_vehicles.lua`, deportivos clásicos y modelos antiguos) llevan **llave física**;
  el resto, llave-tarjeta. El state bag `osdev` lleva `classic` para que el cliente no pida pasar la tarjeta.
- `/negocio`: menú del titular con sus negocios. Rangos (de menor a mayor, se ordenan y borran), plantilla (cambiar
  rango o despedir) y **contratar** a un jugador cercano, que recibe la oferta y la acepta o rechaza. Al aceptar pasa a
  tener el job y el rango del negocio; al despedirlo lo pierde.
- **Sueldo por rango** en `/negocio`: cada hora conectado (`Business.PayMinutes` = 60) con el job del negocio, el empleado
  cobra el sueldo de su rango del banco del titular (tope `MaxSalary`). Sin saldo no se paga y se avisa a los dos.
- **Puntos de servicio**: el titular pone el de su negocio en `/negocio`. Allí, con E, la plantilla (y el titular) entra o
  sale de servicio; al desconectarse sale de servicio. La nómina por hora **solo cuenta de servicio**.
- Para contratar, el negocio necesita **job** (`/crearnegocio <tipo> <nombre> <precio> job=<job>` o `/negociojob
  <id> <job>`) y al menos `Business.MinRanks` rangos (2 por defecto).
- Exports `GetCharacterStats(src)` (ficha para `/stats` de os_hud), `HasAssetAccess(src, categoria, id)` y
  `GetCharacterName(src)`, solo para recursos de `IdentityReaders`.
- Armas por personaje (`WeaponsConfig.Enabled`) **apagado**: las armas son objetos de os_inventory 0.2.0. Export
  `ClearCharacterWeapons(src)` (solo os_inventory) borra las guardadas tras pasarlas al inventario. `os_inventory`
  autorizado en `Payers` y `Chargers` para la tienda Ammu-Nation.
- Creación de personaje: elegir **crear normal** o **importar XML de Menyoo** (pegado en el selector); lo que el XML no
  traiga queda por defecto.
- **Matrículas aleatorias** de EE. UU. al crear vehículos fijos o temporales: 1 cifra, 3 letras y 3 cifras, como las de
  California / San Andreas (p. ej. `8KDR472`), sin I, O ni Q y sin repetir. Las ya creadas conservan la suya. `ListAssets('vehicles')` disponible para os_security.
- El chat muestra el nombre del personaje ("Oscar Vega") como autor de los mensajes.

## 0.1.7 — Lector os_emotes

- `os_emotes` puede leer el personaje activo (`IdentityReaders`) para guardar el andar y la expresión de cada personaje.

## 0.1.6 — Armas por personaje

- Las armas se guardan con cada personaje (`characters.<alias>.weapons`): arma, munición, tinte y accesorios
  (supresores, linternas, miras, empuñaduras y cargadores ampliados). Al aparecer o cambiar de personaje se quitan
  las del ped y se dan las de ese personaje.
- El cliente comprueba cada 3 s y solo envía si cambian (armas o accesorios al momento; solo munición, como mucho
  cada 30 s). El servidor solo acepta envíos tras la aparición confirmada del personaje activo, vivo y sin un cambio
  de personaje en curso, con un mínimo de 1,5 s entre guardados.
- Solo se guardan armas y accesorios de `config/weapons.lua` (las armas añadidas por otros recursos hay que incluirlas
  ahí). `LoseOnDeath` (por defecto `false`): si se activa, el personaje pierde las armas guardadas al morir.
- Limitación: las armas las informa el cliente (en GTA no son autoritativas en el servidor); se limita a la lista
  permitida y a la munición máxima.

## 0.1.5

- El HUD de ID y dinero se oculta mientras se mira una cámara en directo de os_security (evento local
  `os_security:cameraView`) y vuelve al salir.

## 0.1.4 — Selector y diseñador de personaje

- Cobros para la tienda G6: `ChargeCharacter(jugador, cantidad, cuenta, motivo)` cobra al personaje activo
  solo a recursos autorizados en `Chargers` (tope `MaxCharge`), sin tocar nada si no hay saldo; y
  `GetCharacterBalance(jugador)` da efectivo y banco a lectores autorizados. `os_security` puede además
  devolver con `PayCharacter`. El HUD se actualiza tras cada cobro.
- Administradores de txAdmin: el acceso de admin se concede solo cuando txAdmin está listo, se comprueba que
  `add_principal` funcionó (y si falta la línea del `server.cfg` lo dice) y se retira al cambiar la lista de
  administradores.

- Selector de personaje al entrar (NUI): lista solo los personajes de la cuenta del jugador con empleo, dinero, último lugar y estado; la elección se valida en servidor y aparece con el flujo normal. Mientras se elige no se guardan posiciones ni muertes del ped provisional. Creación propia con nombre y apellido (alias `nombre_apellido`, límite por cuenta y espera). `/personajes` abre el mismo panel dentro del juego para cambiar. Cierra la pantalla de carga de `os_loadscreen`.
- Diseñador de personaje: al crear un personaje se entra con él y, sin apariencia guardada, se abre un editor NUI (herencia, rasgos, pelo, cejas, barba, ojos, ropa y accesorios, cámara cara/cuerpo). Se guarda por la ruta validada de apariencia. `/disenarpj` lo reabre.
- Export `GetLoadingPreview(jugador)` (lectores autorizados, ahora también `os_loadscreen`): personaje vinculado y número de personajes de la cuenta del jugador que conecta, sin crear identidades.
- Apariencia por personaje: modelo, ropa, accesorios y cabeza freemode, validada y persistida en el registro; restauración al aparecer con la pantalla en negro; guardado automático por cambios y `/guardarropa`. Un modelo ausente conserva los datos y bloquea el guardado automático.
- `/crearpropiedad <numero> <precio>` sin nombre, tipo ni titular; duplicados rechazados. `/crearnegocio <tipo> <nombre> <precio>` con siete categorías, ID automático y sin titular. Blips de negocios por categoría, sin duplicados. Datos y metadatos anteriores conservados.
- Vehículos creados por el servidor (OneSync, `CREATE_VEHICLE_SERVER_SETTER`) tras comprobar el tipo del modelo; corrige "sin entidad de red". Los fijos guardan su posición y se recrean tras reiniciar el servidor, sin duplicarse; aspecto por state bag. Fijos antiguos completan su tipo al entrar un administrador.
- `/policianpc on|off`: ajuste persistente que desactiva estrellas, persecuciones y despachos policiales/militares de GTA para todos los jugadores, sin borrar entidades ni tocar ambulancias, bomberos o bandas.
- `/npcs on|off`: ajuste persistente que quita peatones, tráfico y coches aparcados de GTA para todos los jugadores, sin borrar entidades existentes.
- Mensajes: confirmaciones y errores como notificaciones de `os_notify` (opcional, con vuelta al chat); listados siempre al chat. Sugerencias con ayuda y parámetros para todos los comandos.
- `importarropa`: importación auditada de XML de Menyoo (OutfitPedData) desde `data/`, con aplicación inmediata al jugador conectado.
- Panel y consola de `os_admin` (opcional): secciones Personajes (ver, listar, cambiar, crear, guardar posición, spawn), Economía y empleos (dar/quitar/fijar dinero, empleo, servicio, bienes) y Bienes y mundo (listar, detalle, asignar, crear propiedad/negocio/vehículo, recuperar vehículo, policía NPC, peatones y tráfico). Las acciones reutilizan los comandos existentes, con su validación y permisos, y devuelven sus respuestas al panel.
- Devtools es el único dueño del autospawn de spawnmanager: un gametype que fuerce respawn ya no mueve al personaje ni cambia su modelo.

## 0.1.3 — Identidad persistente y posiciones

- Cuenta nativa, personaje activo, ID inmutable oschar y alias separados; resolución explícita por conexión, alias o char:ID. /setpj continúa retirado por la instrucción posterior de identidad automática.
- Creación, selección de personajes propios y vinculación confirmada de personajes heredados sin cuenta. Permiso osdev.identity y perfil OSCAR identity separados de moderación/economía.
- Conservación de economía, empleos, bienes, IDs, titularidades y HUD; pagos usan el resolutor común y propiedades admiten titular opcional desde la posición administrativa.
- Migración validada del data.json actual, respaldo exacto y snapshots core.a/core.b alternos. No se reutilizan ni sobrescriben snapshots de borradores. Detección de corrupción, BOOL nativo 1 y verificación de escritura/relectura.
- Posiciones de servidor por lotes: manual, cambio de personaje, desconexión, parada y aviso de apagado; última posición válida, logout y muerte independientes.
- Eventos de muerte deduplicados con causa desconocida y respawn seguro mediante API oficial spawnmanager. Control por generaciones, confirmación autoritativa, timeout y un solo respaldo; modo external opcional.
- Exports de identidad limitados a recursos lectores autorizados y evento local de cambio. El export heredado GetCharacterId sigue devolviendo alias.
- 57 pruebas automatizadas Lua 5.4; códec de desarrollo y dkjson local. Migración de una copia existente verificada en modo lectura. Pendiente validación controlada en FiveM/OneSync con jugadores y spawnmanager.

## 0.1.3-pretest.1 — Autorización común OSCAR

- Se conservan los cambios existentes de `0.1.3-pretest`: identidad automática,
  posiciones, cliente, HUD y almacenamiento. No se activa una segunda migración.
- Investigación del txAdmin instalado 8.1.2: eventos públicos `adminAuth` y
  `adminsUpdated`; la consulta granular `PlayerHasTxPermission` es interna,
  sin export. No se utiliza `admins.json`, HTTP privado ni credenciales.
- Servicio común de autorización con ACE, perfiles temporales explícitos y
  proveedores externos autorizados por recurso/permiso, deshabilitados por defecto.
- `osautorizar <id> <perfil> <minutos> CONFIRMAR` y `osrevocar <id>` requieren
  consola u `oscar.auth.manage`. Separados economía, empleos, activos y consultas.
- Identidad nativa y conexión verificadas; caducidad, revocación, cambios de lista,
  desconexión y reinicio invalidan delegaciones. No se crean permisos player.N,
  ni se modifica `server.cfg`. Ser administrador txAdmin no concede capacidades.
- `/ospermisos` distingue ACE y permisos efectivos con identidad propia
  enmascarada. Auditoría de cambios y denegaciones sin identificadores completos.
- Export `HasOscarPermission` limitado a consumidores verificados. OS Security
  consulta solo `ossecurity.admin`; el contrato `osinventory.admin` de la
  implementación pretest detectada posteriormente se verificó antes de habilitarlo.
  Perfiles separados `security_admin`, `inventory_admin` y perfil combinado explícito.
- Consultas personales filtran bienes en el servidor y no envían datos privados
  de otras cuentas ni el registro completo de personajes.
- 31 pruebas Lua 5.4 pasan con dos códecs de desarrollo; incluyen los ocho
  escenarios solicitados, comandos reales, pagos y conservación de campos pretest.
  Pendiente validación controlada en FXServer/cliente con eventos nativos.

La migración ampliada de identidad, la fase completa de posiciones y la fase completa de OS Inventory
siguen pendientes. Los borradores anteriores se conservaron localmente fuera de Git.
