local util = require("..util")

---Contains the sync type setup functions.
---@class SyncTypeSetup
local SyncTypeSetup = {}

--#REGION ParamType Setup

---Sets up parameter types for tabletop.
---@param core TabletopCore The core of the tabletop library.
---@param game Game This tabletop game.
function SyncTypeSetup:paramTypes(core, game)
    local sync = game.sync

    ---no data
    sync:newParamType("empty",
        function(encoded, paramTypes)
            return ""
        end,
        function(rawData, paramTypes)
            return ""
        end
    )

    ---a string. Every character costs 1 byte to use spairingly
    sync:newParamType("string",
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
    sync:newParamType("boolean",
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
    sync:newParamType("flags",
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
    sync:newParamType("variableLengthInteger",
        function(encoded, paramTypes)
            local integer = util.readVariableLengthInt(encoded)
            return integer
        end,
        function(rawData, paramTypes)
            return util.numToVarLengthInt(rawData)
        end
    )

    ---a variable length integer that supports negative values though zig-zag encoding. This takes more space
    sync:newParamType("variableLengthIntegerZZ",
        function(encoded, paramTypes)
            local integer = util.readVariableLengthIntZZ(encoded)
            return integer
        end,
        function(rawData, paramTypes)
            return util.numToVarLengthIntZZ(rawData)
        end
    )

    ---a variable length decimal with 2 decimal places. Useful for compressed decimals with low precision. Supports negative values
    sync:newParamType("variableLengthDecimal",
        function(encoded, paramTypes)
            ---@type number
            return paramTypes["variableLengthIntegerZZ"].decode(encoded, paramTypes) / 100
        end,
        function(rawData, paramTypes)
            return paramTypes["variableLengthIntegerZZ"].encode(math.floor(rawData * 100), paramTypes)
        end
    )

    ---a vector 2 that uses variable length integers with 2 decimal places. Useful for compressed vec2 with low precision. Supports negative values
    sync:newParamType("variableLengthVec2",
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
    sync:newParamType("variableLengthVec3",
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
    sync:newParamType("unitInterval",
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
    sync:newParamType("integer",
        function(encoded, paramTypes)
            return encoded:readInt()
        end,
        function(rawData, paramTypes)
            local buffer = data:createBuffer()
            buffer:writeInt(rawData)
            buffer:setPosition(0)
            local encodedInt = buffer:readByteArray(4)
            buffer:close()
            return encodedInt
        end
    )

    ---a 64 bit double (8 bytes)
    sync:newParamType("double",
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
    sync:newParamType("float",
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
    sync:newParamType("short",
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
    sync:newParamType("variableLengthTable",
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
            for _, int in pairs(rawData) do
                values = values .. util.numToVarLengthInt(int)
            end
            local dataLength = util.numToVarLengthInt(string.len(values))
            return dataLength .. values
        end
    )

    ---a UUID
    sync:newParamType("UUID",
        function(encoded, paramTypes)
            local intArray = {}
            for i = 1, 4 do
                intArray[i] = util.readVariableLengthIntZZ(encoded)
            end
            return client.intUUIDToString(table.unpack(intArray))
        end,
        function(rawData, paramTypes)
            local uuid = ""
            local intArray = table.pack(client.uuidToIntArray(rawData))
            for i = 1, 4 do
                uuid = uuid .. util.numToVarLengthIntZZ(intArray[i])
            end
            return uuid
        end
    )

    ---a dimenions object. For compression, decimals only have 2 decimal places (nothing under 0.01)
    sync:newParamType("dimenions",
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
end

--#ENDREGION

--#REGION OnReceive Functions Setups

---Sets up on receive functions for tabletop.
---@param core TabletopCore The core of the tabletop library.
---@param game Game This tabletop game.
function SyncTypeSetup:onReceiveFunctions(core, game)
    local sync = game.sync
    -- improve annotations later so this declaration isn't needed

    ---@type HookType
    local onReceive = sync.hookTypes.onReceive

    onReceive:add("newGame", function(data, paramId, objectId, syncTypeId, isLocalUpdate)

        if core.currentGame and core.currentGame.id == data then return end

        if core.currentGame and core.currentGame.id ~= data then
            core.currentGame:remove()
        end

        core:newGame(data)
    end)

    onReceive:add("gamePos", function(data, paramId, objectId, syncTypeId, isLocalUpdate)
        local game = core.currentGame
        if not game then return end
        if game.position == data then return end
        game.position = data
        game.model:setPos(data * 16)
        ---@type AvatarVarGameInfo
        local gameInfo = {
            id = game.id,
            joinGame = core.joinGame,
            open = game.isOpen,
            position = data
        }
        avatar:store("tabletop", gameInfo)
    end)

    onReceive:add("gameRot", function(data, paramId, objectId, syncTypeId, isLocalUpdate)
        if core.currentGame.rotation == data then return end
        core.currentGame.rotation = data
        core.currentGame.model:setRot(data)
    end)

    onReceive:add("doNothing", function(data, paramId, objectId, syncTypeId, isLocalUpdate)
        --log(data, paramId, objectId, syncTypeId, isLocalUpdate)

    end)

    onReceive:add("playSpaces", function(data, paramId, objectId, syncTypeId, isLocalUpdate)
        if table.concat(game.playSpaces, ",") == table.concat(data, ",") then return end

        game.playSpaces = data
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
        -- make sure to finish this, rn you're just discarding it
    end)

    onReceive:add("slotId", function(data, paramId, objectId, syncTypeId, isLocalUpdate)
        if game.slots[objectId] then return end
        local slot = core.Slot:new(game, objectId)
        game.slots[objectId] = slot
        return slot
    end)

    onReceive:add("slotContents", function(data, paramId, objectId, syncTypeId, isLocalUpdate)
        local slot = game.slots[objectId]
        if not slot then return end
        if table.concat(slot.contents, ",") == table.concat(data, ",") then return end
        slot.contents = data

        for _,pieceId in pairs(data) do
            local piece = game.pieces[pieceId]
            if piece then
                piece.parent = objectId
            end
        end
    end)

    onReceive:add("pieceId", function(data, paramId, objectId, syncTypeId, isLocalUpdate)
        if game.pieces[objectId] then return end
        local piece = core.Piece:new(game, objectId)
        game.pieces[objectId] = piece
        return piece
    end)

    onReceive:add("generic", function(data, paramId, objectId, syncTypeId, isLocalUpdate)
        local syncTypeTable = game[syncTypeId .. "s"]
        if not syncTypeTable[objectId] then return end
        syncTypeTable[objectId][paramId] = data
    end)

    onReceive:add("model", function(data, paramId, objectId, syncTypeId, isLocalUpdate)
        local piece = game.pieces[objectId]
        if not piece then return end
        if data == piece.model then return end

        piece.model = data
        ---@type HookType
        local modelHook = sync.hookTypes.model
        ---@type ModelPart
        local model = modelHook.hooks[data]
        local parentSlotID = piece.parent
        -- make a playspace index table
        -- ensure the playspace table is being saved correctly on both clients
        log(game.playSpaces)
        if game.playSpaces[parentSlotID] and (not game.slots[parentSlotID].part) then
            game.slots[objectId].part = game.model:newPart("playspace-"..parentSlotID)
            log('a')
        end
        if parentSlotID and game.slots[parentSlotID].part then
            log("a")
            game.slots[parentSlotID].part:addChild(model:copy(objectId)) -- CHANGE TO A DEEPCOPY
        end
        -- deepcopy the model part. Save to parent.

    end)
end

--#ENDREGION

--#REGION Params Setup

---Sets up parameters for tabletop.
---@param core TabletopCore The core of the tabletop library.
---@param game Game This tabletop game.
function SyncTypeSetup:params(core, game)
    local sync = game.sync

    local gameMeta = sync:newSyncType("gameMeta")
    local slot = sync:newSyncType("slot")
    local piece = sync:newSyncType("piece")

    gameMeta:addParam(sync:newParam("id", sync.paramTypes.UUID, "newGame"))
    gameMeta:addParam(sync:newParam("position", sync.paramTypes.variableLengthVec3, "gamePos"))
    gameMeta:addParam(sync:newParam("rotation", sync.paramTypes.variableLengthVec3, "gameRot"))

    gameMeta:addParam(sync:newParam("playSpaces", sync.paramTypes.variableLengthTable, "playSpaces"))
    slot:addParam(sync:newParam("id", sync.paramTypes.empty, "slotId"))
    piece:addParam(sync:newParam("id", sync.paramTypes.empty, "pieceId"))

    slot:addParam(sync:newParam("parent", sync.paramTypes.variableLengthInteger, "generic"))
    slot:addParam(sync:newParam("contents", sync.paramTypes.variableLengthTable, "slotContents"))
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

--#ENDREGION

return SyncTypeSetup
