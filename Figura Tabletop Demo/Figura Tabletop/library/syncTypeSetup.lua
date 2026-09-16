local util = require("..util")

---@class SyncTypeSetup
local SyncTypeSetup = {}

---comment
---@param core TabletopCore
function SyncTypeSetup:create(core)
    local game = core.currentGame
    assert(game, "This should never happen?")
    local sync = game.sync

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
            local flagByte = string.byte(encoded:readByteArray(1))
            ---@type boolean[]
            local flags = {}
            for i = 0, 7 do
                table.insert(flags, bit32.extract(flagByte,i) == 1)
            end
            return flags
        end,
        function(rawData, paramTypes)
            local keySort = {}
            for k, _ in pairs(rawData) do
                table.insert(keySort, k)
            end
            table.sort(keySort)
            local bitVal = 0
            for i = 0, 7 do
                local bool = rawData[keySort[i + 1]] and 1 or 0
                bitVal = bitVal + bool * 2 ^ i
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
            return {min = vec(minX, minY), max = vec(maxX, maxY)}
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

    onReceive:add("doNothing", function(data, paramId, objectId, syncTypeId, isLocalUpdate)
        --log(data, paramId, objectId, syncTypeId, isLocalUpdate)

    end)

    onReceive:add("playSpaces", function(data, paramId, objectId, syncTypeId, isLocalUpdate)
        if table.concat(game.playSpaces, ",") ~= table.concat(data, ",") then
            for _, playSpaceSlotId in pairs(data) do
                if not game[playSpaceSlotId] then
                    game.slots[objectId].part = game.model:newPart(playSpaceSlotId)
                end
            end

            game.playSpaces = data
        end
    end)

    onReceive:add("pieceFlags", function(data, paramId, objectId, syncTypeId, isLocalUpdate)
        local flagOutput = {}
        flagOutput.canInteract = data[1]
        flagOutput.canMove = data[2]
        flagOutput.canSelect = data[3]
        flagOutput.isDeleted = data[4]
        flagOutput.isSelected = data[5]
        flagOutput.unused1 = data[6]
        flagOutput.unused2 = data[7]
        flagOutput.visible = data[8]
        --log(flagOutput)

        -- TO DO: add flags
        -- make sync an object

    end)

    onReceive:add("slotId", function(data, paramId, objectId, syncTypeId, isLocalUpdate)
        game.slots[objectId] = core.Slot:new(game, objectId)
    end)

    onReceive:add("pieceId", function(data, paramId, objectId, syncTypeId, isLocalUpdate)
        game.pieces[objectId] = core.Piece:new(game, objectId)
    end)

    onReceive:add("generic", function(data, paramId, objectId, syncTypeId, isLocalUpdate)
        game[syncTypeId .. "s"][objectId][paramId] = data
    end)

    onReceive:add("model", function(data, paramId, objectId, syncTypeId, isLocalUpdate)
        if data ~= game.pieces[objectId] then
            ---@type HookType
            local modelHook = sync.hookTypes.model
            ---@type ModelPart
            local model = modelHook.hooks[data]
            local parent = game.pieces[objectId].parent
            if parent and game.slots[parent].part then
                game.slots[parent].part:addChild(model:copy(objectId)) -- CHANGE TO A DEEPCOPY
            end

            -- deepcopy the model part. Save to parent.
        end

    end)


    local gameMeta = sync.SyncType:new("gameMeta")
    local slot = sync.SyncType:new("slot")
    local piece = sync.SyncType:new("piece")

    slot:addParam(sync:newParam("id", sync.paramTypes.variableLengthInteger, "slotId"))
    piece:addParam(sync:newParam("id", sync.paramTypes.variableLengthInteger, "pieceId"))

    gameMeta:addParam(sync:newParam("playSpaces", sync.paramTypes.variableLengthTable, "playSpaces"))

    slot:addParam(sync:newParam("parent", sync.paramTypes.variableLengthInteger, "generic"))
    slot:addParam(sync:newParam("contents", sync.paramTypes.variableLengthTable, "doNothing"))
    slot:addParam(sync:newParam("contentsLimit", sync.paramTypes.variableLengthInteger, "generic"))
    slot:addParam(sync:newParam("dimensions", sync.paramTypes.dimenions, "generic"))
    slot:addParam(sync:newParam("position", sync.paramTypes.variableLengthVec2, "doNothing"))
    slot:addParam(sync:newParam("lenience", sync.paramTypes.dimenions, "generic"))
    slot:addParam(sync:newParam("flags", sync.paramTypes.flags, "doNothing"))

    piece:addParam(sync:newParam("parent", sync.paramTypes.variableLengthInteger, "generic"))
    piece:addParam(sync:newParam("model", sync.paramTypes.variableLengthInteger, "model"))
    piece:addParam(sync:newParam("dimensions", sync.paramTypes.dimenions, "generic"))
    piece:addParam(sync:newParam("height", sync.paramTypes.variableLengthDecimal, "generic"))
    piece:addParam(sync:newParam("position", sync.paramTypes.variableLengthVec2, "doNothing"))
    piece:addParam(sync:newParam("slots", sync.paramTypes.variableLengthTable, "doNothing"))
    piece:addParam(sync:newParam("contents", sync.paramTypes.variableLengthTable, "generic"))
    piece:addParam(sync:newParam("contentsLimit", sync.paramTypes.variableLengthInteger, "generic"))
    piece:addParam(sync:newParam("flags", sync.paramTypes.flags, "pieceFlags"))
end

return SyncTypeSetup
