-- Solo servidor. No contiene concesiones ACE ni datos de cuentas.
OSDevtools.CoreConfig = {
    Version='0.1.3', MaxFileBytes=8*1024*1024, MaxDeaths=64,
    PositionSeconds=60, MonitorMilliseconds=1000, MinPositionMove=0.5,
    SpawnMilliseconds=20000, RespawnMilliseconds=5000, AppearanceMinMilliseconds=8000,
    AllowedBuckets={ [0]=true },
    DefaultSpawn={x=-1037.6,y=-2737.8,z=20.17,h=329,bucket=0},
    HospitalSpawn={x=298.63,y=-584.31,z=43.26,h=70,bucket=0},
    IdentityReaders={os_inventory=true,os_security=true,os_admin=true}, -- os_security: objetos por personaje via os_inventory
    -- Respuesta policial NPC de GTA si nadie la ha cambiado con /policianpc (true = GTA normal).
    NpcPoliceDefault=true,
    -- Peatones y trafico de GTA si nadie lo ha cambiado con /npcs (true = GTA normal).
    AmbientNpcsDefault=true
}
