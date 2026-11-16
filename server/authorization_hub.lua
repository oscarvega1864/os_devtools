-- Solo eventos publicos de txAdmin y ACE; sin admins.json ni credenciales HTTP.
OSDevtools.AuthorizationHub={}
function OSDevtools.AuthorizationHub.new(options)
    local u,config=OSDevtools.Util,OSDevtools.AuthorizationConfig
    local proofs,leases,providers={},{},{}
    local hub={}
    local function audit(action,source,detail)
        options.log(('[OSCAR AUTH] action=%s source=%d %s'):format(action,source or 0,detail or ''))
    end
    local function native(source,permission)
        local ok,result=pcall(options.ace,source,permission)
        return ok and (result==true or result==1)
    end
    local function manager(actor)
        return u.integer(actor,0,2147483647) and (actor==0
            or (OSDevtools.AuthIdentity.valid(options.identity(actor)) and native(actor,config.ManagerAce)))
    end
    function hub.reset(reason)
        proofs,leases={},{}
        audit('invalidate_all',0,'reason='..reason)
    end
    function hub.drop(source)
        if proofs[source] or leases[source] then audit('revoke',source,'reason=disconnect_or_invalid_proof') end
        proofs[source],leases[source]=nil,nil
    end
    local function proofFor(source)
        local proof=proofs[source]
        if not proof then return nil end
        local now=options.now()
        if not options.txReady() or now<proof.at or now>=proof.expires or options.identity(source)~=proof.principal then
            hub.drop(source);return nil
        end
        return proof
    end
    function hub.txEvent(origin,event)
        if origin~=config.TxResource or not options.txReady() then return false end
        if not u.object(event) or type(event.isAdmin)~='boolean'
            or not u.integer(event.netid,-1,2147483647) or event.netid==0 then return false end
        if event.netid==-1 then
            if event.isAdmin then return false end
            hub.reset('txadmin_forced_reauth');return true
        end
        local source=event.netid
        if not event.isAdmin then hub.drop(source);return true end
        local principal=options.identity(source)
        if not OSDevtools.AuthIdentity.valid(principal) then return false end
        local old=proofs[source]
        if old and old.principal~=principal then hub.drop(source) end
        local now=options.now()
        proofs[source]={principal=principal,at=now,expires=now+config.ProofSeconds*1000}
        -- Ningun permiso se concede por isAdmin, username o datos adicionales.
        if not old or old.principal~=principal or now<old.at or now-old.at>=5000 then audit('txadmin_authenticated',source) end
        return true
    end
    function hub.updated(origin)
        if origin~=config.TxResource then return false end
        hub.reset('txadmin_admins_updated');return true
    end
    function hub.grant(actor,target,profile,minutes)
        if not manager(actor) then return nil,'Se requiere consola u oscar.auth.manage con identidad valida.' end
        if not u.integer(target,1,2147483647) or type(profile)~='string' or not config.Profiles[profile]
            or not u.integer(minutes,1,config.MaxLeaseMinutes) then return nil,'Perfil, jugador o minutos invalidos.' end
        local proof=proofFor(target)
        if not proof then return nil,'Falta autenticacion reciente de txAdmin; reautenticar en /tx y sincronizar de nuevo.' end
        local scopes={}
        for _,permission in ipairs(config.Profiles[profile]) do
            if not config.Permissions[permission] then return nil,'Perfil no verificado.' end
            scopes[permission]=true
        end
        -- Sustituye el perfil anterior; nunca suma capacidades residuales.
        leases[target]={principal=proof.principal,scopes=scopes,profile=profile,
            expires=math.min(proof.expires,options.now()+minutes*60000)}
        audit('grant',target,('actor=%d profile=%s subject=%s minutes=%d'):format(actor,profile,OSDevtools.AuthIdentity.mask(proof.principal),minutes))
        return true
    end
    function hub.revoke(actor,target)
        if not manager(actor) then return nil,'Se requiere consola u oscar.auth.manage con identidad valida.' end
        if not u.integer(target,1,2147483647) then return nil,'Jugador invalido.' end
        leases[target]=nil;audit('revoke',target,('actor=%d reason=explicit'):format(actor));return true
    end
    function hub.can(source,permission)
        local definition=type(permission)=='string' and config.Permissions[permission]
        if not definition or not u.integer(source,0,2147483647) then return false,'unknown_permission_or_source' end
        if source==0 then return true,'console' end
        local principal=options.identity(source)
        if not OSDevtools.AuthIdentity.valid(principal) then return false,'invalid_persistent_identity' end
        -- El permiso y su cadena de padres (osdev.assets.properties -> osdev.assets -> osdev.admin).
        local chain,node={},permission
        while node and #chain<6 do chain[#chain+1]=node;node=config.Permissions[node] and config.Permissions[node].parent end
        for _,scope in ipairs(chain) do if native(source,scope) then return true,'ace' end end
        local proof=proofFor(source)
        local lease=leases[source]
        if proof and lease and lease.principal==principal and options.now()<lease.expires then
            for _,scope in ipairs(chain) do if lease.scopes[scope] then return true,'txadmin_explicit_lease' end end
        end
        for resource,callback in pairs(providers) do
            local allowed=config.ExternalProviders[resource]
            if allowed and allowed[permission] and options.resourceState(resource)=='started' then
                local ok,result=pcall(callback,source,principal,permission)
                if ok and result==true then return true,'external_provider' end
            end
        end
        return false,'no_effective_permission'
    end
    function hub.consumer(resource,source,permission)
        if not resource or not config.Consumers[resource] or not config.Consumers[resource][permission] then return false end
        return hub.can(source,permission)
    end
    function hub.registerProvider(resource,callback)
        if not resource or not config.ExternalProviders[resource] or type(callback)~='function' then return false end
        providers[resource]=callback;audit('provider_registered',0,'resource='..resource);return true
    end
    function hub.resourceStopped(resource)
        providers[resource]=nil
        if resource==config.TxResource then hub.reset('txadmin_resource_stopped') end
    end
    function hub.status(source)
        local proof=proofFor(source);local lease=proof and leases[source]
        return {txCompatible=options.txReady(),authenticated=proof~=nil,
            profile=lease and options.now()<lease.expires and lease.profile or nil,
            expires=lease and options.now()<lease.expires and lease.expires or nil}
    end
    return hub
end
