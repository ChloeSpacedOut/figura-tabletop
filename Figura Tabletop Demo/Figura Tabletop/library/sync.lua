-- SYNC DATA: receive ping of syncStream 1's ping function: <packet ID var len ZZ (neg = finish)>, <data>
-- On complete: <timeline time value>, <timeline len>, <sync type ID>, <sync type len>, <object ID>, <object sync length>, <param ID>, <data>, <paramID>, <data>
--#REGION Sync

---Sync by ChloeSpacedOut.
---@class Sync
---@field streams SyncStream[] Table that contains all sync streams.
---@field syncTypes SyncType[] Table that contains all sync types.
---@field syncTypeIndex {string : integer} Table that contains the index of each sync type.
---@field paramTypes ParamType[] Table that contains all parameter types.
---@field clock integer The sync library's global clock.
local sync = {
    streams = {},
    syncTypes = {},
    syncTypeIndex = {},
    paramTypes = {},
    clock = 0
}

---Returns a sync type when given its string ID.
---@param stringId string
---@return SyncType
function sync:getSyncType(stringId)
    return self.syncTypes[self.syncTypeIndex[stringId]]
end

--#ENDREGION

--#REGION SyncType Structure
--#REGION ParamType

---A parameter's type, used for sync type parameters. This determines how data will be compressed and pinged.
---@class ParamType<T>
---@field id string The unique ID of this parameter type.
---@field decode fun(encoded: Buffer, paramTypes: ParamType[]): T Decodes data after it has been pinged.
---@field encode fun(rawData: T, paramTypes: ParamType[]): string Encodes data to be pinged.
sync.ParamType = {}
sync.ParamType.__index = sync.ParamType

---Creates a new parameter type.
---@generic T
---@param id string The ID of this parameter type.
---@param decode fun(encoded: Buffer, paramTypes: ParamType[]): T Decodes data after it has been pinged.
---@param encode fun(rawData: T, paramTypes: ParamType[]): string Encodes data to be pinged.
---@return ParamType<T>
function sync.ParamType:new(id, decode, encode)
    self = setmetatable({}, sync.ParamType)
    self.id = id
    self.decode = decode
    self.encode = encode
    sync.paramTypes[id] = self
    return self
end

--#ENDREGION

--#REGION Param

---A parameter, used by a sync type.
---@class Param
---@field id string The ID of this parameter.
---@field paramType ParamType The type of this parameter. This determines how data will be encoding and pinged.
---@field onReceiveHook string The ID of the hook function that will be run once this parameter has been decoded.
sync.Param = {}
sync.Param.__index = sync.Param

---Creates a new parameter.
---@param id string The ID of this parameter.
---@param paramType ParamType The type of this parameter. This determines how data will be encoding and pinged.
---@param onReceiveHook string? The ID of the hook function that will be run once this parameter has been decoded.
---@return Param
function sync.Param:new(id, paramType, onReceiveHook)
    self = setmetatable({}, sync.Param)
    self.id = id
    self.paramType = paramType
    self.onReciveHook = onReceiveHook
    return self
end

--#ENDREGION

--#REGION SyncType

---A sync type. Sync types contain parameters with defined types to make encoding data to be pinged simple.
---@class SyncType
---@field id string The unique ID for this syncType.
---@field params Param[] A table that contains all parametes this sync type will use.
---@field paramIndex {string : integer} A table with all parameter indexs, indexed by ID.
sync.SyncType = {}
sync.SyncType.__index = sync.SyncType

---Creates a new sync type.
---@param id string The unique ID of this syncType.
---@param ... Param Parameters to automatically add on creation. Ensure the order parameters are added is determanistic.
---@return SyncType
function sync.SyncType:new(id, ...)
    self = setmetatable({}, sync.SyncType)
    self.id = id
    self.params = {}
    self.paramIndex = {}

    local parameters = { ... }
    if parameters then
        for _, parameter in ipairs(parameters) do
            self:addParam(parameter)
        end
    end
    table.insert(sync.syncTypes, self)
    sync.syncTypeIndex[id] = #sync.syncTypes
    return self
end

---Adds a new parameter.
---@param param Param
function sync.SyncType:addParam(param)
    table.insert(self.params, param)
    self.paramIndex[param.id] = #self.params
