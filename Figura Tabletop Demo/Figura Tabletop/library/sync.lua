--#REGION Sync

---Sync by ChloeSpacedOut.
local util = require("..util")

---@class Sync
---@field syncStreams SyncStream[] Table that contains all sync streams.
---@field syncStreamIndex {string: integer} Table that contains the index of each sync stream.
---@field syncTypes SyncType[] Table that contains all sync types.
---@field syncTypeIndex {string : integer} Table that contains the index of each sync type.
---@field paramTypes ParamType[] Table that contains all parameter types.
---@field clock integer The sync library's global clock.
---@field receiveTimeOffset integer The offset between the client's sync clock and the avatar host's.
---@field lastReceivedTime integer The last clock value received through a ping. Used to detect if the host's avatar's clock has reset.
---@field ping function? The default ping function for sync streams.
local sync = {
    syncStreams = {},
    syncStreamIndex = {},
    syncTypes = {},
    syncTypeIndex = {},
    paramTypes = {},
    hookTypes = {},
    clock = 0,
    receiveTimeOffset = 0,
    lastReceivedTime = 0,
    ping = nil
}

---Returns a sync steeam when given its string ID.
---@param stringId string
---@return SyncStream?
function sync:getSyncStream(stringId)
    local syncStreamIndex = self.syncStreamIndex[stringId]
    if not syncStreamIndex then return end
    return self.syncStreams[syncStreamIndex]
end

---Returns a sync type when given its string ID.
---@param stringId string
---@return SyncType?
function sync:getSyncType(stringId)
    local syncTypeIndex = self.syncTypeIndex[stringId]
    if not syncTypeIndex then return end
    return self.syncTypes[syncTypeIndex]
end

--#ENDREGION

--#REGION HookType

---A hook type, used for storing and referencing functions and objects that can't be synced.
---@class HookType
---@field hooks {indeger: any} Table that contains all hooks.
---@field hookIndex {string : integer} Table that contains the index of each hook.
sync.HookType = {}
sync.HookType.__index = sync.HookType

---Creates a new hook type.
---@param id string The unique ID of this hook type.
---@return HookType
function sync.HookType:new(id)
    setmetatable({}, sync.HookType)
    self.id = id
    self.hooks = {}
    self.hookIndex = {}
    sync.hookTypes[id] = self
    return self
end

---Adds a new hook to this hook type. Hooks must always be added in the same order on all clients.
---@param stringId any
---@param hook any
function sync.HookType:add(stringId, hook)
    table.insert(self.hooks, hook)
    self.hookIndex[stringId] = #self.hooks
end

---Retruns a hook when given its string ID.
---@param stringId string
---@return function?
function sync.HookType:getHook(stringId)
    local hookIndex = self.hookIndex[stringId]
    if not hookIndex then return end
    return self.hooks[hookIndex]
end

sync.HookType:new("onReceive")

--#ENDREGION

--#REGION Ping

function pings.sync(syncData, syncStreamIndex)
    local syncStream = sync.syncStreams[syncStreamIndex]
    if not syncStream then return end
    syncStream:receive(syncData)
end

sync.ping = pings.sync

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
---@param id string The unique ID of this parameter.
---@param paramType ParamType The type of this parameter. This determines how data will be encoding and pinged.
---@param onReceiveHook string The ID of the hook function that will be run once this parameter has been decoded.
---@return Param
function sync.Param:new(id, paramType, onReceiveHook)
    self = setmetatable({}, sync.Param)
    self.id = id
    self.paramType = paramType
    self.onReceiveHook = onReceiveHook
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
    local toSend = syncStream:getNewestSend()
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
    if not self.syncTypes[syncTypeIndex] then
        self.syncTypes[syncTypeIndex] = {}
    end
    if not self.syncTypes[syncTypeIndex][objectId] then
        self.syncTypes[syncTypeIndex][objectId] = {}
    end
    self.syncTypes[syncTypeIndex][objectId][paramIndex] = syncData
end

--#ENDREGION

--#REGION Timeline

---The timeline of a send or receive object.
---@class Timeline
---@field timeSteps TimeStep[] A table that contains all timesteps within this timeline
---@field initTime integer The system time at the beginning of the timeline.
---@field timeStepIndex integer The index used when playing back a timeline.
sync.Timeline = {}
sync.Timeline.__index = sync.Timeline

---Creates a new timeline.
---@param initTime integer The init time this timeline will use.
---@return Timeline
function sync.Timeline:new(initTime)
    self = setmetatable({}, sync.Timeline)
    self.timeSteps = {}
    self.initTime = initTime
    self.timeStepIndex = 1
    return self
end

