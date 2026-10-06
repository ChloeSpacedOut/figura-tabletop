local tabletopCore = require("...library.core")

function tabletopCore.onNewGame(game)
    game:registerModel("test", models["Figura Tabletop"].game.test.scout_launcher)

    if host:isHost() then
        game:setLocalOnly(true)
        
        local playspaceSlot = game:newPlaySpace()
        local testPiece = game:newPiece()
        testPiece:setModel("test")
        playspaceSlot:addPiece(testPiece)

        game:setLocalOnly(false)
        
        
    end
end 

--log(game)

-- next to do:
-- ID shouldn't be synced twice
-- add framework for instant sync
-- game create event that hooks into the game first being made