-- Solo servidor. adminAuth de txAdmin no expone sus permisos granulares.
OSDevtools = OSDevtools or {}
OSDevtools.AuthorizationConfig = {
    TxResource = 'monitor', VerifiedTxVersion = '8.1.2', ProofSeconds = 900, MaxLeaseMinutes = 60,
    ManagerAce = 'oscar.auth.manage',
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
