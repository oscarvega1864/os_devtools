OSDevtools.SpawnClient={}
function OSDevtools.SpawnClient.new(options)
    local generation,current,busy=0,nil,false
    local controller={}
    function controller.receive(context)
        if type(context)~='table' or type(context.token)~='string' or type(context.position)~='table' or context.token==current then return end
        generation=generation+1;local version=generation;current=context.token;busy=true
        options.spawn(context.position,function(collisionsReady)
            if version~=generation or not busy then return end
            if not collisionsReady then
                busy=false;options.release();options.failed(current);return
            end
            local function acknowledge()
                if version~=generation or not busy then return end
                options.ack(current);options.schedule(500,acknowledge)
            end
            acknowledge()
        end,function() return version==generation and busy end,context)
        options.schedule(OSDevtools.SpawnConfig.TimeoutMilliseconds,function()
            if version~=generation or not busy then return end
            busy=false;options.release();options.failed(current);options.notify('Timeout de aparicion; revisar consola y colisiones.')
        end)
    end
    function controller.accepted(token)
        if token~=current or not busy then return end
        busy=false;generation=generation+1;options.release()
    end
    function controller.stop() busy=false;generation=generation+1;options.release() end
    return controller
end
