-- Solo servidor. adminAuth de txAdmin no expone sus permisos granulares.
OSDevtools = OSDevtools or {}
OSDevtools.AuthorizationConfig = {
    TxResource = 'monitor', VerifiedTxVersion = '8.1.2', ProofSeconds = 900, MaxLeaseMinutes = 60,
    ManagerAce = 'oscar.auth.manage',
    Permissions = {
        ['osdev.admin'] = {}, ['osdev.economy'] = { parent = 'osdev.admin' },
        ['osdev.jobs'] = { parent = 'osdev.admin' }, ['osdev.assets'] = { parent = 'osdev.admin' },
        ['osdev.inspect'] = { parent = 'osdev.admin' },
        ['ossecurity.admin'] = {}
    },
    Consumers = {
        os_devtools = { ['osdev.admin']=true, ['osdev.economy']=true, ['osdev.jobs']=true,
            ['osdev.assets']=true, ['osdev.inspect']=true },
        os_security = { ['ossecurity.admin']=true }
        -- os_inventory: contrato pendiente; no se inventa una integracion.
    },
    Profiles = {
        oscar_admin = { 'osdev.admin', 'ossecurity.admin' }, -- Solo asignacion explicita de operador.
        devtools_admin = { 'osdev.admin' }, finance = { 'osdev.economy' },
        jobs = { 'osdev.jobs' }, assets = { 'osdev.assets','osdev.inspect' },
        observer = { 'osdev.inspect' },
        security_admin = { 'ossecurity.admin' }
    },
    ExternalProviders = {} -- resource = { ['permiso.especifico'] = true }; sin privilegios por defecto.
}
