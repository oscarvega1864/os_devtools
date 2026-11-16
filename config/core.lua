-- Solo servidor. No contiene concesiones ACE ni datos de cuentas.
OSDevtools.CoreConfig = {
    Version='0.1.6', MaxFileBytes=8*1024*1024, MaxDeaths=64,
    PositionSeconds=60, MonitorMilliseconds=1000, MinPositionMove=0.5,
    SpawnMilliseconds=20000, RespawnMilliseconds=5000, AppearanceMinMilliseconds=8000,
    AllowedBuckets={ [0]=true },
    DefaultSpawn={x=-1037.6,y=-2737.8,z=20.17,h=329,bucket=0},
    HospitalSpawn={x=298.63,y=-584.31,z=43.26,h=70,bucket=0},
    IdentityReaders={os_inventory=true,os_security=true,os_admin=true,os_gruppesechs=true,os_loadscreen=true,os_emotes=true,os_hud=true,os_life=true,os_police=true}, -- os_security: objetos por personaje via os_inventory
    -- Recursos que pueden ingresar dinero (nominas de trabajos) con PayCharacter, y su tope por pago.
    -- os_security: devolucion de una compra de la tienda G6 que no se pudo entregar.
    Payers={os_gruppesechs=true,os_security=true,os_inventory=true}, MaxPayment=50000, -- os_inventory: devolucion de una compra en Ammu-Nation que no cabe
    -- Menu /negocio: para contratar, el negocio necesita job (/crearnegocio ... job=<job> o /negociojob) y al menos
    -- MinRanks rangos creados por el titular. La invitacion caduca a los InviteSeconds; contratar a InviteDistance m.
    -- Sueldo por rango: cada PayMinutes conectado con el job del negocio, el empleado cobra el sueldo de su rango del
    -- banco del titular (si no tiene saldo, no se paga y se avisa). MaxSalary: tope por pago.
    Business={MinRanks=2,MaxRanks=10,MaxStaff=40,InviteSeconds=30,InviteDistance=5.0,PayMinutes=60,MaxSalary=10000},
    -- Recursos que pueden cobrar al personaje activo con ChargeCharacter (tienda G6), y su tope por cobro.
    Chargers={os_security=true,os_inventory=true,os_life=true,os_police=true}, MaxCharge=500000, -- os_inventory: tienda Ammu-Nation
    -- Proveedor bancario: recursos que leen fichas de personaje (tambien desconectados), buscan
    -- personajes y mueven efectivo/banco con BankAdjust. o-link es el puente de Oxide Banking.
    Bankers={['o-link']=true}, MaxBankMove=10000000, MaxBankSearch=50,
    -- Respuesta policial NPC de GTA si nadie la ha cambiado con /policianpc (true = GTA normal).
    NpcPoliceDefault=true,
    -- Peatones y trafico de GTA si nadie lo ha cambiado con /npcs (true = GTA normal).
    AmbientNpcsDefault=true,
    -- Selector al entrar: lista los personajes de la cuenta (license) y permite crear uno propio.
    CharacterSelect={Enabled=true,AllowCreate=true,MaxCharacters=4,CreateCooldownMilliseconds=5000,RequestMilliseconds=1000,
        DesignWithoutAppearance=true} -- disenador de personaje al aparecer sin apariencia guardada
}
