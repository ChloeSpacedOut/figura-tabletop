---deep copies a table. From http://lua-users.org/wiki/CopyTable
---@param origional table
---@return table
local function deepcopyTable(origional)
    local orig_type = type(origional)
    local copy
    if orig_type == 'table' then
        copy = {}
        for origionalKey, orig_value in next, origional, nil do
            copy[deepcopyTable(origionalKey)] = deepcopyTable(orig_value)
        end
        setmetatable(copy, deepcopyTable(getmetatable(origional)))
    else
        copy = origional
    end
    return copy
end


local isInGame = false
local openGames = {}

local function joinGame(gameId, game)
    game.joinGame(avatar:getUUID(), pings, models, events, host)
end


local function updateOpenGames()
    local avatarVars = world.avatarVars()
    local existingGames = {}
    -- check for new open games
    for _, vars in pairs(avatarVars) do
        if not vars.tabletop then goto continue end
        
        
        local tabletop = vars.tabletop
        if not tabletop.game then goto continue end
        existingGames[tabletop.game.id] = true
        if tabletop.game.open and (not openGames[tabletop.game.id]) then
           openGames[tabletop.game.id] = deepcopyTable(tabletop.game)
           openGames[tabletop.game.id].joinProgress = 0
        end
        ::continue::
    end

    -- check for new closed games & update join progress
    for gameId, game in pairs(openGames) do
        if not existingGames[gameId] then
            openGames[gameId] = nil
            goto continue
        end

        if isInGame then goto continue end

        game.joinProgress = math.clamp(game.joinProgress - 0.01, 0, 1)
        ---@type Vector3
        local distanceFromPlayer =  (game.location - player:getPos()):length()
        if player:isCrouching() and (distanceFromPlayer < 2) then
            game.joinProgress = math.clamp(game.joinProgress + 0.03, 0, 1)
        end
        
        if math.floor(game.joinProgress) == 1 then
            joinGame(gameId, game)
            isInGame = true
        end

        ::continue::
    end
end

---@diagnostic disable-next-line: duplicate-set-field
function events.tick()
    updateOpenGames()
    

end