local util = require("..util")
local sync = require("..sync")

---@class ParamSetup
local paramSetup = {}
paramSetup.__index = paramSetup
function paramSetup:new(core)
    self = setmetatable({}, paramSetup)
    self.defaultParamTypes = {
        ---a string. Every character costs 1 byte to use spairingly
        string = sync.ParamType:new("string",
            function(encoded, paramTypes)
                local stringLength = util.readVariableLengthInt(encoded)
                return encoded:readString(stringLength)
            end,

            function(rawData, paramTypes)
                local stringLength = string.len(rawData)
                return util.numToVarLengthInt(stringLength) .. rawData
            end
        ),
        ---a boolean (1 byte)
        boolean = sync.ParamType:new("boolean",
            function(encoded, paramTypes)
                return encoded:read() == "T"
            end,

            function(rawData, paramTypes)
                if rawData then
                    return "T"
                else
                    return "F"
                end
            end
        ),
        ---a boolean (1 byte)
        flags = sync.ParamType:new("flags",
            ----- THIS NEEDS TO BE CREATED
            function(encoded, paramTypes)
                return encoded:read() == "T"
            end,

            function(rawData, paramTypes)
                if rawData then
                    return "T"
                else
                    return "F"
                end
            end
        ),
        ---a variable length integer. The number of bytes used will vary depending on the size. Useful for compact integer storage while still allowing high numbers
        variableLengthInteger = sync.ParamType:new("variableLengthInteger",
            function(encoded, paramTypes)
                local integer = util.readVariableLengthInt(encoded)
                return integer
            end,

            function(rawData, paramTypes)
                return util.numToVarLengthInt(rawData)
            end
        ),
        ---a variable length integer that supports negative values though zig-zag encoding. This takes more space
        variableLengthIntegerZZ = sync.ParamType:new("variableLengthIntegerZZ",
            function(encoded, paramTypes)
                local decoded = paramTypes["variableLengthInteger"].decode(encoded, paramTypes)
                local isPositive = decoded % 2 == 1
                if isPositive then
                    decoded = (decoded + 1) / 2
                else
                    decoded = -decoded / 2
                end
                ---@type integer
                return decoded
            end,

            function(rawData, paramTypes)
                rawData = math.floor(rawData)
                if rawData >= 0 then
                    rawData = (rawData * 2) - 1
                else
                    rawData = math.abs(rawData) * 2
                end
                return paramTypes["variableLengthInteger"].encode(rawData, paramTypes)
            end
        ),
        ---a variable length decimal with 2 decimal places. Useful for compressed decimals with low precision. Supports negative values
        variableLengthDecimal = sync.ParamType:new("variableLengthDecimal",
            function(encoded, paramTypes)
                ---@type number
                return paramTypes["variableLengthIntegerZZ"].decode(encoded, paramTypes) / 100
            end,

            function(rawData, paramTypes)
                return paramTypes["variableLengthIntegerZZ"].encode(math.floor(rawData * 100), paramTypes)
            end
        ),
        ---a vector 2 that uses variable length integers with 2 decimal places. Useful for compressed vec2 with low precision. Supports negative values
        variableLengthVec2 = sync.ParamType:new("variableLengthVec2",
            function(encoded, paramTypes)
                local x = paramTypes["variableLengthDecimal"].decode(encoded, paramTypes)
                local y = paramTypes["variableLengthDecimal"].decode(encoded, paramTypes)
                return vec(x, y)
            end,

            function(rawData, paramTypes)
                local x = paramTypes["variableLengthDecimal"].encode(rawData.x, paramTypes)
                local y = paramTypes["variableLengthDecimal"].encode(rawData.y, paramTypes)
                return x .. y
            end
        ),
        ---a vector 3 that uses variable length integers with 2 decimal places. Useful for compressed vec3 with low precision
        variableLengthVec3 = sync.ParamType:new("variableLengthVec3",
            function(encoded, paramTypes)
                local x = paramTypes["variableLengthDecimal"].decode(encoded, paramTypes)
                local y = paramTypes["variableLengthDecimal"].decode(encoded, paramTypes)
                local z = paramTypes["variableLengthDecimal"].decode(encoded, paramTypes)
                return vec(x, y, z)
            end,

            function(rawData, paramTypes)
                local x = paramTypes["variableLengthDecimal"].encode(rawData.x, paramTypes)
                local y = paramTypes["variableLengthDecimal"].encode(rawData.y, paramTypes)
                local z = paramTypes["variableLengthDecimal"].encode(rawData.z, paramTypes)
                return x .. y .. z
            end
        ),
        ---a decimal of range from 0 to 1, stored in a single byte. Multiply this value for different ranges
        unitInterval = sync.ParamType:new("unitInterval",
            function(encoded, paramTypes)
                local byte = encoded:read()
                return byte / 255
            end,

            function(rawData, paramTypes)
                rawData = math.clamp(rawData, 0, 1)
                rawData = math.floor(rawData * 255)
                return string.char(rawData)
            end
        ),
        ---a 32 bit integer (4 bytes)
        integer = sync.ParamType:new("integer",
            function(encoded, paramTypes)
                return encoded:readInt()
            end,

            function(rawData, paramTypes)
                local buffer = data:createBuffer()
                buffer:writeInt(rawData)
                buffer:setPosition(0)
                local encodedInt = buffer:readByteArray(4)
                buffer:close()
                log(encodedInt)
                return encodedInt
            end
        ),
        ---a 64 bit double (8 bytes)
        double = sync.ParamType:new("double",
            function(encoded, paramTypes)
                return encoded:readDouble()
            end,

            function(rawData, paramTypes)
                local buffer = data:createBuffer()
                buffer:writeDouble(rawData)
                buffer:setPosition(0)
                local encodedDouble = buffer:readByteArray(8)
                buffer:close()
                return encodedDouble
            end
        ),
        ---a 32 bit float (4 bytes)
        float = sync.ParamType:new("float",
            function(encoded, paramTypes)
                return encoded:readFloat()
            end,

            function(rawData, paramTypes)
                local buffer = data:createBuffer()
                buffer:writeFloat(rawData)
                buffer:setPosition(0)
                local encodedFloat = buffer:readByteArray(4)
                buffer:close()
                return encodedFloat
            end
        ),
        ---a 16 bit short (2 bytes)
        short = sync.ParamType:new("short",
            function(encoded, paramTypes)
                return encoded:readShort()
            end,

            function(rawData, paramTypes)
                rawData = math.clamp(rawData, -32768, 32767)
                local buffer = data:createBuffer()
                buffer:writeShort(rawData)
                buffer:setPosition(0)
                local encodedShort = buffer:readByteArray(2)
                buffer:close()
                return encodedShort
            end
        ),
        ---a table of variable length integers 
        variableLengthTable = sync.ParamType:new("variableLengthTable",
            function(encoded, paramTypes)
                local dataLength = util.readVariableLengthInt(encoded)
                local endPos = encoded:getPosition() + dataLength
                local bufferLength = encoded:getLength()
                local values = {}

                repeat
                    table.insert(values, util.readVariableLengthInt(encoded))
                until (endPos <= encoded:getPosition()) or (encoded:getPosition() == bufferLength)

                return values
            end,

            function(rawData, paramTypes)
                local values = ""

                for _, id in pairs(rawData) do
                    values = values .. util.numToVarLengthInt(id)
                end

                local dataLength = util.numToVarLengthInt(string.len(values))
                return dataLength .. values
            end
        ),
        ---a dimenions object. For compression, decimals only have 2 decimal places (nothing under 0.01)
        dimenions = sync.ParamType:new("dimenions",
            function(encoded, paramTypes)
                local minX = paramTypes["variableLengthDecimal"].decode(encoded, paramTypes)
                local minY = paramTypes["variableLengthDecimal"].decode(encoded, paramTypes)
                local maxX = paramTypes["variableLengthDecimal"].decode(encoded, paramTypes)
                local maxY = paramTypes["variableLengthDecimal"].decode(encoded, paramTypes)
                return core.Dimensions:new(vec(minX, minY), vec(maxX, maxY))
            end,

            function(rawData, paramTypes)
                local minX = paramTypes["variableLengthDecimal"].encode(rawData.min.x, paramTypes)
                local minY = paramTypes["variableLengthDecimal"].encode(rawData.min.y, paramTypes)
                local maxX = paramTypes["variableLengthDecimal"].encode(rawData.max.x, paramTypes)
                local maxY = paramTypes["variableLengthDecimal"].encode(rawData.max.y, paramTypes)
                return minX .. minY .. maxX .. maxY
            end
        )
    }

    self.defaultSlotParams = {}
    table.insert(self.defaultSlotParams, sync.Param:new("id", self.defaultParamTypes.variableLengthInteger))
    table.insert(self.defaultSlotParams, sync.Param:new("parent", self.defaultParamTypes.variableLengthInteger))
    table.insert(self.defaultSlotParams, sync.Param:new("contents", self.defaultParamTypes.variableLengthIntegerTable))
    table.insert(self.defaultSlotParams, sync.Param:new("contentsLimit", self.defaultParamTypes.variableLengthInteger))
    table.insert(self.defaultSlotParams, sync.Param:new("dimensions", self.defaultParamTypes.dimenions))
    table.insert(self.defaultSlotParams, sync.Param:new("position", self.defaultParamTypes.variableLengthVec2))
    table.insert(self.defaultSlotParams, sync.Param:new("leniecne", self.defaultParamTypes.dimenions))
    table.insert(self.defaultSlotParams, sync.Param:new("isVisible", self.defaultParamTypes.boolean))
    table.insert(self.defaultSlotParams, sync.Param:new("canRemoveContents", self.defaultParamTypes.boolean))
    table.insert(self.defaultSlotParams, sync.Param:new("canMoveContents", self.defaultParamTypes.boolean))
    table.insert(self.defaultSlotParams, sync.Param:new("canInteractContents", self.defaultParamTypes.boolean))

    self.defaultPieceParams = {}
    table.insert(self.defaultPieceParams, sync.Param:new("id", self.defaultParamTypes.variableLengthInteger))
    table.insert(self.defaultPieceParams, sync.Param:new("parent", self.defaultParamTypes.variableLengthInteger))
    table.insert(self.defaultPieceParams, sync.Param:new("model", self.defaultParamTypes.variableLengthInteger))
    table.insert(self.defaultPieceParams, sync.Param:new("dimensions", self.defaultParamTypes.dimenions))
    table.insert(self.defaultPieceParams, sync.Param:new("height", self.defaultParamTypes.variableLengthDecimal))
    table.insert(self.defaultPieceParams, sync.Param:new("position", self.defaultParamTypes.variableLengthVec2))
    table.insert(self.defaultPieceParams, sync.Param:new("slots", self.defaultParamTypes.variableLengthIntegerTable))
    table.insert(self.defaultPieceParams, sync.Param:new("contents", self.defaultParamTypes.variableLengthIntegerTable))
    table.insert(self.defaultPieceParams, sync.Param:new("contentsLimit", self.defaultParamTypes.variableLengthInteger))
    table.insert(self.defaultPieceParams, sync.Param:new("isVisible", self.defaultParamTypes.boolean))
    table.insert(self.defaultPieceParams, sync.Param:new("isInteractable", self.defaultParamTypes.boolean))
    table.insert(self.defaultPieceParams, sync.Param:new("isMovable", self.defaultParamTypes.boolean))
    table.insert(self.defaultPieceParams, sync.Param:new("isRemovable", self.defaultParamTypes.boolean))

    return self
end

return paramSetup
