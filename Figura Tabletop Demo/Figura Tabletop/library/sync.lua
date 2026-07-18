---@class Sync
local sync = {}

---@class ParamType<T>
---@field decode fun(encoded: Buffer): T decodes data after it has been pinged
---@field encode fun(rawData: T): string encodes data to be pinged
sync.ParamType = {}
sync.ParamType.__index = sync.ParamType

---creates a new parameter type
---@generic T
---@param id string the ID of this parameter type
---@param decode fun(encoded: Buffer, paramTypes: ParamType[]): T decodes data after it has been pinged
---@param encode fun(rawData: T, paramTypes: ParamType[]): string encodes data to be pinged
---@return ParamType<T>
function sync.ParamType:new(id, decode, encode)
    self = setmetatable({}, sync.ParamType)
    self.decode = decode
    self.encode = encode
    return self
end

---@class Param
---@field id string the ID of this parameter
---@field paramType ParamType the type of this parameter. This determines how data will be compressed and pinged
---@field onReceiveHook string the ID of the hook function that will be run once this parameter has been decoded
sync.Param = {}
sync.Param.__index = sync.Param

---creates a new parameter
---@param id string the ID of this parameter
---@param paramType ParamType the type of this parameter. This determines how data will be compressed and pinged
---@param onReceiveHook string? the ID of the hook function that will be run once this parameter has been decoded
---@return Param
function sync.Param:new(id, paramType, onReceiveHook)
    self = setmetatable({}, sync.Param)
    self.id = id
    self.paramType = paramType
    self.onReciveHook = onReceiveHook
    return self
end

---@class ParamHandler
---@field params Param[]
---@field paramIndex {string : integer}
sync.ParamHandler = {}
sync.ParamHandler.__index = sync.ParamHandler

---creates a new parameter handler
---@param ... Param parameters to add on creation
function sync.ParamHandler:new(...)
    self = setmetatable({}, sync.ParamHandler)
    self.params = {}
    self.paramIndex = {}

    local parameters = { ... }
    if parameters then
        for _, parameter in ipairs(parameters) do
            self:addParam(parameter)
        end
    end
    return self
end

---adds a new parameter
---@param param Param
function sync.ParamHandler:addParam(param)
    table.insert(self.params, param)
    self.paramIndex[param.id] = #self.params
end


---@class Send
---@field syncStream SyncStream the sync stream this send object is in reference to
---@field id integer the ID of this send witin its sync stream
---@field syncTime integer the time when this data began being stored to be synced
---@field isSending boolean if the data is being sent
---@field currentPacket integer the current packet being sent
---@field toSend string the encoded final version data that is to be sent
---@field timeline string[] the timeline of data that is to be sent
---@field timelineIndex integer[] the index of the timeline. Used to maintain order
sync.Send = {}
sync.Send.__index = sync.Send
---@param syncStream SyncStream the sync stream this send object is in reference to
function sync.Send:new(syncStream)
    self = setmetatable({}, sync.Send)
    self.syncStream = syncStream
    self.id = #syncStream.toSend + 1
    self.syncTime = 0
    self.isSending = false
    self.currentPacket = 0
    self.toSend = nil
    self.timeline = {}
    self.timelineIndex = {}

    table.insert(syncStream.toSend, self)
    return self
end

function sync.Send:add()

end

-- timing chunks -> toSendString -> receiving chunks -> timing chunks
-- allow 16 streams of async transfer, each with their own settings. Each stream can have a queue
-- function to add and remove new sends
-- remember you're dealing with both passive and active sync
-- fields can be used a system control messages, like clone field, which when an ID is added, piece is cloned to that slot

---@class Receive
---@field received string[]
sync.Receive = {}
sync.Receive.__index = sync.Receive
function sync.Receive:new()
    self = setmetatable({}, sync.Receive)
    self.syncTime = 0
    self.received = {}
    self.timeline = {}
    self.timelineIndex = {}
    return self
end

---@class SyncStream
---@field game Game the game this sync stream will be in reference to
---@field id string the unique ID of this sync stream
---@field ping function the ping function send objects will hook into
---@field packetInterval integer how many ticks between each sync ping (sync packet)
---@field syncSpeed integer how many bytes will be sent per second when syncing
---@field toSend Send[]
---@field toReceive Receive[]
sync.SyncStream = {}
sync.SyncStream.__index = sync.SyncStream

---creates a new sync stream
---@param game Game
---@param id string the unique ID of this sync stream
---@param ping function? the ping function send objects will hook into
---@return SyncStream
function sync.SyncStream:new(game, id, ping)
    self = setmetatable({}, sync.SyncStream)
    self.game = game
    self.id = id
    if ping then  
        self.ping = ping
    end
    self.toSend = {}
    self.receive = nil -- THERE SHOULD ONLY BE ONE RECEIVE VALUE
    self.packetInterval = 5
    self.syncSpeed = 200
    return self
end

---creates a new send object within the sync stream
---@return Send
function sync.SyncStream:newToSend()
    return sync.Send:new(self)
end

---adds a new ping function to this sync stream
---@param ping function
function sync.SyncStream:setPingFunction(ping)
    self.ping = ping
end

return sync