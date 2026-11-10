-- Solo servidor. adminAuth de txAdmin no expone sus permisos granulares.
OSDevtools = OSDevtools or {}
OSDevtools.AuthorizationConfig = {
    TxResource = 'monitor', VerifiedTxVersion = '8.1.2', ProofSeconds = 900, MaxLeaseMinutes = 60,
    ManagerAce = 'oscar.auth.manage',
    -- Admins de txAdmin: mientras txAdmin los reconozca como admin en el juego, entran en este grupo ACE
    -- (el mismo que los admins de server.cfg: panel F10, comandos, vMenu...). nil lo desactiva.
    -- Requiere en server.cfg: add_ace resource.os_devtools command.add_principal allow
    --                         add_ace resource.os_devtools command.remove_principal allow
    -- Al reiniciar os_devtools se retiran (un ID de jugador se reutiliza); el admin debe reconectar o volver a
    -- autenticarse en txAdmin para recuperarlo.
    TxAdminGroup = 'group.admin',
    Permissions = {
        ['osdev.admin'] = {}, ['osdev.economy'] = { parent = 'osdev.admin' },
        ['osdev.jobs'] = { parent = 'osdev.admin' }, ['osdev.assets'] = { parent = 'osdev.admin' },
        ['osdev.inspect'] = { parent = 'osdev.admin' },
        ['osdev.identity'] = { parent = 'osdev.admin' },
        ['ossecurity.admin'] = {}, ['osinventory.admin'] = {}
    },
    Consumers = {
        os_devtools = { ['osdev.admin']=true, ['osdev.economy']=true, ['osdev.jobs']=true,
            ['osdev.assets']=true, ['osdev.inspect']=true, ['osdev.identity']=true },
        os_security = { ['ossecurity.admin']=true },
        os_inventory = { ['osinventory.admin']=true }
    },
    Profiles = {
        oscar_admin = { 'osdev.admin', 'ossecurity.admin', 'osinventory.admin' }, -- Solo asignacion explicita.
        devtools_admin = { 'osdev.admin' }, finance = { 'osdev.economy' },
        jobs = { 'osdev.jobs' }, assets = { 'osdev.assets','osdev.inspect' },
        observer = { 'osdev.inspect' },
        identity = { 'osdev.identity' },
        security_admin = { 'ossecurity.admin' }, inventory_admin = { 'osinventory.admin' }
    },
    ExternalProviders = {} -- resource = { ['permiso.especifico'] = true }; sin privilegios por defecto.
}