end

---Returns a parameter when given its string ID.
---@param paramId string The unique ID for this parameter.
---@return Param
function sync.SyncType:getParam(paramId)
    return self.params[self.paramIndex[paramId]]
end


---Syncs a specified parameter.
---@param paramId string The unique ID of this parameter.
---@param syncStream SyncStream The sync stream this parameter will be sent through.
---@param objectId integer The unique ID for the object to be synced.
---@param syncData any The data to be synced.
function sync.SyncType:syncParam(paramId, syncStream, objectId, syncData)
    local param = self:getParam(paramId)
    if not syncStream.toSend then return end
    local toSend = syncStream.toSend[1]
    if not toSend then return end
    toSend:add(self, objectId, param, syncData)
end

--#ENDREGION
--#ENDREGION

--#REGION SyncSteam Structure
--#REGION TimeStep

---A timeline's time step.
---@class TimeStep
---@field timestamp integer The this time step's unique time stamp within the parent timeline.
---@field syncTypes table This time step's data table, containing sync types, object IDs, parameter indexes and the final encoded data.
sync.TimeStep = {}
sync.TimeStep.__index = sync.TimeStep

---Creates a new time step.
---@param timestamp integer The this time step's unique time stamp within the parent timeline.
---@return TimeStep
function sync.TimeStep:new(timestamp)
    self = setmetatable({}, sync.TimeStep)
    self.timestamp = timestamp
    self.syncTypes = {}
    return self
end

---Adds new data to this time step.
---@param syncType SyncType The sync type the updated object falls under.
---@param objectId integer The unique ID of the synced object.
---@param param Param The parameter synced from this object.
---@param syncData any The data synced.
function sync.TimeStep:add(syncType, objectId, param, syncData)
    local syncTypeIndex = sync.syncTypeIndex[syncType.id]
    local paramIndex = syncType.paramIndex[param.id]
    local encodedData = param.paramType.encode(syncData, sync.paramTypes)
    if not self.syncTypes[syncTypeIndex] then
        self.syncTypes[syncTypeIndex] = {}
    end
    if not self.syncTypes[syncTypeIndex][objectId] then
        self.syncTypes[syncTypeIndex][objectId] = {}
    end
    self.syncTypes[syncTypeIndex][objectId][paramIndex] = encodedData
end

--#ENDREGION

--#REGION Timeline

---The timeline of a send or receive object.
---@class Timeline
---@field timeSteps TimeStep[] A table that contains all timesteps within this timeline
---@field initTime integer The system time at the beginning of the timeline.
sync.Timeline = {}
sync.Timeline.__index = sync.Timeline

---Creates a new timeline.
---@return Timeline
function sync.Timeline:new()
    self = setmetatable({}, sync.Timeline)
    self.timeSteps = {}
    self.initTime = client.getSystemTime()
    return self
end

