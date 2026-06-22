local util = require("..util")
---@class TabletopCore
---@field currentGame Game? the currently active game
local core = {
    currentGame = nil
}





---@class ParamType<T>
---@field decode fun(encoded: Buffer): T decodes data after it has been pinged
---@field encode fun(rawData: T): string encodes data to be pinged
core.ParamType = {}
core.ParamType.__index = core.ParamType

---creates a new parameter type
---@generic T
---@param id string the ID of this parameter type
---@param decode fun(encoded: Buffer): T decodes data after it has been pinged
---@param encode fun(rawData: T): string encodes data to be pinged
---@return ParamType<T>
function core.ParamType:new(id, decode, encode)
    self = setmetatable({}, core.ParamType)
    self.decode = decode
    self.encode = encode
    return self
end

local defaultParamTypes = {}

---a string. Every character costs 1 byte to use spairingly
defaultParamTypes.string = core.ParamType:new("string",
    function(encoded)
        local stringLength = util.readVariableLengthInt(encoded)
        return encoded:readString(stringLength)
    end,

    function(rawData)
        local stringLength = string.len(rawData)
        return util.numToVarLengthInt(stringLength) .. rawData
    end
)

---a boolean (1 byte)
defaultParamTypes.boolean = core.ParamType:new("boolean",
    function(encoded)
        return encoded:read() == "T"
    end,

    function(rawData)
        if rawData then
            return "T"
        else
            return "F"
        end
    end
)


---a variable length integer. The number of bytes used will vary depending on the size. Useful for compact integer storage while still allowing high numbers
defaultParamTypes.variableLengthInteger = core.ParamType:new("variableLengthInteger",
    function(encoded)
        local integer = util.readVariableLengthInt(encoded)
        return integer
    end,

    function(rawData)
        return util.numToVarLengthInt(rawData)
    end
)

---a variable length decimal with 2 decimal places. Useful for compressed decimals with low precision
defaultParamTypes.variableLengthDecimal = core.ParamType:new("variableLengthDecimal",
    function(encoded)
        local integer = util.readVariableLengthInt(encoded) / 100
        return integer
    end,

    function(rawData)
        return util.numToVarLengthInt(math.floor(rawData * 100))
    end
)

---a vector 2 that uses variable length integers with 2 decimal places. Useful for compressed vec2 with low precision
defaultParamTypes.variableLengthVec3 = core.ParamType:new("variableLengthVec3",
    function(encoded)
        local x = util.readVariableLengthInt(encoded) / 100
        local y = util.readVariableLengthInt(encoded) / 100
        return vec(x, y)
    end,

    function(rawData)
        local x = util.numToVarLengthInt(math.floor(rawData.x * 100))
        local y = util.numToVarLengthInt(math.floor(rawData.y * 100))
        return x .. y
    end
)

---a vector 3 that uses variable length integers with 2 decimal places. Useful for compressed vec3 with low precision
defaultParamTypes.variableLengthVec3 = core.ParamType:new("variableLengthVec3",
    function(encoded)
        local x = util.readVariableLengthInt(encoded) / 100
        local y = util.readVariableLengthInt(encoded) / 100
        local z = util.readVariableLengthInt(encoded) / 100
        return vec(x, y, z)
    end,

    function(rawData)
        local x = util.numToVarLengthInt(math.floor(rawData.x * 100))
        local y = util.numToVarLengthInt(math.floor(rawData.y * 100))
        local z = util.numToVarLengthInt(math.floor(rawData.z * 100))
        return x .. y .. z
    end
)

---a decimal of range from 0 to 1, stored in a single byte. Multiply this value for different ranges
defaultParamTypes.unitInterval = core.ParamType:new("unitInterval",
    function(encoded)
        local byteString = encoded:read()
        local byte = string.byte(byteString, 1, -1)
        return byte / 255
    end,

    function(rawData)
        rawData = math.clamp(rawData, 0, 1)
        rawData = math.floor(rawData * 255)
        return string.char(rawData)
    end
)