---Returns a time step object when given a timestamp.
---@param timeStamp integer
---@return TimeStep
function sync.Timeline:toTimeStep(timeStamp)
    local latestTimeStep = self.timeSteps[#self.timeSteps]
    if latestTimeStep and timeStamp == latestTimeStep.timestamp then
        return latestTimeStep
    else
        local newTimeStep = sync.TimeStep:new(timeStamp)
        table.insert(self.timeSteps, newTimeStep)
        return newTimeStep
    end
end

---Adds a specified parameter to this timeline.
---@param syncType SyncType The sync type the updated object falls under.
---@param objectId integer The unique ID of the synced object.
---@param param Param The parameter synced from this object.
---@param syncData any The data synced.
function sync.Timeline:add(syncType, objectId, param, syncData)
    local currentTimestamp = sync.clock - self.initTime
    local timestep = self:toTimeStep(currentTimestamp)
    timestep:add(syncType, objectId, param, syncData)
end

---Finalises a timeline and returns structured data to be sent.
---@return string
function sync.Timeline:finalise()
    local toSend = ""
    local currentTime = util.numToVarLengthInt(sync.clock)
    toSend = toSend .. currentTime
    for _, timeStep in ipairs(self.timeSteps) do
        local timeStepData = ""
        for syncTypeIndex, objects in pairs(timeStep.syncTypes) do
            local syncTypeData = ""
            for objectId, params in pairs(objects) do
                local objectData = ""
                for paramIndex, syncData in pairs(params) do
                    local syncType = sync.syncTypes[syncTypeIndex]
                    local param = syncType.params[paramIndex]
                    local encodedData = param.paramType.encode(syncData, sync.paramTypes)
                    objectData = objectData .. util.numToVarLengthInt(paramIndex) .. encodedData
                end
                objectId = util.numToVarLengthInt(objectId)
                local objectDataLength = util.numToVarLengthInt(string.len(objectData))
                syncTypeData = syncTypeData .. objectId .. objectDataLength .. objectData
            end
            syncTypeIndex = util.numToVarLengthInt(syncTypeIndex)
            local syncTypeDataLength = util.numToVarLengthInt(string.len(syncTypeData))
            timeStepData = timeStepData .. syncTypeIndex .. syncTypeDataLength .. syncTypeData
        end
        local timestamp = util.numToVarLengthInt(timeStep.timestamp)
        local timeStepLength = util.numToVarLengthInt(string.len(timeStepData))
        toSend = toSend .. timestamp .. timeStepLength .. timeStepData
    end
    return toSend
end

--#ENDREGION

--#REGION Send

---The send object of a sync stream.
---@class Send
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
    self.syncStream = syncStream
    self.isSending = false
    self.currentPacket = 1
    self.toSend = nil
    self.timeline = sync.Timeline:new(sync.clock)
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
    self.toSend = self.timeline:finalise()
    self.isSending = true
end

--#ENDREGION

--#REGION Receive

---The receive object of a sync stream.
---@class Receive
---@field syncStream SyncStream The sync stream this receive object is in reference to.
---@field isReceived boolean If the data has been fully received.
---@field receiveTime integer The time at which this receive object was created.
---@field packets string[] A table that contains the received packets.
---@field timeline Timeline? The timeline. Only created after packets are finalised.
sync.Receive = {}
sync.Receive.__index = sync.Receive

---Creates a new receive object.
---@param syncStream SyncStream The sync stream this receive object will use.
---@return Receive
function sync.Receive:new(syncStream)
    self = setmetatable({}, sync.Receive)
    self.syncStream = syncStream
    self.isReceived = false
    self.receiveTime = sync.clock
    self.packets = {}
    self.timeline = sync.Timeline:new(sync.clock + sync.receiveTimeOffset)
    return self
end

function sync.Receive:add(packetId, packetData)
    self.packets[packetId] = packetData
end

function sync.Receive:finalise(finalPacketId)
    local receivedData = ""
    for i = 1, finalPacketId do
        if not self.packets[i] then return end
        receivedData = receivedData .. self.packets[i]
    end

    self.isReceived = true

    local buffer = data:createBuffer()
    buffer:writeByteArray(receivedData)
    buffer:setPosition(0)
    local bufferLength = buffer:getLength()
    local receiveTime = util.readVariableLengthInt(buffer)
    if (sync.receiveTimeOffset == 0) or (receiveTime < sync.lastReceivedTime) then
        sync.receiveTimeOffset = receiveTime - sync.clock
        self.receiveTime = sync.clock + sync.receiveTimeOffset
    end

    repeat
        local timestamp = util.readVariableLengthInt(buffer)
        local timestepLength = util.readVariableLengthInt(buffer)
        local timestepEndPos = timestepLength + buffer:getPosition()
        repeat
            local syncTypeIndex = util.readVariableLengthInt(buffer)
            local syncTypeLength = util.readVariableLengthInt(buffer)
            local syncTypeEndPos = syncTypeLength + buffer:getPosition()
            repeat
                local objectId = util.readVariableLengthInt(buffer)
                local objectLength = util.readVariableLengthInt(buffer)
                local objectEndPos = objectLength + buffer:getPosition()
                repeat
                    local paramIndex = util.readVariableLengthInt(buffer)
                    local syncType = sync.syncTypes[syncTypeIndex]
                    local param = syncType.params[paramIndex]
                    local paramType = param.paramType
                    local decoded = paramType.decode(buffer, sync.paramTypes)
                    local timestep = self.timeline:toTimeStep(timestamp)

                    if not timestep.syncTypes[syncTypeIndex] then
                        timestep.syncTypes[syncTypeIndex] = {}
                    end

                    if not timestep.syncTypes[syncTypeIndex][objectId] then
                        timestep.syncTypes[syncTypeIndex][objectId] = {}
                    end

                    timestep.syncTypes[syncTypeIndex][objectId][paramIndex] = decoded
                until (buffer:getPosition() >= objectEndPos) or (buffer:getPosition() == bufferLength)
            until (buffer:getPosition() >= syncTypeEndPos) or (buffer:getPosition() == bufferLength)
        until (buffer:getPosition() >= timestepEndPos) or (buffer:getPosition() == bufferLength)
    until buffer:getPosition() == bufferLength

    buffer:close()
    sync.lastReceivedTime = receiveTime
end

--#ENDREGION

--#REGION SyncStream

---A sync stream. This contains send and receive objects, and controls how data will be pinged. Syncstreams must be created on the host and other clients.
---@class SyncStream
---@field id string The unique ID of this sync stream.
---@field ping function The ping function send objects will hook into. If no ping function is provided on creation, this will be sync stream's built in function.
---@field packetInterval integer How many ticks will be spent waiting between between sending each packet.
---@field syncSpeed integer How many bytes will be sent per second when syncing.
---@field sendInterval integer How many ticks will be spent waiting after a send object is created before finalising it to be sent.
---@field receiveDelay integer How many ticks will be waited after data is received before playing out a timeline.
---@field rateLimitRoleback integer How many packets will be rolled back after the figura cloud ratelimits the client.
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
        self.ping = sync.ping
    end

    self.packetInterval = 10
    self.syncSpeed = 450
    self.sendInterval = 10
    self.receiveDelay = 5
    self.rateLimitRoleback = 3
    self.includeStreamId = true
    self.toSend = {}
    self.toReceive = {}
    table.insert(sync.syncStreams, self)
    sync.syncStreamIndex[id] = #sync.syncStreams
    return self
end

---Gets the send object first in the queue.
---@return Send
function sync.SyncStream:getQueuedSend()
    return self.toSend[1]
end

---Gets the send object last in the queue.
---@return Send
function sync.SyncStream:getNewestSend()
    return self.toSend[#self.toSend]
end

---Gets the receive object first in the queue.
---@return Receive
function sync.SyncStream:getQueuedReceive()
    return self.toReceive[1]
end

---Gets the receive object last in the queue.
---@return Receive
function sync.SyncStream:getNewestReceive()
    return self.toReceive[#self.toReceive]
end

---Adds a new ping function to this sync stream.
---@param ping function
function sync.SyncStream:setPingFunction(ping)
    self.ping = ping
end

---Updates this sync stream and sends queued packets.
function sync.SyncStream:update()
    if not self.ping then return end

    local sendInterval = self.sendInterval
    if sendInterval > 0 then
        for _, send in pairs(self.toSend) do
            if send.isSending then goto continue end
            local initTime = send.timeline.initTime
            if sync.clock >= (initTime + sendInterval) then
                send:finalise()
            end
            ::continue::
        end
    end

    for index, receive in pairs(self.toReceive) do
        if not receive.isReceived then goto continue end
        local timeline = receive.timeline
        if not timeline then goto continue end

        repeat
            local timeStep = timeline.timeSteps[timeline.timeStepIndex]
            if (sync.clock + sync.receiveTimeOffset) < (timeline.initTime + timeStep.timestamp + self.receiveDelay) then break end
            timeline.timeStepIndex = timeline.timeStepIndex + 1
            for syncTypeIndex, objects in pairs(timeStep.syncTypes) do
                for objectId, params in pairs(objects) do
                    for paramIndex, decodedData in pairs(params) do
                        local syncType = sync.syncTypes[syncTypeIndex]
                        local param = syncType.params[paramIndex]
                        ---@type HookType
                        local onReceiveHooks = sync.hookTypes.onReceive
                        local onReceive = onReceiveHooks:getHook(param.onReceiveHook)
                        if onReceive then
                            onReceive(decodedData, param.id, objectId, syncType.id, false)
                        end
                    end
                end
            end
        until timeline.timeStepIndex == #timeline.timeSteps

        if timeline.timeStepIndex == #timeline.timeSteps then
            table.remove(self.toReceive, index)
        end

        ::continue::
    end

    if not (sync.clock % self.packetInterval == 0) then return end
    local queuedSend = self:getQueuedSend()
    if not queuedSend then return end
    if not queuedSend.isSending then return end
    if not queuedSend.toSend then return end
    local bytesPerPacket = math.floor(self.syncSpeed * (self.packetInterval / 20))
    local toSend = queuedSend.toSend
    local currentPacket = queuedSend.currentPacket

    local packetStart = (currentPacket - 1) * bytesPerPacket
    local packetEnd = currentPacket * bytesPerPacket - 1
    local dataEnd = string.len(toSend)

    local packetId
    local isFinalPacket = packetEnd >= dataEnd
    if isFinalPacket then
        packetEnd = dataEnd
        packetId = util.numToVarLengthIntZZ(-currentPacket)
    else
        packetId = util.numToVarLengthIntZZ(currentPacket)
    end

    local packetData = string.sub(toSend, packetStart, packetEnd)
    local packet = packetId .. packetData
    queuedSend.currentPacket = queuedSend.currentPacket + 1

    if self.includeStreamId then
        local syncStreamIndex = sync.syncStreamIndex[self.id]
        self.ping(packet, syncStreamIndex)
    else
        self.ping(packet)
    end

    if isFinalPacket then
        table.remove(self.toSend, 1)
    end
end

---Sends specified data over this sync stream.
---@param syncTypeId string
---@param objectId integer
---@param paramId string
---@param syncData any
function sync.SyncStream:send(syncTypeId, objectId, paramId, syncData)
    if not self:getNewestSend() then
        sync.Send:new(self)
    end
    local syncType = sync:getSyncType(syncTypeId)
    if not syncType then return end
    local param = syncType:getParam(paramId)
    self:getNewestSend():add(syncType, objectId, param, syncData)
end

---Updates specified data locally using this sync stream.
---@param syncTypeId string
---@param objectId integer
---@param paramId string
---@param syncData any
function sync.SyncStream:localUpdate(syncTypeId, objectId, paramId, syncData)
    local syncType = sync:getSyncType(syncTypeId)
    if not syncType then return end
    local param = syncType:getParam(paramId)

    ---@type HookType
    local onReceiveHooks = sync.hookTypes.onReceive
    local onReceive = onReceiveHooks:getHook(param.onReceiveHook)
    if not onReceive then return end
    onReceive(syncData, paramId, objectId, syncTypeId, true)
end

---Receives specified data over this sync stream.
---@param syncData any
function sync.SyncStream:receive(syncData)
    if host:isHost() then return end

    if not self:getNewestReceive() then
        table.insert(self.toReceive, sync.Receive:new(self))
    end

    local receive = self:getNewestReceive()
    if receive.isReceived then
        table.insert(self.toReceive, sync.Receive:new(self))
        receive = self:getNewestReceive()
    end

    local buffer = data:createBuffer()
    buffer:writeByteArray(syncData)
    buffer:setPosition(0)
    local packetId = util.readVariableLengthIntZZ(buffer)

    local isFinalPacket = packetId < 0
    packetId = math.abs(packetId)

    local packetData = buffer:readByteArray(buffer:getLength())
    buffer:close()

    if packetId == 1 then
        table.insert(self.toReceive, sync.Receive:new(self))
        receive = self:getNewestReceive()
    end

    receive:add(packetId, packetData)
    if isFinalPacket then
        receive:finalise(packetId)
    end
end

--#ENDREGION
--#ENDREGION

--#REGION Events
--#REGION Tick

---@diagnostic disable-next-line: duplicate-set-field
function events.tick()
    sync.clock = sync.clock + 1
    for _, syncStream in pairs(sync.syncStreams) do
        syncStream:update()
    end
end

--#ENDREGION

--#REGION Play Sound

---@diagnostic disable-next-line: duplicate-set-field
function events.on_play_sound(sound)
    for _, syncStream in pairs(sync.syncStreams) do
        local queuedSend = syncStream:getQueuedSend()
        if not queuedSend then goto continue end
        queuedSend.currentPacket = math.max(0, queuedSend.currentPacket - syncStream.rateLimitRoleback)

        ::continue::
    end
end

return sync

--#ENDREGION
--#ENDREGION