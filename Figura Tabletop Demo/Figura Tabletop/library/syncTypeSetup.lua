local util = require("..util")
local sync = require("..sync")

---@class SyncTypeSetup
local SyncTypeSetup = {}

---comment
---@param core TabletopCore
function SyncTypeSetup:create(core)
    ---a string. Every character costs 1 byte to use spairingly
    sync.ParamType:new("string",
        function(encoded, paramTypes)
            local stringLength = util.readVariableLengthInt(encoded)
            return encoded:readString(stringLength)
        end,
        function(rawData, paramTypes)
            local stringLength = string.len(rawData)
            return util.numToVarLengthInt(stringLength) .. rawData
        end
    )

    ---a boolean (1 byte)
    sync.ParamType:new("boolean",
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
    )

    ---a bundle of 8 boolean flags (1 byte)
    sync.ParamType:new("flags",
        ----- THIS NEEDS TO BE CREATED
        function(encoded, paramTypes)
            local flagByte = encoded:readBase64(1)
            ---@type boolean[]
            local flags = {}
            for i = 0, 7 do
                table.insert(flags, bit32.extract(flagByte,i) == 1)
            end
            return flags
        end,
        function(rawData, paramTypes)
            table.sort(rawData)
            local bitVal = 0
            for i = 0, 7 do
                bitVal = bitVal + rawData[i] * 2 ^ i
            end
            return string.char(bitVal)
        end
    )

    ---a variable length integer. The number of bytes used will vary depending on the size. Useful for compact integer storage while still allowing high numbers
    sync.ParamType:new("variableLengthInteger",
        function(encoded, paramTypes)
            local integer = util.readVariableLengthInt(encoded)
            return integer
        end,
        function(rawData, paramTypes)
            return util.numToVarLengthInt(rawData)
        end
    )

    ---a variable length integer that supports negative values though zig-zag encoding. This takes more space
    sync.ParamType:new("variableLengthIntegerZZ",
        function(encoded, paramTypes)
            local integer = util.readVariableLengthIntZZ(encoded)
            return integer
        end,
        function(rawData, paramTypes)
            return util.numToVarLengthIntZZ(rawData)
        end
    )

    ---a variable length decimal with 2 decimal places. Useful for compressed decimals with low precision. Supports negative values
    sync.ParamType:new("variableLengthDecimal",
        function(encoded, paramTypes)
            ---@type number
            return paramTypes["variableLengthIntegerZZ"].decode(encoded, paramTypes) / 100
        end,
        function(rawData, paramTypes)
            return paramTypes["variableLengthIntegerZZ"].encode(math.floor(rawData * 100), paramTypes)
        end
    )

    ---a vector 2 that uses variable length integers with 2 decimal places. Useful for compressed vec2 with low precision. Supports negative values
    sync.ParamType:new("variableLengthVec2",
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
    )

    ---a vector 3 that uses variable length integers with 2 decimal places. Useful for compressed vec3 with low precision
    sync.ParamType:new("variableLengthVec3",
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
    )

    ---a decimal of range from 0 to 1, stored in a single byte. Multiply this value for different ranges
    sync.ParamType:new("unitInterval",
        function(encoded, paramTypes)
            local byte = encoded:read()
            return byte / 255
        end,
        function(rawData, paramTypes)
            rawData = math.clamp(rawData, 0, 1)
            rawData = math.floor(rawData * 255)
            return string.char(rawData)
        end
    )

    ---a 32 bit integer (4 bytes)
    sync.ParamType:new("integer",
        function(encoded, paramTypes)
            return encoded:readInt()
        end,
        function(rawData, paramTypes)
            local buffer = data:createBuffer()
            buffer:writeInt(rawData)
            buffer:setPosition(0)
            local encodedInt = buffer:readByteArray(4)
            buffer:close()
            --log(encodedInt)
            return encodedInt
        end
    )

    ---a 64 bit double (8 bytes)
    sync.ParamType:new("double",
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
    )

    ---a 32 bit float (4 bytes)
    sync.ParamType:new("float",
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
    )

    ---a 16 bit short (2 bytes)
    sync.ParamType:new("short",
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
    )

    ---a table of variable length integers 
    sync.ParamType:new("variableLengthTable",
        function(encoded, paramTypes)
            local dataLength = util.readVariableLengthInt(encoded)
            local endPos = encoded:getPosition() + dataLength
            local bufferLength = encoded:getLength()
            local values = {}
            while (endPos > encoded:getPosition()) and (encoded:getPosition() ~= bufferLength) do
                table.insert(values, util.readVariableLengthInt(encoded))
            end 
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
    )

    ---a dimenions object. For compression, decimals only have 2 decimal places (nothing under 0.01)
    sync.ParamType:new("dimenions",
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

    -- improve annotations later so this declaration isn't needed

    ---@type HookType
    local onReceive = sync.hookTypes.onReceive

    onReceive:add("doNothing", function(a, b, c, d)
        log(a, b, c, d)
    end)

    
    local slot = sync.SyncType:new("slot")
    
    slot:addParam(sync.Param:new("id", sync.paramTypes.variableLengthInteger, "doNothing"))
    slot:addParam(sync.Param:new("parent", sync.paramTypes.variableLengthInteger, "doNothing"))
    slot:addParam(sync.Param:new("contents", sync.paramTypes.variableLengthTable, "doNothing"))
    slot:addParam(sync.Param:new("contentsLimit", sync.paramTypes.variableLengthInteger, "doNothing"))
    slot:addParam(sync.Param:new("dimensions", sync.paramTypes.dimenions, "doNothing"))
    slot:addParam(sync.Param:new("position", sync.paramTypes.variableLengthVec2, "doNothing"))
    slot:addParam(sync.Param:new("lenience", sync.paramTypes.dimenions, "doNothing"))
    slot:addParam(sync.Param:new("flags", sync.paramTypes.flags, "doNothing"))

    local piece = sync.SyncType:new("piece")

    piece:addParam(sync.Param:new("id", sync.paramTypes.variableLengthInteger, "doNothing"))
    piece:addParam(sync.Param:new("parent", sync.paramTypes.variableLengthInteger, "doNothing"))
    piece:addParam(sync.Param:new("model", sync.paramTypes.variableLengthInteger, "doNothing"))
    piece:addParam(sync.Param:new("dimensions", sync.paramTypes.dimenions, "doNothing"))
    piece:addParam(sync.Param:new("height", sync.paramTypes.variableLengthDecimal, "doNothing"))
    piece:addParam(sync.Param:new("position", sync.paramTypes.variableLengthVec2, "doNothing"))
    piece:addParam(sync.Param:new("slots", sync.paramTypes.variableLengthTable, "doNothing"))
    piece:addParam(sync.Param:new("contents", sync.paramTypes.variableLengthTable, "doNothing"))
    piece:addParam(sync.Param:new("contentsLimit", sync.paramTypes.variableLengthInteger, "doNothing"))
    piece:addParam(sync.Param:new("flags", sync.paramTypes.flags, "doNothing"))
end

return SyncTypeSetup