---a 32 bit integer (4 bytes)
defaultParamTypes.integer = core.ParamType:new("integer",
    function(encoded)
        return encoded:readInt()
    end,

    function(rawData)
        local buffer = data:createBuffer()
        buffer:writeInt(rawData)
        buffer:setPosition(0)
        local encodedInt = buffer:readBase64()
        buffer:close()
        return encodedInt
    end
)

---a 64 bit double (8 bytes)
defaultParamTypes.double = core.ParamType:new("double",
    function(encoded)
        return encoded:readDouble()
    end,

    function(rawData)
        local buffer = data:createBuffer()
        buffer:writeDouble(rawData)
        buffer:setPosition(0)
        local encodedDouble = buffer:readBase64()
        buffer:close()
        return encodedDouble
    end
)

---a 32 bit float (4 bytes)
defaultParamTypes.float = core.ParamType:new("float",
    function(encoded)
        return encoded:readFloat()
    end,

    function(rawData)
        local buffer = data:createBuffer()
        buffer:writeFloat(rawData)
        buffer:setPosition(0)
        local encodedFloat = buffer:readBase64()
        buffer:close()
        return encodedFloat
    end
)

---a 16 bit short (2 bytes)
defaultParamTypes.short = core.ParamType:new("short",
    function(encoded)
        return encoded:readShort()
    end,

    function(rawData)
        local buffer = data:createBuffer()
        buffer:writeShort(rawData)
        buffer:setPosition(0)
        local encodedShort = buffer:readBase64()
        buffer:close()
        return encodedShort
    end
)

---a table of variable length integers
defaultParamTypes.variableLengthIntegerTable = core.ParamType:new("variableLengthIntegerTable",
    function(encoded)
        local dataLength = util.readVariableLengthInt(encoded)
        local endPos = encoded:getPosition() + dataLength
        local bufferLength = encoded:getLength()
        local pieces = {}

        repeat
            table.insert(pieces, util.readVariableLengthInt(encoded))
        until (endPos <= encoded:getPosition()) or (encoded:getPosition() == bufferLength)

        return pieces
    end,

    function(rawData)
        local pieces = ""

        for _, id in pairs(rawData.pieces) do
            pieces = pieces .. util.numToVarLengthInt(id)
        end

        local dataLength = util.numToVarLengthInt(string.len(pieces))
        return dataLength .. pieces
    end
)

---a dimenions object. For compression, decimals only have 2 decimal places (nothing under 0.01)
defaultParamTypes.dimenions = core.ParamType:new("dimenions",
    function(encoded)
        local minX = util.readVariableLengthInt(encoded) / 100
        local minY = util.readVariableLengthInt(encoded) / 100
        local maxX = util.readVariableLengthInt(encoded) / 100
        local maxY = util.readVariableLengthInt(encoded) / 100
        return core.Dimensions:new(vec(minX, minY), vec(maxX, maxY))
    end,

    function(rawData)
        local minX = util.numToVarLengthInt(math.floor(rawData.min.x * 100))
        local minY = util.numToVarLengthInt(math.floor(rawData.min.y * 100))
        local maxX = util.numToVarLengthInt(math.floor(rawData.max.x * 100))
        local maxY = util.numToVarLengthInt(math.floor(rawData.max.y * 100))
        return minX .. minY .. maxX .. maxY
    end
)

---@class Param
---@field id string the ID of this parameter
---@field paramType ParamType the type of this parameter. This determines how data will be compressed and pinged
---@field onReceiveHook string the ID of the hook function that will be run once this parameter has been decoded
core.Param = {}
core.Param.__index = core.Param

---creates a new parameter
---@param id string the ID of this parameter
---@param paramType ParamType the type of this parameter. This determines how data will be compressed and pinged
---@param onReceiveHook string? the ID of the hook function that will be run once this parameter has been decoded
---@return Param
function core.Param:new(id, paramType, onReceiveHook)
    self = setmetatable({}, core.Param)
    self.id = id
    self.paramType = paramType
    self.onReciveHook = onReceiveHook
    return self
end

