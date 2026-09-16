local syncTypeSetup = require("..syncTypeSetup")
local syncHandler = require("..syncHandler")
local sync = require("..sync")

---@class TabletopCore
---@field currentGame Game? the currently active game
local core = {
    currentGame = nil
}

---@class Game
---@field sync Sync this game's instance of the sync library
---@field gameTime integer this game's internal timer
---@field worldPos Vector3 the root position where this game will exist in the world
---@field worldRot Vector3 the root rotation of the game relative to the world
---@field slots Slot[] table that contains all slots
---@field pieces Piece[] table that contains all pieces
---@field playSpaces Slot[] table that contains all playspace slots
---@field root Piece the root piece of this game
core.Game = {}
core.Game.__index = core.Game

---creates a new game
---@param postion Vector3 the root position where this game will exist in the world
---@param rotation Vector3 the root rotation of the game relative to the world
---@return Game
function core.Game:new(postion, rotation)
    self = setmetatable({}, core.Game)

    self.sync = sync:new()
    self.sync:newHookType("model")
    self.gameTime = 0

    self.position = postion
    self.rotation = rotation
    self.scale = 1

    self.slots = {}
    self.pieces = {}
    self.playSpaces = {}

    self.model = models:newPart("tabletopRoot", "WORLD")

    --self.root = core.Piece:new()

    core.currentGame = self

    syncTypeSetup:create(core)
    self.syncHandler = syncHandler:setup(self)
    return self
end

function core.Game:registerModel(id, model)
    ---@type HookType
    local modelHook = self.sync.hookTypes.model
    modelHook:add(id, model)
end

function core.Game:getModel(id)
    ---@type HookType
    local modelHook = self.sync.hookTypes.model
    return modelHook:getHook(id)
end

---Creates a new game slot
function core.Game:newSlot()
    local id = #self.slots + 1
    table.insert(self.slots, core.Slot:new(self, id))
end


function core.Game:newPiece()
    local id = #self.pieces + 1
    local piece = core.Piece:new(self, id)
    table.insert(self.pieces, piece)
    return piece
end

function core.Game:newPlaySpace()
    local id = #self.slots + 1
    local slot = core.Slot:new(self, id)
    table.insert(self.slots, slot)
    table.insert(self.playSpaces, id)
    return slot
end

---@diagnostic disable-next-line: duplicate-set-field
function events.tick()
    local game = core.currentGame
    if not game then return end
    game.gameTime = game.gameTime + 1

    game.syncHandler:update()
end

---@class SlotFlags
---@field visible boolean If this slot is visible.
---@field canAddContents boolean If this slot can have pieces added to it.
---@field canMoveContents boolean If pieces within this slot can be moved.
---@field canRemoveContents boolean If this slot can have pieces removed from it.
---@field isDeleted boolean If this slot is deleted and should be removed from the board.
---@field unused1 boolean Unused flag.
---@field unused2 boolean Unused flag.
---@field unused3 boolean Unused flag.

---@class Slot
---@field id integer unique id of this slot
---@field parent integer the id of this slot's parent piece
---@field part ModelPart? this slot's reference to the model tree
---@field contents integer[] table of all pieces contained within this slot, stored by id
---@field dimensions {min: Vector2, max: Vector2} dimensions of this slot. Rounded down to 2 decimal places
---@field position Vector2 position of this slot relative to its parent piece. Rounded down to 2 decimal places
---@field lenience {min: Vector2, max: Vector2} how much objects can be moved within this slot. Rounded down to 2 decimal places
---@field flags SlotFlags table that contains this slot's flags.
core.Slot = {}
core.Slot.__index = core.Slot
---@param game Game the game that uses this slot
---@return Slot
function core.Slot:new(game, id)
    self = setmetatable({}, core.Slot)
    self.id = id
    self.game = game
    self.parent = nil
    self.part = nil
    self.contents = {}
    self.dimensions = {min = vec(0, 0), max = vec(0, 0)}
    self.position = vec(0, 0)
    self.rotation = vec(0, 0, 0)
    self.lenience = {min = vec(0, 0), max = vec(0, 0)}
    self.flags = {
        visible = true,
        canAddContents = true,
        canRemoveContents = true,
        canMoveContents = true,
        isDeleted = false,
        unused1 = false,
        unused2 = false,
        unused3 = false,
    }
    return self
end

---Syncs and updates a parameter with the specified value. Use this instead of setting your parameters directly
---@param paramId string
---@param value any
function core.Slot:update(paramId, value)
    self.game:updateParam("slot", self.id, paramId, value)
end

---@class PieceFlags
---@field visible boolean If this piece is visible.
---@field canInteract boolean If this piece can be right-click interacted with.
---@field canMove boolean If this piece can be moved within or from its parent slot.
---@field canSelect boolean If this piece can be selected when hovering with the cursor.
---@field isDeleted boolean If this piece is deleted and should be removed from the board.
---@field isSelected boolean If this piece is current selected by a player -- THIS MAY NEED TO BECOME ITS OWN FIELD TO HANDLE WHO IS SELECTING
---@field unused1 boolean Unused flag.
---@field unused2 boolean Unused flag.

---@class Piece
---@field id integer unique ID of the piece
---@field parent integer index of the parent slot of this piece
---@field part ModelPart? this piece's reference to the model tree
---@field model ModelPart? model the piece will copy and use
---@field dimensions {min: Vector2, max: Vector2} dimensions of this piece. Rounded down to 2 decimal places
---@field height number height of this piece
---@field position Vector2 position within this piece's parent slot. Clamped by the parent slot's lenience
---@field slots Slot[] table that contains all of this piece's slots
---@field contents integer[] table of all pieces contained within this piece, stored by id
---@field flags PieceFlags table that contains this piece's flags.
core.Piece = {}
core.Piece.__index = core.Piece
---@param game Game the game that uses this slot
---@param id integer the unique ID of this piece
---@return Piece
function core.Piece:new(game, id)
    self = setmetatable({}, core.Piece)
    self.id = id
    self.game = game
    self.parent = nil
    self.part = nil
    self.model = nil
    self.dimensions = {min = vec(-1, -1), max = vec(1, 1)}
    self.height = 2
    self.position = vec(-0.00, 1)
    self.slots = {}
    self.contents = {}
    self.flags = {
        visible = true,
        canInteract = true,
        canMove = true,
        canSelect = true,
        isDeleted = false,
        isSelected = false,
        unused1 = false,
        unused2 = false,
    }
    return self
end

---Syncs and updates a parameter with the specified value. Use this instead of setting your parameters directly
---@param paramId string
---@param value any
function core.Piece:update(paramId, value)
    self.game:updateParam("piece", paramId, value)
end

return core
