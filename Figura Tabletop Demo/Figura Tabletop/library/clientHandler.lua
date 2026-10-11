---The client handler.
---@class ClientHandler
---@field directSync SyncStream
local ClientHandler = {}
ClientHandler.__index = ClientHandler

---Creates a new client handler
---@param core TabletopCore
---@param clientId string Client's UUID.
---@param pingsGlobal table Client's PingAPI global.
---@param modelsGlobal ModelPart Client's ModelAPI global.
---@param eventsGlobal EventsAPI Client's EventsAPI global.
---@param hostGlobal HostAPI Client's HostAPI global.
---@return ClientHandler
function ClientHandler:new(core, clientId, pingsGlobal, modelsGlobal, eventsGlobal, hostGlobal)
    setmetatable({}, ClientHandler)
    self.core = core
    self.clientId = clientId
    self.pings = pingsGlobal
    self.models = modelsGlobal
    self.events = eventsGlobal
    self.host = hostGlobal


    self.directSync = core.currentGame.sync:newSyncStream("directSync")
    self.directSync.includeStreamId = false
    self.directSync:setPingFunction(pingsGlobal.directSync)

    return self
end

---Ticks this client handler.
function ClientHandler:tick()
    
end

return ClientHandler