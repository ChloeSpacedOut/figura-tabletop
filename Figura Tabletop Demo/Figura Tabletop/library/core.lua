local syncTypeSetup = require("..syncTypeSetup")
local clientHandler = require("..clientHandler")
local sync = require("..sync")

---@class TabletopCore
---@field currentGame Game? the currently active game
local core = {
    currentGame = nil
}

---creates a new game
---@param uuid string? Unique ID of this game
function core:newGame(uuid)
    self.currentGame = core.Game:new(uuid)
    return self.currentGame
end

---Function that runs when a new game is created
---@param game Game
function core.onNewGame(game) end

function core.joinGame(userId, pingsGlobal, modelsGlobal, eventsGlobal, hostGlobal)
    if not core.currentGame then return end
    core.currentGame.clientHandler = clientHandler:new(core, userId, pingsGlobal, modelsGlobal, eventsGlobal, hostGlobal)
end

---Avatar variables to be stored alongside a tabletop game.
---@class AvatarVarGameInfo
---@field id string The UUID of this tabletop game
---@field position Vector3 The position in the world of this tabletop game
---@field open boolean If this tabletop game is currently open.
---@field joinGame function A function which when run lets you join the game.

---@class Game
---@field sync Sync this game's instance of the sync library
---@field gameTime integer this game's internal timer
---@field postion Vector3 the root position where this game will exist in the world
---@field rotation Vector3 the root rotation of the game relative to the world
---@field slots Slot[] table that contains all slots
---@field pieces Piece[] table that contains all pieces
---@field playSpaces Slot[] table that contains all playspace slots
---@field root Piece the root piece of this game
---@field clientHandler ClientHandler?
core.Game = {}
core.Game.__index = core.Game

---creates a new game
---@param uuid string? Unique ID of this game
---@return Game
function core.Game:new(uuid)
    self = setmetatable({}, core.Game)

    self.sync = sync:new()
    self.sync:newHookType("model")

    self.clientHandler = nil

    if uuid then
        self.id = uuid
    else
        self.id = client.intUUIDToString(client.generateUUID())
    end
    
    self.gameTime = 0
    self.isOpen = true

    self.localOnly = false

    self.position = vec(0, 0, 0)
    self.rotation = vec(0, 0, 0)
    self.scale = 1

    self.slots = {}
    self.pieces = {}
    self.playSpaces = {}

    self.model = models:newPart("tabletopRoot", "WORLD")

    core.currentGame = self

    syncTypeSetup:new(core, self)

    self.passiveSync = self.sync:newSyncStream("passiveSync", pings.passiveSync)
    self.passiveSync.includeStreamId = false

    core.onNewGame(self)

    ---@type AvatarVarGameInfo
    local gameInfo = {
        id = self.id,
        position = vec(0, 0, 0),
        open = true,
        joinGame = core.joinGame
    }
    avatar:store("tabletop", gameInfo)

    return self
end

function core.Game:remove()
    avatar:store("tabletop", nil)
end

function core.Game:tick()
    self.sync:tick()
    if self.clientHandler then
        self.clientHandler:tick()
    end

    self.gameTime = self.gameTime + 1

    if not host:isHost() then return end
    if not self.passiveSync then return end
    if not self.passiveSync:getNewestSend() then
        self:doPassiveSync()
    end
end

function core.Game:setLocalOnly(boolean)
    self.localOnly = boolean
end

function core.Game:updateParam(syncTypeId, objectId, paramId, syncData)
    local returnValue = self.sync:localUpdate(syncTypeId, objectId, paramId, syncData)
    if self.clientHandler and (not self.localOnly) then
        local directSync = self.clientHandler.directSync
        directSync:send(syncTypeId, objectId, paramId, syncData)
    end
    return returnValue
end

local function sendSyncTypeData(syncStream, syncType, data, isSingleInstance)
    if isSingleInstance then
        for paramId, _ in pairs(syncType.paramIndex) do
            local syncData = data[paramId]
            if syncData then
                syncStream:send(syncType.id, 1, paramId, syncData)
            end
        end
    else
        for objectId, object in pairs(data) do
            for paramId, _ in pairs(syncType.paramIndex) do
                local syncData = object[paramId]
                if syncData then
                    syncStream:send(syncType.id, objectId, paramId, syncData)
                end
            end
        end
    end
end

function core.Game:doPassiveSync()
    sendSyncTypeData(self.passiveSync, self.sync:getSyncType("gameMeta"), self, true)
    sendSyncTypeData(self.passiveSync, self.sync:getSyncType("piece"), self.pieces, false)
    sendSyncTypeData(self.passiveSync, self.sync:getSyncType("slot"), self.slots, false)
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

---comment
---@param id any
---@return Slot
function core.Game:newSlot(id)
    if not id then
        id = #self.slots + 1
    end 
    ---@type Slot
    return self:updateParam("slot", id, "id")
end

---comment
---@param id any
---@return Piece
function core.Game:newPiece(id)
    if not id then
        id = #self.pieces + 1
    end
    ---@type Piece
    return self:updateParam("piece", id, "id")
end

---comment
---@return Slot
function core.Game:newPlaySpace() -- make this local
    local id = #self.slots + 1
    local slot = self:newSlot(id)
    local playSpaces = self.playSpaces
    table.insert(playSpaces, id)
    
    self:updateParam("gameMeta", 1, "playSpaces", playSpaces)
    return slot
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

function core.Slot:addPiece(piece)
    local contents = self.contents
    table.insert(contents, piece.id)
    self:update("contents", contents)
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
    self.game:updateParam("piece", self.id, paramId, value)
end

function core.Piece:setModel(modelHookId)
    self:update("model", self.game.sync.hookTypes.model.hookIndex[modelHookId])
end


function events.tick()
    if core.currentGame then
        core.currentGame:tick()
    end
end

function events.on_play_sound(id)
    if core.currentGame then
        core.currentGame.sync:on_play_sound(id)
    end
end

function pings.passiveSync(syncData)
    if not core.currentGame then
        local emptyID = client.intUUIDToString(0,0,0,0)
        core:newGame(emptyID)
    end
    local syncInstance = core.currentGame.sync
    local passiveSync = syncInstance:getSyncStream("passiveSync")

    if not passiveSync then return end
    passiveSync:receive(syncData)
end


return core
