-- MainHandler.server.luau
-- Core Anti-Cheat System Handler
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- Security Modules
local SecurityConfig = require(script.Parent.SecurityConfig)
local DetectionModules = require(script.Parent.DetectionModules)

local AntiCheatUG = {}
AntiCheatUG.__index = AntiCheatUG
AntiCheatUG.Version = "1.0.0"

-- Internal State
local PlayerData = {}
local BanStore = DataStoreService:GetDataStore(SecurityConfig.BanSystem.DATASTORE_NAME)

-- Secure Event for client communication
local SecurityEvent = Instance.new("RemoteEvent")
SecurityEvent.Name = "AntiCheatUG_SecurityEvent"
SecurityEvent.Parent = game:GetService("ReplicatedStorage")

-- Secure Function for validation
local ValidationFunction = Instance.new("RemoteFunction")
ValidationFunction.Name = "AntiCheatUG_Validation"
ValidationFunction.Parent = game:GetService("ReplicatedStorage")

function AntiCheatUG.new()
    local self = setmetatable({}, AntiCheatUG)
    self._detectionModules = {}
    self._connections = {}
    return self
end

--[[
    Initialize Anti-Cheat System
]]
function AntiCheatUG:Initialize()
    if self._initialized then
        warn("[AntiCheat-UG] Already initialized")
        return
    end
    
    print(string.format("[AntiCheat-UG] Initializing v%s...", self.Version))
    
    -- Initialize detection modules
    self:_initDetectionModules()
    
    -- Set up player handlers
    self:_setupPlayerHandlers()
    
    -- Initialize ban checking
    self:_initBanSystem()
    
    self._initialized = true
    print("[AntiCheat-UG] System initialized successfully")
    
    -- Periodic cleanup
    self:_startCleanupTask()
end

--[[
    Initialize all detection modules
]]
function AntiCheatUG:_initDetectionModules()
    self._detectionModules = {
        SpeedHack = DetectionModules.SpeedHackDetector.new(),
        Teleport = DetectionModules.TeleportDetector.new(),
        NoClip = DetectionModules.NoClipDetector.new(),
        RemoteSecurity = DetectionModules.RemoteSecurity.new(),
        HumanoidValidator = DetectionModules.HumanoidValidator.new()
    }
    
    -- Connect detection callbacks
    for moduleName, module in pairs(self._detectionModules) do
        if module.OnViolation then
            module.OnViolation:Connect(function(player, violationData)
                self:_handleViolation(player, moduleName, violationData)
            end)
        end
    end
end

--[[
    Set up player connection/disconnection handlers
]]
function AntiCheatUG:_setupPlayerHandlers()
    -- Player joining
    self._connections.playerAdded = Players.PlayerAdded:Connect(function(player)
        self:_onPlayerJoin(player)
    end)
    
    -- Player leaving
    self._connections.playerRemoving = Players.PlayerRemoving:Connect(function(player)
        self:_onPlayerLeave(player)
    end)
    
    -- Handle existing players
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            self:_onPlayerJoin(player)
        end)
    end
end

--[[
    Initialize ban checking system
]]
function AntiCheatUG:_initBanSystem()
    -- Listen for validation requests
    ValidationFunction.OnServerInvoke = function(player, validationToken)
        return self:_validateClient(player, validationToken)
    end
    
    -- Set up security event
    SecurityEvent.OnServerEvent:Connect(function(player, eventType, data)
        self:_handleSecurityEvent(player, eventType, data)
    end)
end

--[[
    Handle player joining
]]
function AntiCheatUG:_onPlayerJoin(player)
    -- Check if player is banned
    local isBanned = self:_checkBan(player)
    if isBanned then
        player:Kick(" Whoooppsss! Your account is permanently banned")
        return
    end
    
    -- Initialize player data
    PlayerData[player] = {
        JoinTime = os.time(),
        ViolationCount = 0,
        LastViolation = 0,
        LastPosition = nil,
        ChecksEnabled = true,
        ClientValidated = false,
        SessionId = HttpService:GenerateGUID(false)
    }
    
    -- Initialize detection modules for player
    for _, module in pairs(self._detectionModules) do
        if module.InitializePlayer then
            module:InitializePlayer(player)
        end
    end
    
    -- Request client validation
    self:_requestClientValidation(player)
    
    -- Start monitoring
    self:_startPlayerMonitoring(player)
    
    if SecurityConfig.Logging.VERBOSE then
        print(string.format("[AntiCheat-UG] Player %s joined (Session: %s)", 
              player.Name, PlayerData[player].SessionId))
    end
