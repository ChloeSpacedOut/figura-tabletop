---@class ClientHandler
---@field directSync SyncStream
local ClientHandler = {}
ClientHandler.__index = ClientHandler

---comment
---@param core any
---@param userId any
---@param pingsGlobal any
---@param modelsGlobal any
---@param eventsGlobal any
---@param hostGlobal any
---@return ClientHandler
function ClientHandler:new(core, userId, pingsGlobal, modelsGlobal, eventsGlobal, hostGlobal)
    setmetatable({}, ClientHandler)
    self.core = core
    self.userId = userId
    self.pings = pingsGlobal
    self.models = modelsGlobal
    self.events = eventsGlobal
    self.host = hostGlobal


    self.directSync = core.currentGame.sync:newSyncStream("directSync")
    self.directSync.includeStreamId = false
    self.directSync:setPingFunction(pingsGlobal.directSync)

    return self
end

function ClientHandler:tick()
    
end




return ClientHandler