local defaultSlotParams = {}
table.insert(defaultSlotParams, core.Param:new("id", defaultParamTypes.variableLengthInteger))
table.insert(defaultSlotParams, core.Param:new("parent", defaultParamTypes.variableLengthInteger))
table.insert(defaultSlotParams, core.Param:new("contents", defaultParamTypes.variableLengthIntegerTable))
table.insert(defaultSlotParams, core.Param:new("contentsLimit", defaultParamTypes.variableLengthInteger))
table.insert(defaultSlotParams, core.Param:new("dimensions", defaultParamTypes.dimenions))
table.insert(defaultSlotParams, core.Param:new("position", defaultParamTypes.variableLengthVec2))
table.insert(defaultSlotParams, core.Param:new("leniecne", defaultParamTypes.dimenions))
table.insert(defaultSlotParams, core.Param:new("isVisible", defaultParamTypes.boolean))
table.insert(defaultSlotParams, core.Param:new("canRemoveContents", defaultParamTypes.boolean))
table.insert(defaultSlotParams, core.Param:new("canMoveContents", defaultParamTypes.boolean))
table.insert(defaultSlotParams, core.Param:new("canInteractContents", defaultParamTypes.boolean))

local defaultPieceParams = {}
table.insert(defaultPieceParams, core.Param:new("id", defaultParamTypes.variableLengthInteger))
table.insert(defaultPieceParams, core.Param:new("parent", defaultParamTypes.variableLengthInteger))
table.insert(defaultPieceParams, core.Param:new("model", defaultParamTypes.variableLengthInteger))
table.insert(defaultPieceParams, core.Param:new("dimensions", defaultParamTypes.dimenions))
table.insert(defaultPieceParams, core.Param:new("height", defaultParamTypes.variableLengthDecimal))
table.insert(defaultPieceParams, core.Param:new("position", defaultParamTypes.variableLengthVec2))
table.insert(defaultPieceParams, core.Param:new("slots", defaultParamTypes.variableLengthIntegerTable))
table.insert(defaultPieceParams, core.Param:new("contents", defaultParamTypes.variableLengthIntegerTable))
table.insert(defaultPieceParams, core.Param:new("contentsLimit", defaultParamTypes.variableLengthInteger))
table.insert(defaultPieceParams, core.Param:new("isVisible", defaultParamTypes.boolean))
table.insert(defaultPieceParams, core.Param:new("isInteractable", defaultParamTypes.boolean))
table.insert(defaultPieceParams, core.Param:new("isMovable", defaultParamTypes.boolean))
table.insert(defaultPieceParams, core.Param:new("isRemovable", defaultParamTypes.boolean))

---@class ParamHandler
---@field params Param[]
---@field paramIndex {string : integer}
core.ParamHandler = {}
core.ParamHandler.__index = core.ParamHandler

---creates a new parameter handler
---@param ... Param parameters to add on creation
function core.ParamHandler:new(...)
    self = setmetatable({}, core.ParamHandler)
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
function core.ParamHandler:addParam(param)
    table.insert(self.params, param)
    self.paramIndex[param.id] = #self.params
end

---@class Dimensions
---@field min Vector2 minum corner
---@field max Vector2 maximum corner
core.Dimensions = {}
core.Dimensions.__index = core.Dimensions
---@param min Vector2 minum corner
---@param max Vector2 maximum corner
---@return Dimensions
function core.Dimensions:new(min, max)
    self = setmetatable({}, core.Dimensions)
    self.min = min
    self.max = max
    return self
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
core.Send = {}
core.Send.__index = core.Send
---@param syncStream SyncStream the sync stream this send object is in reference to
function core.Send:new(syncStream)
    self = setmetatable({}, core.Send)
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

function core.Send:add()

end

-- timing chunks -> toSendString -> receiving chunks -> timing chunks
-- allow 16 streams of async transfer, each with their own settings. Each stream can have a queue
-- function to add and remove new sends
-- remember you're dealing with both passive and active sync
-- fields can be used a system control messages, like clone field, which when an ID is added, piece is cloned to that slot

---@class Receive
---@field received string[]
core.Receive = {}
core.Receive.__index = core.Receive
function core.Receive:new()
    self = setmetatable({}, core.Receive)
    self.syncTime = 0
    self.received = {}
    self.timeline = {}
    self.timelineIndex = {}
    return self
end