end

--[[
    Handle player leaving
]]
function AntiCheatUG:_onPlayerLeave(player)
    -- Clean up detection modules
    for _, module in pairs(self._detectionModules) do
        if module.CleanupPlayer then
            module:CleanupPlayer(player)
        end
    end
    
    -- Remove player data
    PlayerData[player] = nil
    
    if SecurityConfig.Logging.VERBOSE then
        print(string.format("[AntiCheat-UG] Player %s left", player.Name))
    end
end

--[[
    Request client-side validation
]]
function AntiCheatUG:_requestClientValidation(player)
    -- Generate validation token
    local token = HttpService:GenerateGUID(false)
    PlayerData[player].ValidationToken = token
    
    -- Send validation request to client
    SecurityEvent:FireClient(player, "Validate", {
        Token = token,
        Timestamp = os.time()
    })
    
    -- Set validation timeout
    task.delay(10, function()
        if PlayerData[player] and not PlayerData[player].ClientValidated then
            self:_handleViolation(player, "ANTI_TAMPER", {
                Reason = "Client validation timeout",
                Code = SecurityConfig.BanSystem.VIOLATION_CODES.ANTI_TAMPER
            })
        end
    end)
end

--[[
    Validate client response
]]
function AntiCheatUG:_validateClient(player, validationToken)
    if not PlayerData[player] then return false end
    
    -- Check token
    if validationToken == PlayerData[player].ValidationToken then
        PlayerData[player].ClientValidated = true
        PlayerData[player].LastValidation = os.time()
        
        if SecurityConfig.Logging.VERBOSE then
            print(string.format("[AntiCheat-UG] Client validated for %s", player.Name))
        end
        return true
    end
    
    -- Invalid token
    self:_handleViolation(player, "ANTI_TAMPER", {
        Reason = "Invalid validation token",
        Code = SecurityConfig.BanSystem.VIOLATION_CODES.ANTI_TAMPER
    })
    return false
end

--[[
    Handle security violations
]]
function AntiCheatUG:_handleViolation(player, violationType, violationData)
    -- Check if player is whitelisted
    if self:_isWhitelisted(player) then
        if SecurityConfig.Logging.VERBOSE then
            print(string.format("[AntiCheat-UG] Whitelisted player %s triggered %s", 
                  player.Name, violationType))
        end
        return
    end
    
    -- Update violation count
    if not PlayerData[player] then return end
    
    PlayerData[player].ViolationCount = (PlayerData[player].ViolationCount or 0) + 1
    PlayerData[player].LastViolation = os.time()
    
    -- Check if threshold exceeded
    if PlayerData[player].ViolationCount >= SecurityConfig.Thresholds.MAX_ANOMALY_COUNT then
        -- Apply ban
        self:_applyBan(player, violationType, violationData)
    else
        -- Log violation
        self:_logViolation(player, violationType, violationData)
        
        -- Warning to client
        SecurityEvent:FireClient(player, "Warning", {
            Type = violationType,
            Count = PlayerData[player].ViolationCount,
            Max = SecurityConfig.Thresholds.MAX_ANOMALY_COUNT
        })
        
        -- Announce in server (optional)
        self:_announceViolation(player, violationType, false)
    end
end

--[[
    Apply permanent ban
]]
function AntiCheatUG:_applyBan(player, violationType, violationData)
    if not player or not player.Parent then return end
    
    -- Generate ban data
    local banId = "BAN_" .. player.UserId .. "_" .. os.time()
    local violationCode = violationData.Code or SecurityConfig.BanSystem.VIOLATION_CODES.ANTI_TAMPER
    
    local banData = {
        PlayerId = player.UserId,
        PlayerName = player.Name,
        BanId = banId,
        ViolationType = violationType,
        ViolationCode = violationCode,
        ViolationData = violationData,
        Timestamp = os.time(),
        SessionId = PlayerData[player] and PlayerData[player].SessionId or "UNKNOWN"
    }
    
    -- Save to DataStore
    local success, err = pcall(function()
        BanStore:SetAsync(SecurityConfig.BanSystem.KEY_PREFIX .. player.UserId, banData)
    end)
    
    if not success and SecurityConfig.Logging.ENABLED then
        warn("[AntiCheat-UG] Failed to save ban:", err)
    end
    
    -- Create ban message
    local banMessage = SecurityConfig.BanSystem.BAN_MESSAGE
        :gsub("{VIOLATION}", violationType)
        :gsub("{CODE}", violationCode)
    
    -- Kick player
    player:Kick(banMessage)
    
    -- Server announcement
    self:_announceViolation(player, violationType, true)
    
    -- Log ban
    if SecurityConfig.Logging.ENABLED then
        print(string.format(
            "[AntiCheat-UG] BANNED | Player: %s (%d) | Type: %s | Code: %s",
            player.Name, player.UserId, violationType, violationCode
        ))
    end
