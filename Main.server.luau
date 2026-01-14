-- Main.server.luau (Place in ServerScriptService)
-- System entry point
local ServerScriptService = game:GetService("ServerScriptService")

-- Create folder structure
local AntiCheatFolder = Instance.new("Folder")
AntiCheatFolder.Name = "AntiCheatUG"
AntiCheatFolder.Parent = ServerScriptService

-- Load modules
local SecurityConfig = require(script.Parent.SecurityConfig)
local MainHandler = require(script.Parent.MainHandler)

-- Initialize system
local antiCheatSystem = MainHandler.new()

-- Start with delay to ensure game is loaded
task.wait(3)

-- Initialize anti-cheat
antiCheatSystem:Initialize()

-- Safety cleanup on shutdown
game:BindToClose(function()
    antiCheatSystem:Shutdown()
    task.wait(1)
end)

-- Return system for external access
return {
    System = antiCheatSystem,
    Version = antiCheatSystem.Version,
    Config = SecurityConfig
}
