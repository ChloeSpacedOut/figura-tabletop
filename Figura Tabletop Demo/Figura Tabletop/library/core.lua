local syncTypeSetup = require("..syncTypeSetup")
local syncHandler = require("..syncHandler")
local sync = require("..sync")

---@class TabletopCore
---@field currentGame Game? the currently active game
local core = {
    currentGame = nil
}

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

    --self.root = core.Piece:new()

    syncTypeSetup:create(core)
    self.syncHandler = syncHandler:setup(self)

    core.currentGame = self
    return self
end

---Creates a new game slot
function core.Game:newSlot()
    local id = #self.slots + 1
    table.insert(self.slots, core.Slot:new(self, id))
end


function core.Game:newPiece()
    local id = #self.pieces + 1
    table.insert(self.pieces, core.Piece:new(self, id))
end

---@diagnostic disable-next-line: duplicate-set-field
function events.tick()
    local game = core.currentGame
    if not game then return end
    game.gameTime = game.gameTime + 1

    game.syncHandler:update()
end


---@class Slot
---@field id integer unique id of this slot
---@field lastSynced integer how long it has been since this slot was last synced
---@field parent integer the id of this slot's parent piece
---@field contents integer[] table of all pieces contained within this slot, stored by id
---@field dimensions Dimensions dimensions of this slot. Rounded down to 2 decimal places
---@field position Vector2 position of this slot relative to its parent piece. Rounded down to 2 decimal places
---@field lenience Dimensions how much objects can be moved within this slot. Rounded down to 2 decimal places
core.Slot = {}
core.Slot.__index = core.Slot
---@param game Game the game that uses this slot
---@return Slot
function core.Slot:new(game, id)
    self = setmetatable({}, core.Slot)
    self.id = id
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
    self.game:updateParam("slot", self.id, paramId, value)
end

---@class Piece
---@field id integer unique ID of the piece
---@field parent Slot parent slot of this piece
---@field model ModelPart model the piece will copy and use
---@field dimensions Dimensions dimensions of this piece
---@field height number height of this piece
---@field position Vector2 position within this piece's parent slot. Clamped by the parent slot's lenience
---@field slots Slot[] table that contains all of this piece's slots
---@field contents integer[] table of all pieces contained within this piece, stored by id
core.Piece = {}
core.Piece.__index = core.Piece
---@param game Game the game that uses this slot
---@param id integer the unique ID of this peice
---@return Piece
function core.Piece:new(game, id)
    self = setmetatable({}, core.Piece)
    self.id = id
    self.game = game
    self.parent = nil
    self.model = nil
    self.dimensions = core.Dimensions:new(vec(-1, -1), vec(1, 1))
    self.height = 2
    self.position = vec(-0.00, 1)
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
