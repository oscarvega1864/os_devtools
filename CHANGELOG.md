# Changelog

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
