local sync = require("..sync")

function pings.passiveSync(syncData)
    local passiveSync = sync:getSyncStream("passiveSync")
    if not passiveSync then return end
    passiveSync:receive(syncData)
end

---comment
---@param syncStream SyncStream
---@param syncType SyncType
---@param data any
local function sendSyncTypeData(syncStream, syncType, data)
    for objectId, object in pairs(data) do
        for paramId, _ in pairs(syncType.paramIndex) do
            local syncData = object[paramId]
            if syncData then
                syncStream:send(syncType.id, objectId, paramId, syncData)
            end
        end
    end
end

local SyncHandler = {}
SyncHandler.__index = SyncHandler



---comment
function SyncHandler:setup(game)
    self = setmetatable({}, SyncHandler)
    self.game = game

    self.doPassiveSync = function()
        sendSyncTypeData(self.passiveSync, sync:getSyncType("piece"), game.pieces)
        sendSyncTypeData(self.passiveSync, sync:getSyncType("slot"), game.slots)
    end

    self.passiveSync = sync.SyncStream:new("passiveSync", pings.passiveSync)
    self.passiveSync.includeStreamId = false

    self.passiveSync.onFinishSend = self.doPassiveSync
    if not host:isHost() then return self end
    self:doPassiveSync()
    return self
end



function SyncHandler:clientSetup(pingFunction)
    local directSync = sync.SyncStream:new("directSync", pingFunction)
    directSync.includeStreamId = false
end

function SyncHandler:update()
    if not host:isHost() then return end
    if not self.passiveSync:getNewestSend() then
        self:doPassiveSync()
    end
end

return SyncHandler