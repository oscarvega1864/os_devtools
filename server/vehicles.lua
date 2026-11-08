-- Vehiculos de Devtools creados por el servidor (OneSync, CREATE_VEHICLE_SERVER_SETTER).
-- Los fijos guardan su ultima posicion y se recrean tras reiniciar; ninguno depende de un
-- network ID persistido. Un vehiculo existente se reconoce por su state bag o su matricula.
OSDevtools.Vehicles={}
function OSDevtools.Vehicles.new(options)
    -- options: state() -> snapshot, change(actor,label,fn), now() -> ms
    local domain,config=OSDevtools.State,OSDevtools.CoreConfig
    local vehicles={}
    local live={}        -- id -> handle de entidad (solo en ejecucion)
    local inspections={} -- nonce -> consulta de tipos de modelo pendiente
    local counter=0

    function vehicles.onesync() return GetConvar('onesync','off')~='off' end
    local function plateOf(entity) return ((GetVehicleNumberPlateText(entity) or ''):gsub('%s+$','')) end
    local function look(id,record)
        return {id=id,plate=record.plate,primary=record.primary,secondary=record.secondary,livery=record.livery,liveryType=record.liveryType}
    end

    -- Entidad viva de un registro: primero la conocida, despues cualquiera con su marca o matricula.
    function vehicles.find(id,record)
        local entity=live[id]
        if entity and DoesEntityExist(entity) then return entity end
        live[id]=nil
        for _,handle in ipairs(GetAllVehicles() or {}) do
            if DoesEntityExist(handle) then
                local bag=Entity(handle).state.osdev
                if (type(bag)=='table' and bag.id==id) or plateOf(handle)==record.plate then live[id]=handle;return handle end
            end
        end
        return nil
    end

    function vehicles.spawn(id,record,point)
        if not vehicles.onesync() then return nil,'OneSync desactivado: el servidor no puede crear vehiculos.' end
        if not domain.vehicleTypes[record.vtype] then return nil,'Tipo de vehiculo desconocido; se consultara a un administrador conectado.' end
        if vehicles.find(id,record) then return nil,'Ya existe una entidad para el vehiculo #'..id..'.' end
        local entity=CreateVehicleServerSetter(GetHashKey(record.model),record.vtype,point.x+0.0,point.y+0.0,point.z+0.0,(point.h or 0)+0.0)
        if not entity or entity==0 then return nil,'El servidor no pudo crear el vehiculo (CreateVehicleServerSetter).' end
        SetEntityOrphanMode(entity,2) -- el servidor no lo borra por falta de jugadores cerca
        if point.bucket and point.bucket~=0 then SetEntityRoutingBucket(entity,point.bucket) end
        SetVehicleNumberPlateText(entity,record.plate)
        SetVehicleColours(entity,record.primary,record.secondary)
        Entity(entity).state:set('osdev',look(id,record),true)
        live[id]=entity
        return entity
    end

    function vehicles.delete(id)
        local entity=live[id];live[id]=nil
        if entity and DoesEntityExist(entity) then DeleteEntity(entity) end
    end
    -- Tras cambiar color o livery, el state bag lleva el aspecto a quien controle el vehiculo.
    function vehicles.refreshLook(id,record)
        local entity=vehicles.find(id,record)
        if entity then Entity(entity).state:set('osdev',look(id,record),true) end
    end

    -- El tipo del modelo solo lo conoce un cliente; se pregunta a un administrador.
    function vehicles.inspect(source,models,callback)
        counter=counter+1
        local nonce=('%d:%d'):format(counter,options.now())
        inspections[nonce]={source=source,models=models,callback=callback,expires=options.now()+10000}
        TriggerClientEvent('osdev:inspectVehicleModels',source,nonce,models)
    end
    function vehicles.inspected(source,nonce,result)
        local pending=type(nonce)=='string' and inspections[nonce]
        if not pending or pending.source~=source then return false end
        inspections[nonce]=nil
        if options.now()>pending.expires or type(result)~='table' then pending.callback(nil);return true end
        local types={}
        for _,model in ipairs(pending.models) do
            local kind=result[model]
            types[model]=domain.vehicleTypes[kind] and kind or false
        end
        pending.callback(types);return true
    end

    -- Posiciones de los fijos vivos que se movieron mas de 1 m o giraron mas de 5 grados.
    function vehicles.collectPositions()
        local updates={}
        for key,record in pairs(options.state().vehicles) do
            local entity=record.fixed and live[record.id]
            if entity and DoesEntityExist(entity) then
                local c=GetEntityCoords(entity)
                local point={x=domain.number(c.x),y=domain.number(c.y),z=domain.number(c.z),h=domain.number(GetEntityHeading(entity)),bucket=GetEntityRoutingBucket(entity)}
                if domain.position(point,false) and config.AllowedBuckets[point.bucket] then
                    local old=record.position
                    local moved=not old or (old.x-point.x)^2+(old.y-point.y)^2+(old.z-point.z)^2>1
                        or math.abs(((old.h or 0)-point.h+180)%360-180)>5 or old.bucket~=point.bucket
                    if moved then updates[key]=point end
                end
            end
        end
        return updates
    end
    function vehicles.savePositions(reason)
        local updates=vehicles.collectPositions()
        if not next(updates) then return false end
        return options.change(0,'vehicles:'..reason,function(d)
            for key,point in pairs(updates) do if d.vehicles[key] then d.vehicles[key].position=point end end
            return true
        end)
    end

    -- Recrea los fijos ausentes. Devuelve cuantos se crearon y los registros sin tipo conocido.
    function vehicles.restore()
        local created,missing=0,{}
        for _,record in pairs(options.state().vehicles) do
            if record.fixed and record.position and not vehicles.find(record.id,record) then
                if domain.vehicleTypes[record.vtype] then
                    if vehicles.spawn(record.id,record,record.position) then created=created+1 end
                else missing[#missing+1]=record.id end
            end
        end
        table.sort(missing)
        return created,missing
    end

    -- Al parar el recurso solo se retiran los temporales; los fijos siguen en el mundo.
    function vehicles.stop()
        for _,record in pairs(options.state().vehicles) do
            if not record.fixed then vehicles.delete(record.id) end
        end
    end
    return vehicles
end
