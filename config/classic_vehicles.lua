-- Vehiculos clasicos: llevan llave fisica (objeto "llave") en vez de llave-tarjeta, y no piden pasar la tarjeta por el
-- lector para abrir o arrancar. Lista por nombre de modelo (spawn) en minusculas; anade aqui los vehiculos anadidos.
-- Incluye la clase "Deportivos clasicos" de GTA y modelos antiguos de otras clases.
OSDevtools = OSDevtools or {}
local list = {
    -- Deportivos clasicos
    'ardent', 'btype', 'btype2', 'btype3', 'casco', 'cheburek', 'cheetah2', 'coquette2', 'deluxo', 'dynasty', 'fagaloa',
    'feltzer3', 'gt500', 'infernus2', 'jb700', 'jb7002', 'mamba', 'manana', 'manana2', 'michelson', 'monroe', 'nebula',
    'peyote', 'peyote3', 'pigalle', 'rapidgt3', 'retinue', 'retinue2', 'savestra', 'stinger', 'stingergt', 'stromberg',
    'swinger', 'torero', 'tornado', 'tornado2', 'tornado3', 'tornado4', 'tornado5', 'tornado6', 'turismo2', 'viseris',
    'z190', 'zion3', 'ztype', 'toreador',
    -- Antiguos de otras clases (berlinas, muscle, todoterreno, furgonetas)
    'emperor', 'emperor2', 'glendale', 'regina', 'virgo', 'virgo2', 'virgo3', 'voodoo', 'voodoo2', 'chino', 'chino2',
    'hermes', 'hustler', 'blade', 'buccaneer', 'buccaneer2', 'dukes', 'faction', 'faction2', 'impaler', 'picador',
    'sabregt', 'sabregt2', 'slamvan', 'slamvan2', 'stalion', 'tampa', 'vamos', 'hotknife', 'ratloader', 'ratloader2',
    'bfinjection', 'bodhi2', 'rebel', 'rebel2', 'surfer', 'surfer2', 'journey', 'youga2', 'tractor', 'tornado',
}
OSDevtools.ClassicVehicles = {}
for _, name in ipairs(list) do OSDevtools.ClassicVehicles[name] = true end
function OSDevtools.IsClassicVehicle(model) return type(model) == 'string' and OSDevtools.ClassicVehicles[model:lower()] == true end
