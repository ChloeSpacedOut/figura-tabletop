
local tabletopCore = require("...library.core")

local mainPage = action_wheel:newPage()
action_wheel:setPage(mainPage)


mainPage:newAction()
    :setTitle("Place Game")
    :onLeftClick(function ()
        local game = tabletopCore:newGame()
        game.position = player:getPos()
    end)

mainPage:newAction()
    :setTitle("Remove Game")
    :onLeftClick(function ()
        tabletopCore.currentGame:remove()
    end)


