-- DetectionModules.server.luau
-- All detection logic modules
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SecurityConfig = require(script.Parent.SecurityConfig)

local DetectionModules = {}

-- Base detector class
local BaseDetector = {}
BaseDetector.__index = BaseDetector

function BaseDetector.new()
    local self = setmetatable({}, BaseDetector)
    self._players = {}
    self._connections = {}
    self.OnViolation = Instance.new("BindableEvent")
    return self
end

function BaseDetector:InitializePlayer(player)
    self._players[player] = {
        Enabled = true,
        Data = {}
    }
end

function BaseDetector:CleanupPlayer(player)
    self._players[player] = nil
end

--[[
    SPEED HACK DETECTOR
]]
DetectionModules.SpeedHackDetector = setmetatable({}, BaseDetector)
DetectionModules.SpeedHackDetector.__index = DetectionModules.SpeedHackDetector

function DetectionModules.SpeedHackDetector.new()
    local self = setmetatable(BaseDetector.new(), DetectionModules.SpeedHackDetector)
    self:_init()
    return self
end

function DetectionModules.SpeedHackDetector:_init()
    -- Speed check loop
    task.spawn(function()
        while true do
            task.wait(SecurityConfig.Thresholds.SPEED_CHECK_INTERVAL)
            
            for player, data in pairs(self._players) do
                if data.Enabled and player:IsDescendantOf(game) then
                    self:_checkPlayer(player)
                end
            end
        end
    end)
end

function DetectionModules.SpeedHackDetector:_checkPlayer(player)
    local character = player.Character
    if not character then return end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not rootPart then return end
    
    -- Get player data
    local data = self._players[player]
    
    -- Check walkspeed
    if humanoid.WalkSpeed > SecurityConfig.Thresholds.MAX_WALK_SPEED then
        self.OnViolation:Fire(player, {
            Type = "SPEED_HACK",
            Reason = "WalkSpeed exceeded limit",
            Value = humanoid.WalkSpeed,
            Max = SecurityConfig.Thresholds.MAX_WALK_SPEED,
            Code = SecurityConfig.BanSystem.VIOLATION_CODES.SPEED_HACK
        })
    end
    
    -- Velocity-based speed check
    if data.LastPosition then
        local distance = (rootPart.Position - data.LastPosition).Magnitude
        local timePassed = SecurityConfig.Thresholds.SPEED_CHECK_INTERVAL
        local speed = distance / timePassed
        
        if speed > SecurityConfig.Thresholds.SPEED_HACK_THRESHOLD then
            self.OnViolation:Fire(player, {
                Type = "SPEED_HACK",
                Reason = "Velocity exceeds threshold",
                Speed = speed,
                Threshold = SecurityConfig.Thresholds.SPEED_HACK_THRESHOLD,
                Code = SecurityConfig.BanSystem.VIOLATION_CODES.SPEED_HACK
            })
        end
    end
    
    -- Update last position
    data.LastPosition = rootPart.Position
end

--[[
    TELEPORT DETECTOR
]]
DetectionModules.TeleportDetector = setmetatable({}, BaseDetector)
DetectionModules.TeleportDetector.__index = DetectionModules.TeleportDetector

function DetectionModules.TeleportDetector.new()
    local self = setmetatable(BaseDetector.new(), DetectionModules.TeleportDetector)
    self:_init()
    return self
end

function DetectionModules.TeleportDetector:_init()
    task.spawn(function()
        while true do
            task.wait(SecurityConfig.Thresholds.TELEPORT_CHECK_INTERVAL)
            
            for player, data in pairs(self._players) do
                if data.Enabled and player:IsDescendantOf(game) then
                    self:_checkPlayer(player)
                end
            end
        end
    end)
end

