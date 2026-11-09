-- Composicion del servicio comun. Eventos locales: nunca RegisterNetEvent.
local config=OSDevtools.AuthorizationConfig
local lastDenial,lastDiagnostic={},{}
OSDevtools.AuthHub=OSDevtools.AuthorizationHub.new({
    now=GetGameTimer,identity=OSDevtools.AuthIdentity.resolve,ace=IsPlayerAceAllowed,
    txReady=function()
        return GetResourceState(config.TxResource)=='started'
            and GetResourceMetadata(config.TxResource,'version',0)==config.VerifiedTxVersion
    end,
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
        print(('[OSCAR AUTH] action=txadmin_group_added source=%d group=%s'):format(source,group))
    elseif not on and txGranted[source] then
        txGranted[source]=nil
        ExecuteCommand(('remove_principal player.%d %s'):format(source,group))
        print(('[OSCAR AUTH] action=txadmin_group_removed source=%d group=%s'):format(source,group))
    end
end
local function txGroupsClear() for source in pairs(txGranted) do txGroup(source,false) end end
AddEventHandler('txAdmin:events:adminAuth',function(event)
    local origin=GetInvokingResource()
    hub.txEvent(origin,event)
    if origin~=config.TxResource or type(event)~='table' or type(event.isAdmin)~='boolean' or math.type(event.netid)~='integer' then return end
    if event.netid==-1 then if not event.isAdmin then txGroupsClear() end return end
    if event.netid>0 and GetPlayerName(event.netid) then txGroup(event.netid,event.isAdmin) end
end)
AddEventHandler('txAdmin:events:adminsUpdated',function() hub.updated(GetInvokingResource()) end)
AddEventHandler('playerDropped',function()
    local player=tonumber(source);hub.drop(player);txGroup(player,false);lastDenial[player],lastDiagnostic[player]=nil,nil
end)
AddEventHandler('onResourceStop',function(resource)
    hub.resourceStopped(resource)
    if resource==GetCurrentResourceName() then hub.reset('broker_stopped');txGroupsClear() end
end)
AddEventHandler('onResourceStart',function(resource)
    if resource==config.TxResource then hub.reset('monitor_started') end
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
