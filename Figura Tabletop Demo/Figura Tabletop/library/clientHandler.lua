---@class ClientHandler
---@field client TabletopClient
local clientHandler = {}

---@class TabletopClient
---@field userId string client's user ID
---@field pings table client's PingAPI global
---@field models ModelPart client's ModelAPI global
---@field events EventsAPI client's EventsAPI global
---@field host HostAPI client's HostAPI global
clientHandler.tabletopClient =  nil


return clientHandler