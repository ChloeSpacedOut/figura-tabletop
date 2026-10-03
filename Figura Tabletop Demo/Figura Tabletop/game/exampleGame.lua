local tabletopCore = require("...library.core")

function tabletopCore.onNewGame(game)
    game:registerModel("test", models["Figura Tabletop"].game.test.scout_launcher)

    if host:isHost() then

        local playspace = game:newPlaySpace()
        local testPiece = game:newPiece()
        testPiece.model = game.sync.hookTypes.model.hookIndex.test
        testPiece.parent = playspace.id
        table.insert(playspace.contents, testPiece.id)
        
    end
end 

--log(game)

-- next to do:
-- ID shouldn't be synced twice
-- add framework for instant sync
-- game create event that hooks into the game first being made