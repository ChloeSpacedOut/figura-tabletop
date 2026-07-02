local core = require("..core")
local clientHandler = require("..clientHandler")


models.model:setVisible(true)

local mainPage = action_wheel:newPage()
action_wheel:setPage(mainPage)

local function joinGame(userId, pingsGlobal, modelsGlobal, eventsGlobal, hostGlobal)
    clientHandler.tabletopClient = {
        userId = userId,
        pings = pingsGlobal,
        models = modelsGlobal,
        events = eventsGlobal,
        host = hostGlobal
    }

    pingsGlobal.directSync = core.directSync
    core.currentGame:newSyncStream("direct", pingsGlobal.directSync)
end

function pings.test()

end

function pings.newGame()
     local tabletop = {
            game = {
                id = client.generateUUID(),
                location = player:getPos(),
                open = true,
                joinGame = joinGame
            }
        }
        avatar:store("tabletop", tabletop)
end


mainPage:newAction()
    :setTitle("Place Game")
    :onLeftClick(pings.newGame)

mainPage:newAction()
    :setTitle("Remove Game")