---@class SyncStream
---@field game Game the game this sync stream will be in reference to
---@field id integer a numeric ID between 0 and 15
---@field ping function the ping function send objects will hook into
---@field packetInterval integer how many ticks between each sync ping (sync packet)
---@field syncSpeed integer how many bytes will be sent per second when syncing
---@field toSend Send[]
---@field toReceive Receive[]
core.SyncStream = {}
core.SyncStream.__index = core.SyncStream

---comment
---@param game Game
---@param id integer a numeric ID between 0 and 15
---@param ping function the ping function send objects will hook into
---@return SyncStream
function core.SyncStream:new(game, id, ping)
    self = setmetatable({}, core.SyncStream)
    self.game = game
    self.id = id
    self.ping = ping
    self.toSend = {}
    self.toReceive = {}
    self.packetInterval = 5
    self.syncSpeed = 200
    return self
end

---creates a new send object within the sync stream
---@return Send
function core.SyncStream:newToSend()
    return core.Send:new(self)
end

---@class Game
---@field gameTime integer this game's internal timer
---@field nextSyncId integer the next available sync ID
---@field worldPos Vector3 the root position where this game will exist in the world
---@field worldRot Vector3 the root rotation of the game relative to the world
---@field slots Slot[] table that contains all slots
---@field pieces Piece[] table that contains all pieces
---@field root Piece the root piece of this game
---@field paramTypes ParamType[] table that contains all parameter types relevant to this game
---@field paramHandlers ParamHandler[] table that contains all parameter handlers relevant to this game
core.Game = {}
core.Game.__index = core.Game

---creates a new game
---@param worldPos Vector3 the root position where this game will exist in the world
---@param worldRot Vector3 the root rotation of the game relative to the world
---@return Game
function core.Game:new(worldPos, worldRot)
    self = setmetatable({}, core.Game)
    self.gameTime = 0
    self.nextSyncId = 0



    self.slots = {}
    self.pieces = {}
    self.worldPos = worldPos
    self.worldRot = worldRot
    self.paramTypes = defaultParamTypes
    self.paramHandlers = {
        slot = core.ParamHandler:new(table.unpack(defaultSlotParams)),
        piece = core.ParamHandler:new(table.unpack(defaultPieceParams))
    }
    self.syncStreams = {
        passive = core.SyncStream:new(self, 0),
        direct = core.SyncStream:new(self, 1)
    }

    self.syncStreamsIndex = {
        [0] = "passive",
        [1] = "direct"
    }


    --self.root = core.Piece:new()

    core.currentGame = self
    return self
end

---creates a new syncStream
---@param id any
function core.Game:newSyncStream(id)
    local syncStreamCount = #self.syncStreams
    self.syncStreams[syncStreamCount] = core.SyncStream:new(self, syncStreamCount)
end

---returns a sync stream from a numeric ID
---@param numericId integer a numeric ID between 0 and 15
---@return SyncStream
function core.Game:getSyncSteam(numericId)
    return self.syncStreams[self.syncStreamsIndex[numericId]]
end

---get all of this game's parameter types
---@return ParamType[]
function core.Game:getParamTypes()
    return self.paramTypes
end

---adds a new parameter handler to this game
---@param id string
---@param paramHandler ParamHandler
function core.Game:addParamHandler(id, paramHandler)
    self.paramHandlers[id] = paramHandler
end

---get all of this game's parameter handlers
---@return ParamHandler[]
function core.Game:getParamHandlers()
    return self.paramHandlers
end

---updates and instantly syncs a parameter
---@param handlerId string
---@param paramId string
---@param value any
function core.Game:updateParam(handlerId, syncId, paramId, value)
    local paramHandler = self:getParamHandlers()[handlerId]
    local paramIndex = paramHandler.paramIndex[paramId]
    local param = paramHandler.params[paramIndex]
    local paramType = param.paramType

    local syncIdEncoded = util.numToVarLengthInt(syncId)
    local paramIndexEncoded = util.numToVarLengthInt(paramIndex)
    local encoded = paramType.encode(value)
    local toSend = syncIdEncoded .. paramIndexEncoded .. encoded
    --- add data to table
end

---Creates a new game slot
function core.Game:newSlot()
    table.insert(self.slots, core.Slot:new(self))
end

