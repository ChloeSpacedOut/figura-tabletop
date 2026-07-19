---@class TabletopCore
---@field currentGame Game? the currently active game
local core = {
    currentGame = nil
}

local paramSetup = require("..paramSetup"):new(core)
local util = require("..util")
local sync = require("..sync")

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

---@class Game
---@field gameTime integer this game's internal timer
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



    self.slots = {}
    self.pieces = {}
    self.worldPos = worldPos
    self.worldRot = worldRot
    self.paramTypes = paramSetup.defaultParamTypes
    self.paramHandlers = {
        slot = sync.SyncType:new(table.unpack(paramSetup.defaultSlotParams)),
        piece = sync.SyncType:new(table.unpack(paramSetup.defaultPieceParams))
    }
    self.syncStreams = {
        passive = sync.SyncStream:new(self, "passive", pings.passiveSync),
        direct = sync.SyncStream:new(self, "direct")
    }

    --self.root = core.Piece:new()

    core.currentGame = self
    return self
end

---creates a new syncStream
---@param id string
---@param pingFunction function?
function core.Game:newSyncStream(id, pingFunction)
    self.syncStreams[id] = sync.SyncStream:new(self, id, pingFunction)
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
---@diagnostic disable-next-line: duplicate-set-field
function events.tick()
    clock = clock + 1
    local game = core.currentGame
    if not game then return end
    game.gameTime = game.gameTime + 1
    -- for each active syncstream (add an is active field) send chunks. Revert if rate limited
    for id, syncStream in pairs(game.syncStreams) do
        syncStream:update()
        if syncStream.toSend[1] and syncStream.toSend[1].isSending and syncStream.toSend[1].toSend and clock % syncStream.packetInterval == 0 then
            local packetInterval = syncStream.packetInterval
            local syncSpeed = syncStream.syncSpeed
            local bytesPerPacket = math.floor(syncSpeed * (packetInterval / 20))
            local toSend = syncStream.toSend[1].toSend
            local currentPacket = syncStream.toSend[1].currentPacket
            local packet = string.sub(toSend,currentPacket * bytesPerPacket, (currentPacket + 1) * bytesPerPacket)
            syncStream.toSend[1].currentPacket = currentPacket + 1

            
            syncStream.ping(packet)
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