---Adds a specified parameter to this timeline.
---@param syncType SyncType The sync type the updated object falls under.
---@param objectId integer The unique ID of the synced object.
---@param param Param The parameter synced from this object.
---@param syncData any The data synced.
function sync.Timeline:add(syncType, objectId, param, syncData)
    local currentTimestamp = client.getSystemTime() - self.initTime
    local latestTimeStep = self.timeSteps[#self.timeSteps]
    if latestTimeStep and (currentTimestamp == latestTimeStep.timestamp) then
        latestTimeStep:add(syncType, objectId, param, syncData)
    else
        local newTimeStep = sync.TimeStep:new(currentTimestamp)
        table.insert(self.timeSteps, newTimeStep)
        newTimeStep:add(syncType, objectId, param, syncData)
    end
end

---Finalises a timeline and returns structured data to be sent.
---@return string
function sync.Timeline:finalise()
    local toSend = ""
    for _, timeStep in ipairs(self.timeSteps) do
        --timeStep.
    end
    return toSend
end

--#ENDREGION

--#REGION Send

---The send object of a sync stream.
---@class Send
---@field id integer The ID of this send witin its sync stream.
---@field syncStream SyncStream The sync stream this send object is in reference to.
---@field timeline Timeline The timeline of data that is to be sent.
---@field isSending boolean If the data is being sent.
---@field currentPacket integer The ID of the current packet being sent.
---@field toSend string The encoded final version data that is to be sent.
sync.Send = {}
sync.Send.__index = sync.Send

---Creates a new send object.
---@param syncStream SyncStream The sync stream this send object is in reference to.
function sync.Send:new(syncStream)
    self = setmetatable({}, sync.Send)
    self.id = #syncStream.toSend + 1
    self.syncStream = syncStream
    self.isSending = false
    self.currentPacket = 0
    self.toSend = nil
    self.timeline = sync.Timeline:new()
    self.timelineIndex = {}

    table.insert(syncStream.toSend, self)
    return self
end

---Adds a specified parameter to be sent.
---@param syncType SyncType
---@param objectId integer
---@param param Param
---@param syncData any
function sync.Send:add(syncType, objectId, param, syncData)
    self.timeline:add(syncType, objectId, param, syncData)
end

---Finalises this send object to be synced.
function sync.Send:finalise()

end

--#ENDREGION

--#REGION Receive

---The receive object of a sync stream.
---@class Receive
---@field receiveTime integer The time at which this receive object was created.
---@field packets string[] A table that contains the received packets.
---@field timeline Timeline? The timeline. Only created after packets are finalised.
sync.Receive = {}
sync.Receive.__index = sync.Receive

---Creates a new receive object.
---@return Receive
function sync.Receive:new()
    self = setmetatable({}, sync.Receive)
    self.receiveTime = client.getSystemTime()
    self.packets = {}
    self.timeline = nil
    return self
end

--#ENDREGION

--#REGION SyncStream

---A sync stream. This contains send and receive objects, and controls how data will be pinged. Syncstreams must be created on the host and other clients.
---@class SyncStream
---@field id string The unique ID of this sync stream.
---@field ping function The ping function send objects will hook into. If no ping function is provided on creation, this will be sync stream's built in function.
---@field packetInterval integer How many ticks will be spent waiting between between sending each packet.
---@field syncSpeed integer How many bytes will be sent per second when syncing.
---@field includeStreamId boolean If the sync stream's ID should be included when syncing data.
---@field toSend Send[] A table that contains all of this sync stream's send objects.
---@field toReceive Receive[] A table that contains all of this sync stream's receive objects.
sync.SyncStream = {}
sync.SyncStream.__index = sync.SyncStream

---Creates a new sync stream.
---@param id string The unique ID of this sync stream.
---@param ping function? The ping function send objects will hook into. If no ping function is provided on creation, this will be sync stream's built in function.
---@return SyncStream
function sync.SyncStream:new(id, ping)
    self = setmetatable({}, sync.SyncStream)
    self.id = id
    if ping then
        self.ping = ping
    else

    end
    
    self.packetInterval = 5
    self.includeStreamId = true
    self.syncSpeed = 200
    self.toSend = {}
    self.receive = {}
    sync.streams[id] = self
    return self
end

---Creates a new send object within the sync stream.
---@return Send
function sync.SyncStream:newToSend()
    return sync.Send:new(self)
end

---Adds a new ping function to this sync stream.
---@param ping function
function sync.SyncStream:setPingFunction(ping)
    self.ping = ping
end

---Updates this sync stream and sends queued packets.
function sync.SyncStream:update()
    if not self.ping then return end
    if not sync.clock % self.packetInterval == 0 then return end
    local nextSend = self.toSend[1]
    if not nextSend then return end
    if not nextSend.isSending then return end
    if not nextSend.toSend then return end
    local bytesPerPacket = math.floor(self.syncSpeed * (self.packetInterval / 20))
    local toSend = nextSend.toSend
    local currentPacket = nextSend.currentPacket
    local packet = string.sub(toSend,currentPacket * bytesPerPacket, (currentPacket + 1) * bytesPerPacket)
    nextSend.currentPacket = currentPacket + 1
    
    self.ping(packet)
end

--#ENDREGION
--#ENDREGION

--#REGION Tick

function events.tick()
    sync.clock = sync.clock + 1
    for _, syncStream in pairs(sync.streams) do
        syncStream:update()
    end
end

function pings.sync()

end

--#ENDREGION

return sync