function core.Game:newPiece()
    table.insert(self.pieces, core.Piece:new(self))
end

function core.Game:intialiseSync()
    util.numToVarLengthInt(self.nextSyncId)
end

local clock = 0
function events.tick()
    clock = clock + 1
    local game = core.currentGame
    if not game then return end
    game.gameTime = game.gameTime + 1
    -- for each active syncstream (add an is active field) send chunks. Revert if rate limited
    for id, syncStream in pairs(game.syncStreams) do
        if syncStream.toSend[1] and syncStream.toSend[1].isSending and syncStream.toSend[1].toSend and clock % syncStream.packetInterval == 0 then
            local packetInterval = syncStream.packetInterval
            local syncSpeed = syncStream.syncSpeed
            local bytesPerPacket = math.floor(syncSpeed * (packetInterval / 20))
            local toSend = syncStream.toSend[1].toSend
            local currentPacket = syncStream.toSend[1].currentPacket
            local packet = string.sub(toSend,currentPacket * bytesPerPacket, (currentPacket + 1) * bytesPerPacket)
            syncStream.toSend[1].currentPacket = currentPacket + 1

            --- need status byte too (4 bits for syncstream, 2 for isStart and isEnd, 2 free)
            syncStream.ping()
        end
    end
    
end

-- sound event to revert when rate limited


---@class Slot
---@field syncId integer unique syncID of this slot
---@field lastSynced integer how long it has been since this slot was last synced
---@field parent integer the syncID of this slot's parent piece
---@field contents integer[] table of all pieces contained within this slot, stored by syncID
---@field dimensions Dimensions dimensions of this slot. Rounded down to 2 decimal places
---@field position Vector2 position of this slot relative to its parent piece. Rounded down to 2 decimal places
---@field lenience Dimensions how much objects can be moved within this slot. Rounded down to 2 decimal places
core.Slot = {}
core.Slot.__index = core.Slot
---@param game Game the game that uses this slot
---@return Slot
function core.Slot:new(game)
    self = setmetatable({}, core.Slot)
    self.syncId = game.nextSyncId
    game.nextSyncId = game.nextSyncId + 1

    self.lastSynced = 0
    self.game = game
    self.parent = nil
    self.contents = {}
    self.dimensions = core.Dimensions:new(vec(-1, -1), vec(1, 1))
    self.position = vec(0, 0)
    self.rotation = vec(0, 0, 0)
    self.lenience = core.Dimensions:new(vec(0, 0), vec(0, 0))
    self.isVisiable = true
    self.canRemoveContents = true
    self.canMoveContents = true
    self.canInteractContents = true
    return self
end

---Syncs and updates a parameter with the specified value. Use this instead of setting your parameters directly
---@param paramId string
---@param value any
function core.Slot:update(paramId, value)
    self.game:updateParam("slot", self.syncId, paramId, value)
end

---@class Piece
---@field syncId integer unique syncID of the piece
---@field parent Slot parent slot of this piece
---@field model ModelPart model the piece will copy and use
---@field dimensions Dimensions dimensions of this piece
---@field height number height of this piece
---@field position Vector2 position within this piece's parent slot. Clamped by the parent slot's lenience
---@field slots Slot[] table that contains all of this piece's slots
---@field contents integer[] table of all pieces contained within this piece, stored by syncID
core.Piece = {}
core.Piece.__index = core.Piece
---@param game Game the game that uses this slot
---@return Piece
function core.Piece:new(game)
    self = setmetatable({}, core.Piece)
    self.syncId = game.nextSyncId
    game.nextSyncId = game.nextSyncId + 1

    self.game = game
    self.parent = nil
    self.model = nil
    self.dimensions = core.Dimensions:new(vec(-1, -1), vec(1, 1))
    self.height = 2
    self.position = vec(0, 0)
    self.slots = {}
    self.contents = {}
    self.isVisible = true
    self.isInteractable = true
    self.isMovable = true
    self.isRemovable = true
    return self
end

---Syncs and updates a parameter with the specified value. Use this instead of setting your parameters directly
---@param paramId string
---@param value any
function core.Piece:update(paramId, value)
    self.game:updateParam("piece", paramId, value)
end

return core
