local syncTypeSetup = require("..syncTypeSetup")
local clientHandler = require("..clientHandler")
local sync = require("..sync")

--#REGION Core

---The core of the tabletop library.
---@class TabletopCore
---@field currentGame Game? The currently active game.
local core = {
    currentGame = nil
}

---Creates a new game.
---@param uuid string? Unique UUID of this game.
---@return Game
function core:newGame(uuid)
    self.currentGame = core.Game:new(uuid)
    return self.currentGame
end

---User defined function that runs when a new game is created.
---@param game Game
function core.onNewGame(game) end

---Lets a user join an active game by providing their avatar variables.
---@param clientId string Client's UUID.
---@param pingsGlobal table Client's PingAPI global.
---@param modelsGlobal ModelPart Client's ModelAPI global.
---@param eventsGlobal EventsAPI Client's EventsAPI global.
---@param hostGlobal HostAPI Client's HostAPI global.
function core.joinGame(clientId, pingsGlobal, modelsGlobal, eventsGlobal, hostGlobal)
    if not core.currentGame then return end
    core.currentGame.clientHandler = clientHandler:new(core, clientId, pingsGlobal, modelsGlobal, eventsGlobal, hostGlobal)
end

--#ENDREGION

--#REGION Game

---Avatar variables to be stored alongside a tabletop game.
---@class AvatarVarGameInfo
---@field id string The UUID of this tabletop game.
---@field position Vector3 The position in the world of this tabletop game.
---@field open boolean If this tabletop game is currently open.
---@field joinGame function A function which when run lets you join the game.

---A tabletop game.
---@class Game
---@field id string This game's UUID.
---@field sync Sync This game's instance of the sync library.
---@field clientHandler ClientHandler? This game's intance of the client handler library.
---@field gameTime integer This game's internal timer.
---@field localOnly boolean If this game should disable syncing data when parameters are updated. Useful for initally setting up the game.
---@field isOpen boolean If this game is currently open and can be joined by players.
---@field position Vector3 The root position where this game will exist in the world.
---@field rotation Vector3 The root rotation of the game relative to the world.
---@field scale number The scale of this game relative to the world.
---@field slots Slot[] Table that contains all slots for this game.
---@field pieces Piece[] Table that contians all pieces for this game.
---@field playSpaces integer[] Table that the numeric id of all playspaces for this game.
---@field playSpaceIndex integer[] Table that contains the numeric index of all playspaces for this game.
---@field model ModelPart The root model part of this game.
---@field passiveSync SyncStream The passive sync sync stream. Used for passively syncing information about the game.
core.Game = {}
core.Game.__index = core.Game

---Creates a new game.
---@param uuid string? Unique ID of this game.
---@return Game
function core.Game:new(uuid)
    self = setmetatable({}, core.Game)

        if uuid then
        self.id = uuid
    else
        self.id = client.intUUIDToString(client.generateUUID())
    end

    self.sync = sync:new()
    self.sync:newHookType("model")
    self.clientHandler = nil

    self.gameTime = 0
    self.localOnly = false

    self.isOpen = true
    self.position = vec(0, 0, 0)
    self.rotation = vec(0, 0, 0)
    self.scale = 1

    self.slots = {}
    self.pieces = {}
    self.playSpaces = {}
    self.playSpaceIndex = {}

    self.model = models:newPart("tabletopRoot", "WORLD")

    core.currentGame = self

    syncTypeSetup:paramTypes(core, self)
    syncTypeSetup:onReceiveFunctions(core, self)

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

---Removes this game.
function core.Game:remove()
    avatar:store("tabletop", nil)
    self.model:remove()
    core.currentGame = nil
end

---Ticks this game.
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

---Sets if this game should disable syncing data when parameters are updated. Useful for initally setting up the game.
function core.Game:setLocalOnly(boolean)
    self.localOnly = boolean
end

---Updates a parameter and syncs this data.
---@param syncTypeId string The ID of the sync type releavant to data being updated and sent.
---@param objectId integer The object ID releavant to data being updated and sent.
---@param paramId string The parameter ID relevant to the data being updated and sent.
---@param syncData any The data being updated and sent.
---@return any
function core.Game:updateParam(syncTypeId, objectId, paramId, syncData)
    local returnValue = self.sync:localUpdate(syncTypeId, objectId, paramId, syncData)
    if self.clientHandler and (not self.localOnly) then
        local directSync = self.clientHandler.directSync
        directSync:send(syncTypeId, objectId, paramId, syncData)
    end
    return returnValue
end

---Scans through and syncs data stored for a sync type.
---@param syncStream SyncStream The sync stream to be used.
---@param syncType SyncType The sync type to be used.
---@param target table The target location to be scanned.
---@param isSingleInstance boolean If there is only a single instance of this sync type.
local function sendSyncTypeData(syncStream, syncType, target, isSingleInstance)
    if isSingleInstance then
        for paramId, _ in pairs(syncType.paramIndex) do
            local syncData = target[paramId]
            if syncData then
                syncStream:send(syncType.id, 1, paramId, syncData)
            end
        end
    else
        for objectId, object in pairs(target) do
            for paramId, _ in pairs(syncType.paramIndex) do
                local syncData = object[paramId]
                if syncData then
                    syncStream:send(syncType.id, objectId, paramId, syncData)
                end
            end
        end
    end