end

--[[
    Announce violation in server
]]
function AntiCheatUG:_announceViolation(player, violationType, isBan)
    if not SecurityConfig.Logging.ENABLED then return end
    
    local message = isBan and
        string.format("[SECURITY] %s has been permanently banned for cheating (%s)", 
                     player.Name, violationType) or
        string.format("[SECURITY] %s detected for %s", player.Name, violationType)
    
    -- Send to all players (optional - can be disabled)
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player then
            SecurityEvent:FireClient(otherPlayer, "Notification", {
                Type = "SecurityAlert",
                Message = message
            })
        end
    end
end

--[[
    Check if player is whitelisted
]]
function AntiCheatUG:_isWhitelisted(player)
    -- Check user ID whitelist
    for _, id in ipairs(SecurityConfig.Whitelists.AdminUserIds) do
        if player.UserId == id then
            return true
        end
    end
    
    -- Check game whitelist
    local gameId = game.PlaceId
    for _, allowedId in ipairs(SecurityConfig.Whitelists.AllowedSpeedBoostGames) do
        if gameId == allowedId then
            return true
        end
    end
    
    return false
end

--[[
    Check if player is banned
]]
function AntiCheatUG:_checkBan(player)
    local success, banData = pcall(function()
        return BanStore:GetAsync(SecurityConfig.BanSystem.KEY_PREFIX .. player.UserId)
    end)
    
    if success and banData then
        if SecurityConfig.Logging.VERBOSE then
            print(string.format("[AntiCheat-UG] Banned player attempted to join: %s", player.Name))
        end
        return true
    end
    
    return false
end

--[[
    Log violation
]]
function AntiCheatUG:_logViolation(player, violationType, violationData)
    if not SecurityConfig.Logging.ENABLED then return end
    
    print(string.format(
        "[AntiCheat-UG] VIOLATION | Player: %s | Type: %s | Count: %d",
        player.Name, violationType, PlayerData[player].ViolationCount
    ))
end

--[[
    Handle security events from client
]]
function AntiCheatUG:_handleSecurityEvent(player, eventType, data)
    if not PlayerData[player] or not PlayerData[player].ClientValidated then
        return
    end
    
    -- Process different event types
    if eventType == "Heartbeat" then
        PlayerData[player].LastHeartbeat = os.time()
    elseif eventType == "Report" then
        -- Handle client reports
        if data and data.Type then
            self:_logViolation(player, "CLIENT_REPORT_" .. data.Type, data)
        end
    end
end

--[[
    Start player monitoring
]]
function AntiCheatUG:_startPlayerMonitoring(player)
    -- Position tracking for teleport detection
    local lastPosition = nil
    
    -- Monitoring loop
    local connection
    connection = RunService.Heartbeat:Connect(function(deltaTime)
        if not PlayerData[player] or not player:IsDescendantOf(game) then
            connection:Disconnect()
            return
        end
        
        local character = player.Character
        if not character then return end
        
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        
        if not humanoid or not rootPart then return end
        
        -- Update position for next check
        lastPosition = rootPart.Position
    end)
    
    table.insert(self._connections, connection)
end

--[[
    Start cleanup task
]]
function AntiCheatUG:_startCleanupTask()
    task.spawn(function()
        while true do
            task.wait(300) -- Clean up every 5 minutes
            
            -- Reset violation counts after timeout
            local currentTime = os.time()
            for player, data in pairs(PlayerData) do
                if data.LastViolation and 
                   (currentTime - data.LastViolation) > SecurityConfig.Thresholds.RESET_TIME then
                    data.ViolationCount = 0
                    data.LastViolation = nil
                end
            end
        end
    end)
end

--[[
    Shutdown system
]]
function AntiCheatUG:Shutdown()
    for _, connection in pairs(self._connections) do
        connection:Disconnect()
    end
    
    for _, module in pairs(self._detectionModules) do
        if module.Shutdown then
            module:Shutdown()
        end
    end
    
    self._initialized = false
    print("[AntiCheat-UG] System shutdown")
end

return AntiCheatUG
