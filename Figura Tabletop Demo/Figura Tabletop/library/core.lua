local util = require("..util")
---@class TabletopCore
local core = {}





---@class ParamType<T>
---@field decode fun(encoded: string): T decodes data after it has been pinged
---@field encode fun(data: T): string encodes data to be pinged
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

---a vector 3 that uses variable length integers with 2 decimal places. Useful for compressed vec3 with low precision
defaultParamTypes.variableLengthVec3 = core.ParamType:new("variableLengthVec3",
    function(encoded)
        local x = util.readVariableLengthInt(encoded) / 100
        local y = util.readVariableLengthInt(encoded) / 100
        local z = util.readVariableLengthInt(encoded) / 100
        return vec(x,y,z)
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
table.insert(defaultSlotParams, core.Param:new("position", defaultParamTypes.variableLengthVec3))
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
table.insert(defaultPieceParams, core.Param:new("position", defaultParamTypes.variableLengthVec3))
table.insert(defaultPieceParams, core.Param:new("slots", defaultParamTypes.variableLengthIntegerTable))
table.insert(defaultPieceParams, core.Param:new("contents", defaultParamTypes.variableLengthIntegerTable))
table.insert(defaultPieceParams, core.Param:new("contentsLimit", defaultParamTypes.variableLengthInteger))
table.insert(defaultPieceParams, core.Param:new("isVisible", defaultParamTypes.boolean))
table.insert(defaultPieceParams, core.Param:new("isInteractable", defaultParamTypes.boolean))
table.insert(defaultPieceParams, core.Param:new("isMovable", defaultParamTypes.boolean))
table.insert(defaultPieceParams, core.Param:new("isRemovable", defaultParamTypes.boolean))

---@class ParamHandler
---@field parameters table<Param>
core.ParamHandler = {}
core.ParamHandler.__index = core.ParamHandler

---creates a new parameter handler
---@param ... Param optional table of parameters to add on creation. Table keys should
function core.ParamHandler:new(...)
    self = setmetatable({}, core.ParamHandler)
    self.parameters {}

    local parameters = {...}
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
    table.insert(self.parameters, param)
end

---@class Game
---@field worldPos Vector3 the root position where this game will exist in the world
---@field playSpaces table<Slot> table that contains all playspace slots
---@field root Piece the root piece of this game
---@field paramTypes table<ParamType>
core.Game = {}
core.Game.__index = core.Game

---creates a new game
---@param worldPos Vector3 the root position where this game will exist in the world
---@return Game
function core.Game:new(worldPos)
    self = setmetatable({}, core.Game)
    self.playSpaces = {}
    self.paramTypes = defaultParamTypes
    self.slotParamHandler = core.ParamHandler:new(table.unpack(defaultSlotParams))
    self.pieceParamHandler = core.ParamHandler:new(table.unpack(defaultPieceParams))
    --self.root = core.Piece:new()

    return self
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

---@class Slot
---@field id string unique ID of this slot
---@field parent Piece parent piece of this slot
---@field contents Contents contents of this slot
---@field dimensions Dimensions dimensions of this slot
---@field position Vector3 position of this slot relative to its parent piece
---@field lenience Dimensions how much objects can be moved within this slot
core.Slot = {}
core.Slot.__index = core.Slot
---@param id string unique ID of this slot
---@param parent Piece parent piece of this slot
---@param contents Contents contents of this slot
---@param dimensions Dimensions dimensions of this slot
---@param position Vector3 position of this slot relative to its parent piece
---@param lenience Dimensions how much objects can be moved within this slot
---@return Slot
function core.Slot:new(id, parent, contents, dimensions, position, lenience)
    self = setmetatable({}, core.Slot)
    self.id = id
    self.parent = parent
    self.contents = contents
    self.dimensions = dimensions
    self.position = position
    self.rotation = vec(0, 0, 0)
    self.lenience = lenience
    self.isVisiable = true
    self.canRemoveContents = true
    self.canMoveContents = true
    self.canInteractContents = true
    return self
end

---@class Piece
---@field id string unique ID of the piece
---@field parent Slot parent slot of this piece
---@field model ModelPart model the piece will copy and use
---@field dimensions Dimensions dimensions of this piece
---@field height number height of this piece
---@field position Vector2 position within this piece's parent slot. Clamped by the parent slot's lenience
---@field slots table<Slot> table that contains all of this piece's slots
---@field contents Contents contents of this piece
core.Piece = {}
core.Piece.__index = core.Piece
---@param id string unique ID of the piece
---@param parent Slot parent slot of this piece
---@param model ModelPart model the piece will copy and use
---@param dimensions Dimensions dimensions of this piece
---@param height number height of this piece
---@param position Vector2 position within this piece's parent slot. Clamped by the parent slot's lenience
---@param slots table<Slot> table that contains all of this piece's slots
---@param contents Contents contents of this piece
---@return Piece
function core.Piece:new(id, parent, model, dimensions, height, position, slots, contents)
    self = setmetatable({}, core.Piece)
    self.id = id
    self.parent = parent
    self.model = model
    self.dimensions = dimensions
    self.height = height
    self.position = position
    self.slots = slots
    self.contents = contents
    self.isVisible = true
    self.isInteractable = true
    self.isMovable = true
    self.isRemovable = true
    return self
end

return core