end

---Scans through and syncs all tabletop data.
function core.Game:doPassiveSync()
    sendSyncTypeData(self.passiveSync, self.sync:getSyncType("gameMeta"), self, true)
    sendSyncTypeData(self.passiveSync, self.sync:getSyncType("piece"), self.pieces, false)
    sendSyncTypeData(self.passiveSync, self.sync:getSyncType("slot"), self.slots, false)
end

---Registers a new model for this game.
---@param id string The string ID for this model.
---@param model ModelPart The modelpart being registered.
function core.Game:registerModel(id, model)
    ---@type HookType
    local modelHook = self.sync.hookTypes.model
    modelHook:add(id, model)
end

---Returns a model part when given its string ID.
---@param id string The string ID for this model.
---@return ModelPart
function core.Game:getModel(id)
    ---@type HookType
    local modelHook = self.sync.hookTypes.model
    return modelHook:getHook(id)
end

---Creates a new slot.
---@param id integer? The numeric ID of this slot.
---@return Slot
function core.Game:newSlot(id)
    if not id then
        id = #self.slots + 1
    end 
    return self:updateParam("slot", id, "id")
end

---Creates a new piece.
---@param id integer? The numeric id of this piece.
---@return Piece
function core.Game:newPiece(id)
    if not id then
        id = #self.pieces + 1
    end
    return self:updateParam("piece", id, "id")
end

---Creates a new play space slot.
---@return Slot
function core.Game:newPlaySpace()
    local id = #self.slots + 1
    local slot = self:newSlot(id)
    local playSpaces = self.playSpaces
    table.insert(playSpaces, id)
    
    self:updateParam("gameMeta", 1, "playSpaces", playSpaces)
    return slot
end

--#ENDREGION

--#REGION Slot

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
---@field id integer The numeric id of this slot.
---@field game Game The game this slot belongs to.
---@field parent integer The numeric id of this slot's parent piece.
---@field part ModelPart? This slot's reference to the model tree.
---@field dimensions {min: Vector2, max: Vector2} The dimensions of this slot, rounded down to 2 decimal places.
---@field position Vector2 The position of this slot relative to its parent piece, rounded down to 2 decimal places.
---@field rotation Vector3 The rotation of this slot relative to its parent piece, rounded down to 2 decimal places.
---@field lenience {min: Vector2, max: Vector2} How much objects can be moved within this slot, rounded down to 2 decimal places.
---@field contents integer[] Table of all pieces contained within this slot, stored by numeric id.
---@field flags SlotFlags This slot's flags.
core.Slot = {}
core.Slot.__index = core.Slot

---Creates a new slot.
---@param game Game The game this slot belongs to.
---@param id integer The numeric id of this slot.
---@return Slot
function core.Slot:new(game, id)
    self = setmetatable({}, core.Slot)
    self.id = id
    self.game = game
    self.parent = nil
    self.part = nil
    self.dimensions = {min = vec(0, 0), max = vec(0, 0)}
    self.position = vec(0, 0)
    self.rotation = vec(0, 0, 0)
    self.lenience = {min = vec(0, 0), max = vec(0, 0)}
    self.contents = {}
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

---Adds a new piece to this slot.
---@param piece Piece The piece to be added to this slot.
---@return Slot
function core.Slot:addPiece(piece)
    local contents = self.contents
    table.insert(contents, piece.id)
    self:update("contents", contents)
    return self
end

---Syncs and updates a parameter with the specified value for this slot.
---@param paramId string The parameter ID relevant to the data being updated and sent.
---@param syncData any The data being updated and sent.
---@return any
function core.Slot:update(paramId, syncData)
    return self.game:updateParam("slot", self.id, paramId, syncData)
end

--#ENDREGION

--#REGION Piece

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
---@field id integer The numeric id of this piece.
---@field game Game The game this piece belongs to.
---@field parent integer The numeric id of this piece's parent slot.
---@field part ModelPart? This piece's reference to the model tree.
---@field model ModelPart? The model the piece will copy and use.
---@field dimensions {min: Vector2, max: Vector2} The dimensions of this piece, rounded down to 2 decimal places.
---@field height number The height of this piece.
---@field position Vector2 The position of this piece within its parent slot. Clamped by the parent slot's lenience, and rounded down to 2 decimal places.
---@field slots Slot[] Table that contains all of this piece's slots.
---@field contents integer[] Table of all pieces contained within this piece, stored by numeric id.
---@field flags PieceFlags This piece's flags.
core.Piece = {}
core.Piece.__index = core.Piece

---@param game Game The game this piece belongs to.
---@param id integer The numeric id of this piece.
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

---Syncs and updates a parameter with the specified value for this piece.
---@param paramId string The parameter ID relevant to the data being updated and sent.
---@param value any The data being updated and sent.
---@return any
function core.Piece:update(paramId, value)
    return self.game:updateParam("piece", self.id, paramId, value)
end

---Sets the model of this piece.
---@param modelHookId string The registered string ID of this model.
---@return Piece
function core.Piece:setModel(modelHookId)
    self:update("model", self.game.sync.hookTypes.model.hookIndex[modelHookId])
    return self
end

--#ENDREGION

--#REGION Events

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

--#ENDREGION

return core
