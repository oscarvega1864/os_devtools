# Changelog

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