function DetectionModules.TeleportDetector:_checkPlayer(player)
    local character = player.Character
    if not character then return end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end
    
    local data = self._players[player]
    local currentPosition = rootPart.Position
    
    if data.LastPosition then
        local distance = (currentPosition - data.LastPosition).Magnitude
        
        -- Check for impossible travel distance
        if distance > SecurityConfig.Thresholds.MAX_ALLOWED_TRAVEL then
            -- Verify with raycast to ensure it's not legitimate teleportation
            local direction = (currentPosition - data.LastPosition).Unit
            local raycastResult = Workspace:Raycast(
                data.LastPosition + Vector3.new(0, 2, 0),
                direction * distance,
                {character}
            )
            
            -- If ray hits something, it's likely teleport hack
            if raycastResult then
                self.OnViolation:Fire(player, {
                    Type = "TELEPORT",
                    Reason = "Impossible travel distance",
                    Distance = distance,
                    MaxAllowed = SecurityConfig.Thresholds.MAX_ALLOWED_TRAVEL,
                    Code = SecurityConfig.BanSystem.VIOLATION_CODES.TELEPORT
                })
            end
        end
    end
    
    data.LastPosition = currentPosition
end

--[[
    NO-CLIP DETECTOR
]]
DetectionModules.NoClipDetector = setmetatable({}, BaseDetector)
DetectionModules.NoClipDetector.__index = DetectionModules.NoClipDetector

function DetectionModules.NoClipDetector.new()
    local self = setmetatable(BaseDetector.new(), DetectionModules.NoClipDetector)
    self:_init()
    return self
end

function DetectionModules.NoClipDetector:_init()
    task.spawn(function()
        while true do
            task.wait(SecurityConfig.Thresholds.NO_CLIP_CHECK_INTERVAL)
            
            for player, data in pairs(self._players) do
                if data.Enabled and player:IsDescendantOf(game) then
                    self:_checkPlayer(player)
                end
            end
        end
    end)
end

function DetectionModules.NoClipDetector:_checkPlayer(player)
    local character = player.Character
    if not character then return end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not rootPart then return end
    
    -- Skip if player is dead
    if humanoid.Health <= 0 then return end
    
    -- Perform multiple raycasts around player
    local rayDirections = {
        Vector3.new(1, 0, 0),
        Vector3.new(-1, 0, 0),
        Vector3.new(0, 0, 1),
        Vector3.new(0, 0, -1),
        Vector3.new(0, -1, 0) -- Downward ray for ground check
    }
    
    local hitCount = 0
    local totalRays = #rayDirections
    
    for _, direction in ipairs(rayDirections) do
        local raycastResult = Workspace:Raycast(
            rootPart.Position,
            direction * SecurityConfig.Thresholds.NO_CLIP_RAY_LENGTH,
            {character}
        )
        
        if raycastResult then
            hitCount += 1
        end
    end
    
    -- If no rays hit anything, player might be nocliping
    if hitCount == 0 then
        self.OnViolation:Fire(player, {
            Type = "NO_CLIP",
            Reason = "No collisions detected around player",
            Position = rootPart.Position,
            Code = SecurityConfig.BanSystem.VIOLATION_CODES.NO_CLIP
        })
    end
end

--[[
    REMOTE EVENT SECURITY
]]
DetectionModules.RemoteSecurity = setmetatable({}, BaseDetector)
DetectionModules.RemoteSecurity.__index = DetectionModules.RemoteSecurity

function DetectionModules.RemoteSecurity.new()
    local self = setmetatable(BaseDetector.new(), DetectionModules.RemoteSecurity)
    self._remoteCallCounts = {}
    self._lastRemoteCall = {}
    self:_init()
    return self
end

function DetectionModules.RemoteSecurity:_init()
    -- Reset counters periodically
    task.spawn(function()
        while true do
            task.wait(60) -- Reset every minute
            self._remoteCallCounts = {}
        end
    end)
end

