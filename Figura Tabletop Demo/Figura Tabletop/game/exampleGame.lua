local tabletopCore = require("...library.core")
local game = tabletopCore.Game:new()


game:registerModel("test", models["Figura Tabletop"].game.test.scout_launcher)

if host:isHost() then
    

    local playspace = game:newPlaySpace()
    local testPiece = game:newPiece()
    testPiece.model = game.sync.hookTypes.model.hookIndex.test
    testPiece.parent = playspace.id
    table.insert(playspace.contents, testPiece.id)

end
--log(game)