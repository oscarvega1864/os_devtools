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
    -- Con os_admin arrancado, el grupo de los admins de txAdmin solo se da de servicio (/adminservicio de os_admin).
    TxAdminRequiresDuty = true, DutyResource = 'os_admin',
    Permissions = {
        ['osdev.admin'] = {}, ['osdev.economy'] = { parent = 'osdev.admin' },
        ['osdev.jobs'] = { parent = 'osdev.admin' }, ['osdev.assets'] = { parent = 'osdev.admin' },
        ['osdev.inspect'] = { parent = 'osdev.admin' },
        ['osdev.identity'] = { parent = 'osdev.admin' },
        -- Subpermisos de bienes (staff de os_admin): quien tiene osdev.assets los tiene todos.
        ['osdev.assets.properties'] = { parent = 'osdev.assets' }, ['osdev.assets.businesses'] = { parent = 'osdev.assets' },
        ['osdev.assets.factions'] = { parent = 'osdev.assets' }, ['osdev.assets.vehicles'] = { parent = 'osdev.assets' },
        ['osdev.assets.dealers'] = { parent = 'osdev.assets' },
        ['ossecurity.admin'] = {}, ['osinventory.admin'] = {}
    },
    Consumers = {
        os_devtools = { ['osdev.admin']=true, ['osdev.economy']=true, ['osdev.jobs']=true,
            ['osdev.assets']=true, ['osdev.inspect']=true, ['osdev.identity']=true,
            ['osdev.assets.properties']=true, ['osdev.assets.businesses']=true, ['osdev.assets.factions']=true,
            ['osdev.assets.vehicles']=true, ['osdev.assets.dealers']=true },
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
