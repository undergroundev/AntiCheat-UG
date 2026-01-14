-- SecurityConfig.server.luau
-- Configuration for AntiCheat-UG Security System
local SecurityConfig = {}

-- Detection Thresholds (Tuned for production)
SecurityConfig.Thresholds = {
    MAX_WALK_SPEED = 32, -- Max allowed walkspeed (including speed boosts)
    MAX_JUMP_POWER = 100, -- Max allowed jumppower
    MAX_HIP_HEIGHT = 5, -- Max allowed hipheight
    
    -- Teleportation Detection
    MAX_ALLOWED_TRAVEL = 100, -- Studs per check interval (0.5s)
    TELEPORT_CHECK_INTERVAL = 0.5, -- Seconds
    
    -- Speed Hack Detection
    SPEED_HACK_THRESHOLD = 50, -- Studs/second
    SPEED_CHECK_INTERVAL = 0.3, -- Seconds
    
    -- Noclip Detection
    NO_CLIP_CHECK_INTERVAL = 0.8, -- Seconds
    NO_CLIP_RAY_LENGTH = 5, -- Studs
    
    -- Rate Limiting
    MAX_REMOTE_CALLS_PER_MINUTE = 120,
    REMOTE_COOLDOWN = 0.1, -- Minimum seconds between remote calls
    
    -- Humanoid State Validation
    MAX_ANOMALY_COUNT = 5, -- Max violations before action
    RESET_TIME = 60, -- Seconds for violation count reset
}

-- Ban System Configuration
SecurityConfig.BanSystem = {
    DATASTORE_NAME = "AntiCheatUG_Bans",
    KEY_PREFIX = "BAN_",
    
    -- Ban Messages
    BAN_MESSAGE = "Whoooppss! Exploit Dettected - PERMANENT BAN APPLIED\n\n" ..
                  "Violation: {VIOLATION}\n" ..
                  "Code: ACUG-{CODE}\n" ..
                  "Appeal: discord.gg/security",
    
    -- Violation Codes
    VIOLATION_CODES = {
        SPEED_HACK = "SH101",
        TELEPORT = "TP102",
        NO_CLIP = "NC103",
        REMOTE_EXPLOIT = "RE104",
        HUMANOID_TAMPER = "HT105",
        ANTI_TAMPER = "AT106"
    }
}

-- Whitelists (for admin tools, etc.)
SecurityConfig.Whitelists = {
    AdminUserIds = { -- Insert actual admin IDs
        123456789, -- Example
    },
    AllowedSpeedBoostGames = { -- Game IDs where speed boosts are allowed
        987654321,
    }
}

-- Logging Configuration
SecurityConfig.Logging = {
    ENABLED = true,
    VERBOSE = false, -- Set to false in production
    MAX_LOGS_PER_PLAYER = 50
}

return SecurityConfig
