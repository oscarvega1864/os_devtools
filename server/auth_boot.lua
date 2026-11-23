-- Composicion del servicio comun. Eventos locales: nunca RegisterNetEvent.
local config=OSDevtools.AuthorizationConfig
local lastDenial,lastDiagnostic={},{}
local function txReady()
    return GetResourceState(config.TxResource)=='started'
        and GetResourceMetadata(config.TxResource,'version',0)==config.VerifiedTxVersion
end
OSDevtools.AuthHub=OSDevtools.AuthorizationHub.new({
    now=GetGameTimer,identity=OSDevtools.AuthIdentity.resolve,ace=IsPlayerAceAllowed,
    txReady=txReady,
    resourceState=GetResourceState,log=function(message) print(message) end
})
local hub=OSDevtools.AuthHub
function OSDevtools.AuthDenied(source,permission)
    local now=GetGameTimer()
    if not lastDenial[source] or now<lastDenial[source] or now-lastDenial[source]>=5000 then
        lastDenial[source]=now
        print(('[OSCAR AUTH] action=denied source=%d permission=%s'):format(source,permission))
    end
end
function OSDevtools.AuthDiagnosticAllowed(source)
    local now=GetGameTimer()
    if lastDiagnostic[source] and now>=lastDiagnostic[source] and now-lastDiagnostic[source]<2000 then return false end
    lastDiagnostic[source]=now;return true
end
-- Admins de txAdmin -> grupo ACE de la sesion (player.<id>). Solo eventos del recurso de txAdmin.
local txGranted={}
local function txGroup(source,on)
    local group=config.TxAdminGroup
    if type(group)~='string' or not group:match('^group%.[%w_]+$') then return end
    if on and not txGranted[source] then
        txGranted[source]=true
        ExecuteCommand(('add_principal player.%d %s'):format(source,group))
        -- Los mensajes van fuera del comando que lo provoca (/adminservicio): si no, FiveM los muestra en el chat
        -- de quien lo usa. Sin el ACE del recurso para add_principal, FiveM ignora el comando: se avisa en consola.
        CreateThread(function()
            local check=IsPlayerAceAllowed(source,'osdev.admin')
            if check==true or check==1 then
                print(('[OSCAR AUTH] action=txadmin_group_added source=%d group=%s'):format(source,group))
            else
                print(('[OSCAR AUTH] ERROR: no se pudo dar %s a %d. Falta en server.cfg: add_ace resource.%s command.add_principal allow (y command.remove_principal).'):format(
                    group,source,GetCurrentResourceName()))
            end
        end)
    elseif not on and txGranted[source] then
        txGranted[source]=nil
        ExecuteCommand(('remove_principal player.%d %s'):format(source,group))
        CreateThread(function() print(('[OSCAR AUTH] action=txadmin_group_removed source=%d group=%s'):format(source,group)) end)
    end
end
-- txAdmins: quien txAdmin dice que es admin. staffDuty: quien esta de servicio como staff (lo avisa os_admin).
-- El grupo solo se da si es admin de txAdmin y, con servicio obligatorio, esta de servicio.
local txAdmins,staffDuty={},{}
local function dutyRequired() return config.TxAdminRequiresDuty==true and GetResourceState(config.DutyResource or 'os_admin')=='started' end
local function refreshTx(source) txGroup(source,txAdmins[source]==true and (not dutyRequired() or staffDuty[source]==true)) end
local function txGroupsClear() for source in pairs(txGranted) do txGroup(source,false) end end
AddEventHandler('txAdmin:events:adminAuth',function(event)
    local origin=GetInvokingResource()
    hub.txEvent(origin,event)
    if origin~=config.TxResource or not txReady() or type(event)~='table' or type(event.isAdmin)~='boolean' or math.type(event.netid)~='integer' then return end
    if event.netid==-1 then if not event.isAdmin then txAdmins={};txGroupsClear() end return end
    if event.netid>0 and GetPlayerName(event.netid) then txAdmins[event.netid]=event.isAdmin or nil;refreshTx(event.netid) end
end)
-- Servicio de staff (evento de servidor de os_admin; un cliente no puede lanzarlo).
AddEventHandler('os_admin:staffDuty',function(player,on)
    if GetInvokingResource()~=(config.DutyResource or 'os_admin') or math.type(player)~='integer' then return end
    staffDuty[player]=on==true or nil;refreshTx(player)
end)
-- Para /adminservicio de os_admin: un admin de txAdmin que no es del staff tambien puede ponerse de servicio.
exports('IsTxAdmin',function(player)
    if GetInvokingResource()~=(config.DutyResource or 'os_admin') then return false end
    return txAdmins[tonumber(player)]==true
end)
-- Cambio en la lista de admins de txAdmin: se retiran los grupos dados; txAdmin vuelve a autenticar a los que sigan.
AddEventHandler('txAdmin:events:adminsUpdated',function()
    local origin=GetInvokingResource()
    hub.updated(origin)
    if origin==config.TxResource then txGroupsClear() end
end)
AddEventHandler('playerDropped',function()
    local player=tonumber(source);hub.drop(player);txGroup(player,false);lastDenial[player],lastDiagnostic[player]=nil,nil
    txAdmins[player],staffDuty[player]=nil,nil
end)
AddEventHandler('onResourceStop',function(resource)
    hub.resourceStopped(resource)
    if resource==GetCurrentResourceName() then hub.reset('broker_stopped');txGroupsClear() end
end)
AddEventHandler('onResourceStart',function(resource)
    if resource==config.TxResource then hub.reset('monitor_started') end
    -- os_admin vuelve: todos fuera de servicio, se recalcula el grupo de los admins de txAdmin.
    if resource==(config.DutyResource or 'os_admin') then staffDuty={};for player in pairs(txAdmins) do refreshTx(player) end end
end)
local function reply(source,message)
    if source==0 then print('[OSCAR AUTH] '..message) else TriggerClientEvent('osdev:msg',source,message) end
end
RegisterCommand('osautorizar',function(source,args)
    if #args~=4 or args[4]~='CONFIRMAR' then return reply(source,'Uso: osautorizar <idJugador> <perfil> <minutos> CONFIRMAR') end
    local ok,err=hub.grant(source,tonumber(args[1]),args[2],tonumber(args[3]))
    reply(source,ok and 'Perfil temporal asignado. No modifica ACE ni server.cfg.' or err)
end,false)
RegisterCommand('osrevocar',function(source,args)
    if #args~=1 then return reply(source,'Uso: osrevocar <idJugador>') end
    local ok,err=hub.revoke(source,tonumber(args[1]));reply(source,ok and 'Delegacion revocada. Los ACE independientes se conservan.' or err)
end,false)
exports('HasOscarPermission',function(source,permission)
    return hub.consumer(GetInvokingResource(),source,permission)
end)
exports('RegisterOscarAuthorizationProvider',function(callback)
    return hub.registerProvider(GetInvokingResource(),callback)
end)
