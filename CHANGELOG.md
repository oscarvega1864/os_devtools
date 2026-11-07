# Changelog

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