function DetectionModules.RemoteSecurity:CheckRemoteCall(player, remoteName)
    local userId = player.UserId
    local currentTime = os.time()
    
    -- Initialize counters
    if not self._remoteCallCounts[userId] then
        self._remoteCallCounts[userId] = 0
        self._lastRemoteCall[userId] = currentTime
    end
    
    -- Check cooldown
    local timeSinceLastCall = currentTime - self._lastRemoteCall[userId]
    if timeSinceLastCall < SecurityConfig.Thresholds.REMOTE_COOLDOWN then
        self.OnViolation:Fire(player, {
            Type = "REMOTE_EXPLOIT",
            Reason = "Remote call cooldown violation",
            RemoteName = remoteName,
            TimeSinceLast = timeSinceLastCall,
            MinCooldown = SecurityConfig.Thresholds.REMOTE_COOLDOWN,
            Code = SecurityConfig.BanSystem.VIOLATION_CODES.REMOTE_EXPLOIT
        })
        return false
    end
    
    -- Increment counter
    self._remoteCallCounts[userId] += 1
    self._lastRemoteCall[userId] = currentTime
    
    -- Check rate limit
    if self._remoteCallCounts[userId] > SecurityConfig.Thresholds.MAX_REMOTE_CALLS_PER_MINUTE then
        self.OnViolation:Fire(player, {
            Type = "REMOTE_EXPLOIT",
            Reason = "Remote call rate limit exceeded",
            RemoteName = remoteName,
            CallCount = self._remoteCallCounts[userId],
            MaxCalls = SecurityConfig.Thresholds.MAX_REMOTE_CALLS_PER_MINUTE,
            Code = SecurityConfig.BanSystem.VIOLATION_CODES.REMOTE_EXPLOIT
        })
        return false
    end
    
    return true
end

--[[
    HUMANOID VALIDATOR
]]
DetectionModules.HumanoidValidator = setmetatable({}, BaseDetector)
DetectionModules.HumanoidValidator.__index = DetectionModules.HumanoidValidator

function DetectionModules.HumanoidValidator.new()
    local self = setmetatable(BaseDetector.new(), DetectionModules.HumanoidValidator)
    self:_init()
    return self
end

function DetectionModules.HumanoidValidator:_init()
    -- Periodic humanoid validation
    task.spawn(function()
        while true do
            task.wait(1) -- Check every second
            
            for player, data in pairs(self._players) do
                if data.Enabled and player:IsDescendantOf(game) then
                    self:_validateHumanoid(player)
                end
            end
        end
    end)
end

function DetectionModules.HumanoidValidator:_validateHumanoid(player)
    local character = player.Character
    if not character then return end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    -- Check jump power
    if humanoid.JumpPower > SecurityConfig.Thresholds.MAX_JUMP_POWER then
        self.OnViolation:Fire(player, {
            Type = "HUMANOID_TAMPER",
            Reason = "JumpPower exceeds limit",
            Value = humanoid.JumpPower,
            Max = SecurityConfig.Thresholds.MAX_JUMP_POWER,
            Code = SecurityConfig.BanSystem.VIOLATION_CODES.HUMANOID_TAMPER
        })
    end
    
    -- Check hip height
    if humanoid.HipHeight > SecurityConfig.Thresholds.MAX_HIP_HEIGHT then
        self.OnViolation:Fire(player, {
            Type = "HUMANOID_TAMPER",
            Reason = "HipHeight exceeds limit",
            Value = humanoid.HipHeight,
            Max = SecurityConfig.Thresholds.MAX_HIP_HEIGHT,
            Code = SecurityConfig.BanSystem.VIOLATION_CODES.HUMANOID_TAMPER
        })
    end
    
    -- Check for invalid humanoid states
    if humanoid:GetState() == Enum.HumanoidStateType.Flying then
        -- Verify if flying is allowed (e.g., game has flight mechanics)
        local canFly = false -- Set based on game mechanics
        
        if not canFly then
            self.OnViolation:Fire(player, {
                Type = "HUMANOID_TAMPER",
                Reason = "Illegal flying state",
                State = "Flying",
                Code = SecurityConfig.BanSystem.VIOLATION_CODES.HUMANOID_TAMPER
            })
        end
    end
end

return DetectionModules
