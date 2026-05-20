
-- ════════════════════════════════════════════════════════════════════
-- TABLET
-- ════════════════════════════════════════════════════════════════════
do
    local Config
Config = {}


-- ========================================
-- TABLET SETTINGS
-- ========================================
-- The URL loaded in the tablet NUI iframe.
Config.TabletURL = "https://cdecad.com/login2"

-- Keybind to open/close the tablet (default: [ key)
-- Uses FiveM RegisterKeyMapping — players can rebind in Settings > Key Bindings > FiveM
Config.TabletKey         = "LBRACKET"
Config.TabletDescription = "Open/Close CAD Tablet"

-- Dim the tablet when the mouse moves outside of it
-- When true, the tablet fades to 15% opacity when the cursor leaves it
Config.TabletDimmer = false

-- Prevent the tablet from auto-redirecting to /home after login
-- When true, the NUI will block navigation to /home and stay on the current page
Config.PreventAutoRedirect = true

-- ========================================
-- CALL DETAILS POPUP SETTINGS
-- ========================================
-- On-screen popup showing details of calls you are attached to
Config.EnableCallPopup = true

-- Keybind to toggle the call details popup (default: G key)
Config.CallPopupKey         = "G"
Config.CallPopupDescription = "Toggle Call Details Popup"

-- How often (in ms) to poll the CAD for updated call data
-- Only polls while the popup is visible; stops when hidden
Config.CallPollInterval = 10000  -- 10 seconds

-- Auto-hide the popup after this many seconds (0 = never auto-hide)
Config.CallPopupAutoHide = 0

-- ========================================
-- FRAMEWORK SETTINGS
-- ========================================
Config.Framework = {
    Standalone = true,   -- Use CDE Duty System (no ESX/QBCore)
    ESX        = false,  -- ESX Framework
    QBCore     = false,  -- QB-Core Framework
}

-- Only allow the tablet to open while on duty (Standalone/CDE only)
Config.RequireOnDuty = false

-- ========================================
-- LOCATION TRACKING (optional — replaces cde_lm livemap)
-- ========================================
-- When enabled, this resource pushes the player's GPS location to the CAD
-- livemap on a timer, mirroring what cde_lm does. Useful for servers that
-- don't want to run a separate livemap script.
--
-- IMPORTANT: do NOT enable this if you also run cde_lm — you'll get duplicate
-- updates. The resource will print a warning if it detects cde_lm running.
Config.LocationTracking = {
    Enabled         = false,         -- Master switch (off by default)

    -- Where to read the player's duty status from:
    --   'auto'     — try CDE_Duty → ESX → QBCore → CAD (in that order)
    --   'cde_duty' — exports.CDE_Duty:GetDutyStatus()
    --   'esx'      — ESX PlayerData.job
    --   'qbcore'   — QBCore PlayerData.job
    --   'cad'      — poll CAD's /api/fivem/unit-active (no duty script needed;
    --                user goes "on duty" by clicking Begin Shift in CAD)
    DutySource      = 'auto',

    Interval        = 10000,         -- ms between location pushes
    MinDistance     = 50.0,          -- GTA units; skip update if moved less
    LEOOnly         = false,         -- only track LEO (police/sheriff) depts

    -- For DutySource = 'cad': how often to ask the CAD if the user is active.
    -- Cheap call (lean DB read), but no need to hammer it.
    CADActiveCheckInterval = 30000,

    SendOfflineOnDisconnect = true,  -- Push status='Offline' on resource stop
}

-- ========================================
-- OPTIMIZATION SETTINGS
-- ========================================
Config.EnableDebug = false  -- Enable verbose debug logging
    _G.TabletConfig = Config
end

-- ════════════════════════════════════════════════════════════════════
-- DUTY
-- ════════════════════════════════════════════════════════════════════
do
    local Config
-- config.lua
-- CDE Duty System Configuration
-- Version 3.2.0 - Added department support

Config = {}

-- ========================================
-- BASIC SETTINGS
-- ========================================

-- Main command to go on/off duty
Config.Command = "d"
Config.AlternativeCommand = "duty"

-- Show blips for on-duty players
Config.ShowDutyBlips = true

-- Enable 911 chat integration
Config.Enable911Chat = true

-- Enable paycheck system
Config.EnablePaychecks = true

-- ========================================
-- DEPARTMENT CONFIGURATIONS
-- ========================================

Config.Departments = {
    -- LAW ENFORCEMENT DEPARTMENTS
    ["sasp"] = {
        name = "San Andreas State Police",
        type = "leo",
        color = 46,      -- Gold/Yellow
        blipSprite = 60, -- Police badge
        paycheck = 1600,
        callSign = "SASP"
    },
    ["lcso"] = {
        name = "Los Santos County Sheriff's Office",
        type = "leo",
        color = 38,      -- Electric Blue
        blipSprite = 60, -- Police badge
        paycheck = 1500,
        callSign = "LCSO"
    },
    ["lspd"] = {
        name = "Los Santos Police Department",
        type = "leo",
        color = 26,      -- Dark Blue
        blipSprite = 60, -- Police badge
        paycheck = 1500,
        callSign = "LSPD"
    },
    ["bcso"] = {
        name = "Blaine County Sheriff's Office",
        type = "leo",
        color = 16,      -- Brown
        blipSprite = 60, -- Police badge
        paycheck = 1500,
        callSign = "BCSO"
    },
    
    -- FIRE/EMS DEPARTMENTS
    ["lsfd"] = {
        name = "Los Santos Fire Department",
        type = "fire",
        color = 1,       -- Red
        blipSprite = 436, -- Fire icon
        paycheck = 1400,
        callSign = "LSFD"
    },
    ["bcfd"] = {
        name = "Blaine County Fire Department",
        type = "fire",
        color = 2,       -- Green
        blipSprite = 436, -- Fire icon
        paycheck = 1400,
        callSign = "BCFD"
    }
}

-- Backwards compatibility aliases
Config.DutyTypes = {
    -- LEO departments
    ["leo"] = "lcso",  -- Default to LCSO if just "leo" is used
    ["police"] = "lspd", -- Default to LSPD if "police" is used
    ["fire"] = "lsfd",   -- Default to LSFD if "fire" is used
    ["ems"] = "bcfd",   -- Default to BCFD if "ems" is used
}

-- ========================================
-- WEAPON LOADOUTS (Department Specific)
-- ========================================

Config.WeaponLoadouts = {
    -- Law Enforcement Loadout (shared by all LEO departments)
    ["leo"] = {
        health = 200,
        armor = 100,
        weapons = {
            {
                weapon = "WEAPON_COMBATPISTOL", 
                ammo = 250,
                attachments = {
                    "COMPONENT_AT_PI_FLSH",        -- Flashlight
                }
            },
            {
                weapon = "WEAPON_CARBINERIFLE",
                ammo = 500,
                attachments = {
                    "COMPONENT_AT_AR_FLSH",        -- Flashlight
                    "COMPONENT_CARBINERIFLE_CLIP_02" -- Extended Clip
                }
            },
            {
                weapon = "WEAPON_PUMPSHOTGUN",
                ammo = 100,
                attachments = {
                    "COMPONENT_AT_AR_FLSH"         -- Flashlight
                }
            },
            {weapon = "WEAPON_NIGHTSTICK", ammo = 1},
            {weapon = "WEAPON_FLASHLIGHT", ammo = 1},
            {weapon = "WEAPON_BAT", ammo = 1},
            {weapon = "WEAPON_PETROLCAN", ammo = 100},
            {weapon = "WEAPON_STUNGUN", ammo = 100},
   		    {weapon = "WEAPON_FIREEXTINGUISHER", ammo = 2000},
            -- Non-lethal weapons
            {weapon = "weapon_lesslauncher", ammo = 50},  -- Less-lethal launcher
            {weapon = "weapon_beanbag", ammo = 100},       -- Beanbag shotgun
            {weapon = "weapon_pepperspray", ammo = 100} 
        }
    },
    -- SWAT Loadout (special tactical loadout)
    ["swat"] = {
        health = 200,
        armor = 200,
        weapons = {
            {
                weapon = "WEAPON_PISTOL_MK2",
                ammo = 250,
                attachments = {
                    "COMPONENT_AT_PI_FLSH_02",     -- Flashlight
                    "COMPONENT_PISTOL_MK2_CLIP_02", -- Extended Clip
                    "COMPONENT_AT_PI_SUPP_02",     -- Suppressor
                    "COMPONENT_AT_PI_COMP"         -- Compensator
                }
            },
            {
                weapon = "WEAPON_CARBINERIFLE_MK2",
                ammo = 500,
                attachments = {
                    "COMPONENT_AT_AR_FLSH",         -- Flashlight
                    "COMPONENT_CARBINERIFLE_MK2_CLIP_02", -- Extended Clip
                    "COMPONENT_AT_SCOPE_MEDIUM_MK2", -- Scope
                    "COMPONENT_AT_AR_AFGRIP_02",    -- Grip
                    "COMPONENT_AT_MUZZLE_01"        -- Muzzle
                }
            },
            {
                weapon = "WEAPON_PUMPSHOTGUN_MK2",
                ammo = 100,
                attachments = {
                    "COMPONENT_AT_AR_FLSH",         -- Flashlight
                    "COMPONENT_AT_SCOPE_SMALL_MK2", -- Scope
                    "COMPONENT_AT_MUZZLE_08"        -- Muzzle
                }
            },
            {
                weapon = "WEAPON_MARKSMANRIFLE",
                ammo = 200,
                attachments = {
                    "COMPONENT_AT_AR_FLSH",         -- Flashlight
                    "COMPONENT_MARKSMANRIFLE_CLIP_02", -- Extended Clip
                    "COMPONENT_AT_SCOPE_LARGE_FIXED_ZOOM", -- Scope
                    "COMPONENT_AT_AR_SUPP"          -- Suppressor
                }
            },
            {
                weapon = "WEAPON_SMG_MK2",
                ammo = 300,
                attachments = {
                    "COMPONENT_AT_AR_FLSH",         -- Flashlight
                    "COMPONENT_SMG_MK2_CLIP_02",    -- Extended Clip
                    "COMPONENT_AT_SCOPE_SMALL_SMG_MK2", -- Scope
                    "COMPONENT_AT_PI_SUPP"          -- Suppressor
                }
            },
            -- Tactical equipment
            {weapon = "WEAPON_SMOKEGRENADE", ammo = 10},
            {weapon = "WEAPON_BZGAS", ammo = 10},       -- Tear gas
            {weapon = "WEAPON_FLASHBANG", ammo = 5},    -- Flashbang (if available)
            {weapon = "WEAPON_NIGHTSTICK", ammo = 1},
            {weapon = "WEAPON_FLASHLIGHT", ammo = 1},
            {weapon = "WEAPON_PETROLCAN", ammo = 100},
            {weapon = "WEAPON_STUNGUN", ammo = 100},
            -- Non-lethal weapons
            {weapon = "weapon_lesslauncher", ammo = 100},
            {weapon = "weapon_beanbag", ammo = 200}
        }
    },
    -- Department specific loadouts (inherit from leo)
    ["sasp"] = "leo",
    ["lcso"] = "leo",
    ["lspd"] = "leo",
    ["bcso"] = "leo",
    
    -- Fire/EMS Loadouts
    ["lsfd"] = {
        health = 200,
        armor = 50,
        weapons = {
            {weapon = "WEAPON_FLASHLIGHT", ammo = 1},
            {weapon = "WEAPON_FIREEXTINGUISHER", ammo = 2000},
            {weapon = "WEAPON_HATCHET", ammo = 1},
            {weapon = "WEAPON_CROWBAR", ammo = 1},
            {weapon = "WEAPON_FLARE", ammo = 5}
        }
    },
    ["bcfd"] = {
        health = 200,
        armor = 50,
        weapons = {
            {weapon = "WEAPON_FLASHLIGHT", ammo = 1},
            {weapon = "WEAPON_STUNGUN", ammo = 100},
            {weapon = "WEAPON_FIREEXTINGUISHER", ammo = 2000},
            {weapon = "WEAPON_FLARE", ammo = 5}
        }
    }
}

-- ========================================
-- 911 CALL DISPLAY
-- ========================================

Config.CallDisplay = {
    ShowInChat = true,
    ShowNotification = true,
    PlaySound = true,
    SoundName = "CHALLENGE_UNLOCKED",
    SoundSet = "HUD_AWARDS",
    ChatColor = {255, 0, 0}
}

-- ========================================
-- 911 PREVENTION FOR LEOs
-- ========================================

Config.LEOCannotTrigger911 = true  -- Prevents on-duty LEOs from triggering NPC 911 calls

-- ========================================
-- GPS ROUTING
-- ========================================

Config.GPSRouting = {
    AutoRoute = true,           -- Auto-set GPS to 911 calls
    ShowDistance = true,        -- Show distance to call
    RouteDuration = 300,        -- Seconds before route auto-clears (0 = never)
    WaypointSprite = 162,       -- GPS waypoint sprite
    WaypointColor = 5,          -- GPS waypoint color
    ToggleCommand = "gps",      -- Command to toggle GPS
    ClearCommand = "cleargps",  -- Command to clear route
    PanicCommand = "route911"   -- Command to route to last 911
}

-- ========================================
-- PAYCHECK SYSTEM
-- ========================================

Config.Paychecks = {
    Enabled = true,
    Interval = 35,        -- Minutes between paychecks
    OnDutyPay = 1200,      -- Default pay for on-duty
    CivilianPay = 500      -- Pay for civilians
}

-- ========================================
-- MESSAGES
-- ========================================

Config.Messages = {
    WentOnDuty = "~g~You are now on duty!",
    WentOffDuty = "~r~You are now off duty!",
    AlreadyOnDuty = "~y~You are already on duty!",
    AlreadyOffDuty = "~y~You are already off duty!",
    ReceivedLoadout = "~g~Duty loadout received!",
    WeaponsRemoved = "~r~Duty weapons removed!",
    PaycheckOnDuty = "~g~Paycheck received: $%d (On-Duty Bonus)",
    PaycheckCivilian = "~g~Paycheck received: $%d",
    GPSEnabled = "~g~GPS routing enabled!",
    GPSDisabled = "~r~GPS routing disabled!",
    GPSCleared = "~y~GPS route cleared!",
    CallLocationSet = "~b~911 Call location set! Distance: %dm"
}

-- ========================================
-- CAD INTEGRATION (Traffic Stop /ts)
-- ========================================
-- Used by the /ts command to POST to /api/fivem/traffic-stop on the CAD
-- backend.  This creates a Traffic Stop call and auto-attaches the calling
-- unit (resolved by Discord ID) to it.

Config.CAD = {
    Debug = false,
}

Config.TrafficStop = {
    Command            = 'ts',
    AltCommand         = 'trafficstop',
    CooldownSeconds    = 5,    -- Per-player cooldown
    RequireLEO         = true, -- Only on-duty LEO can run /ts
    PlateMaxAgeSeconds = 120,  -- Discard wraith locks older than this
}

-- ========================================
-- ADVANCED SETTINGS
-- ========================================

Config.Advanced = {
    RemoveWeaponsOffDuty = true,
    SaveCivilianWeapons = true,
    PersistDutyStatus = false,
    DebugMode = false
}

-- ========================================
-- DISCORD WEBHOOKS
-- ========================================

Config.Discord = {
    Enabled = true, -- Set to true if you want Discord logs


    -- Time tracking settings
    TimeTracking = {
        Enabled = true,
        SaveInterval = 900, -- Save time data every 10 minutes (in seconds)
        ShowTimeInWebhook = true,
        MinimumDutyTime = 300 -- Minimum seconds on duty before tracking (prevents spam)
    },
    
    -- Webhook appearance
    BotName = "CDE Duty System",
    --BotAvatar = "https://i.imgur.com/YOUR_IMAGE.png", -- Replace with your image
    
    -- Embed colors for different actions
    Colors = {
        DutyOn = 65280,    -- Green
        DutyOff = 16711680, -- Red
        SWAT = 16776960,    -- Gold/Yellow for SWAT loadout
        
        -- Department specific colors (matches blip colors)
        ["sasp"] = 16776960,  -- Gold
        ["lcso"] = 42495,    -- Electric Blue
        ["lspd"] = 29372,     -- Dark Blue  
        ["bcso"] = 9849600,  -- Brown
        ["lsfd"] = 16711680,  -- Red
        ["bcfd"] = 65280     -- Green
    }
}

-- ========================================
-- FRAMEWORK INTEGRATION
-- ========================================

Config.Framework = {
    ESX = false,    -- Set to true if using ESX
    QBCore = false  -- Set to true if using QBCore
}

-- ========================================
-- INITIALIZATION
-- ========================================

print("^2[CDE-DUTY] Config.lua loaded successfully (v3.2.0)^0")
print("^2[CDE-DUTY] Command: /" .. Config.Command .. "^0")
print("^2[CDE-DUTY] Alt Command: /" .. Config.AlternativeCommand .. "^0")

print("^2[CDE-DUTY] Departments configured:^0")
for k, v in pairs(Config.Departments) do
    print("  - " .. k .. ": " .. v.name .. " (" .. v.type .. ")")
end

print("^2[CDE-DUTY] Blips enabled: " .. tostring(Config.ShowDutyBlips) .. "^0")
print("^2[CDE-DUTY] 911 enabled: " .. tostring(Config.Enable911Chat) .. "^0")
    _G.DutyConfig = Config
end

-- ════════════════════════════════════════════════════════════════════
-- CIV
-- ════════════════════════════════════════════════════════════════════
do
    local Config
--[[
    CDECAD Civilian Manager Configuration
]]

Config = {}


-- =============================================================================
-- PERSISTENCE CONFIGURATION
-- =============================================================================

-- How to persist selected civilian across sessions
-- Options: 'kvp', 'mysql'
-- 'kvp' - Uses FiveM's built-in Key-Value storage (no database needed)
-- 'mysql' - Uses MySQL database (requires oxmysql)
Config.Persistence = 'kvp'

-- MySQL table name (only used if Persistence = 'mysql')
Config.MySQLTable = 'cdecad_selected_civs'

-- =============================================================================
-- COMMANDS CONFIGURATION
-- =============================================================================

Config.Commands = {
    -- Command to open civilian selector
    SelectCiv = 'setciv',
    
    -- Command to show current civilian info
    ShowInfo = 'myciv',
    
    -- Command to open bank
    Bank = 'bank',

    -- Command to open the admin bank panel (bank employees only).
    -- Tip: use 'adminbank' or set to a chat-friendly name like 'bnkadmin'.
    AdminBank = 'adminbank',
    
    -- Command to register current vehicle
    RegisterVehicle = 'regveh',
    
    -- Command to show ID to nearby players
    ShowID = 'showid',
    
    -- Command to clear selected civilian
    ClearCiv = 'clearciv'
}

-- =============================================================================
-- ID CARD CONFIGURATION
-- =============================================================================

Config.IDCard = {
    -- Show HTML ID card UI
    ShowHTML = true,
    
    -- Also output to chat/skybox
    ShowInChat = true,
    
    -- Use ox_lib notify for ID display (alternative to HTML)
    UseOxNotify = false,
    
    -- ID card display duration (ms)
    DisplayDuration = 10000,
    
    -- Range for nearby players to see ID (in meters)
    ShowRange = 3.0,
    
    -- Enable ox_target integration (look at player -> Show ID / Request ID)
    UseOxTarget = true,
    
    -- ID Card appearance (fallback if community settings not available)
    CardStyle = {
        -- State name on the ID
        StateName = 'San Andreas',
        
        -- Card title
        CardTitle = "DRIVER'S LICENSE",
        
        -- Background color (hex)
        BackgroundColor = '#1a365d',
        
        -- Text color (hex)
        TextColor = '#ffffff',
        
        -- Accent color (hex)
        AccentColor = '#3182ce'
    }
}

-- =============================================================================
-- BANK CONFIGURATION
-- =============================================================================

Config.Bank = {
    -- Enable bank functionality
    Enabled = true,

    -- Starting balance for new civilians (if not set in CAD)
    DefaultBalance = 5000,

    -- Allow transfers between players
    AllowTransfers = true,

    -- Minimum transfer amount
    MinTransfer = 1,

    -- Maximum transfer amount (0 = unlimited)
    MaxTransfer = 0,

    -- Transaction fee percentage (0 = no fee)
    TransferFee = 0,

    -- Admin/banker access (enables /adminbank in-game)
    -- The CAD validates that the calling player has a bank-employee role
    -- (configured per community). Without it, the command is rejected.
    AdminEnabled = true
}

-- =============================================================================
-- VEHICLE REGISTRATION CONFIGURATION
-- =============================================================================

Config.VehicleRegistration = {
    -- Enable vehicle registration
    Enabled = true,
    
    
    -- Require player to be in vehicle to register
    RequireInVehicle = true,
    
    -- Auto-detect vehicle info from game
    AutoDetect = true,
    
    -- Allow registering stolen vehicles
    AllowStolen = false
}

-- =============================================================================
-- NOTIFICATIONS
-- =============================================================================

Config.Notifications = {
    -- Use ox_lib notifications
    UseOxLib = true,
    
    -- Notification duration (ms)
    Duration = 5000,
    
    -- Notification position
    Position = 'top-right'
}

-- =============================================================================
-- MUGSHOT CONFIGURATION
-- =============================================================================

-- Automatically capture an in-game FiveM mugshot when a civilian is selected
-- and upload it to the CAD as a fallback photo.
-- Set to false (recommended) when your players upload custom photos via the
-- CAD portal — the CAD photo is always the source of truth and will never
-- be overwritten by an in-game capture regardless of this setting.
Config.CaptureFiveMMugshot = false

-- =============================================================================
-- DEBUG
-- =============================================================================

-- Set to true to see debug messages in console (F8)
Config.Debug = true
    _G.CivConfig = Config
end

-- ════════════════════════════════════════════════════════════════════
-- 911
-- ════════════════════════════════════════════════════════════════════
do
    local Config
Config = {}

Config.Debug = false                     -- Print HTTP request/response debug info

-- ═══════════════════════════════════════════════════════════════════
-- COMMANDS
-- ═══════════════════════════════════════════════════════════════════
Config.Command911      = '911'       -- /911 <message>
Config.CommandAnon     = 'a911'      -- /a911 <message>  (anonymous)

-- ═══════════════════════════════════════════════════════════════════
-- CALL SETTINGS
-- ═══════════════════════════════════════════════════════════════════
Config.DefaultCallType = '911 Call'           -- Call type shown in CAD
Config.AnonCallerName  = 'Anonymous'          -- Caller name for /a911
Config.DefaultPriority = 'normal'             -- low | normal | medium | high | critical
Config.CooldownSeconds = 10                   -- Cooldown between 911 calls per player

-- ═══════════════════════════════════════════════════════════════════
-- CHAT MESSAGES
-- ═══════════════════════════════════════════════════════════════════
Config.ChatEnabled = true

Config.Messages = {
    sent     = '^2[911] ^0Your call has been dispatched. Help is on the way.',
    sentAnon = '^2[911] ^0Anonymous report submitted.',
    cooldown = '^1[911] ^0Please wait %d seconds before calling again.',
    noMsg    = '^1[911] ^0Usage: /911 <description of your emergency>',
}

-- ═══════════════════════════════════════════════════════════════════
-- NPC WITNESS REPORTS (automated 911 calls from in-game events)
-- ═══════════════════════════════════════════════════════════════════
Config.NPCReports = {
    Enabled = true,
    Gunshots = {
        Enabled  = true,
        Cooldown = 60,
        Radius   = 200.0,
    },
    Fights = {
        Enabled  = true,
        Cooldown = 60,
    },
    SpeedCamera = {
        Enabled  = false,
        Cooldown = 60,
        Cameras  = {},
    },
}
    _G.Cad911Config = Config
end

-- ════════════════════════════════════════════════════════════════════
-- WRAITH (Wraith ARS 2X plate reader integration)
-- ════════════════════════════════════════════════════════════════════
do
    local Config = {}

    Config.Enabled = true

    Config.PlateReader = {
        LookupOnLock           = true,
        LookupOnScan           = true,
        LookupCooldown         = 10,
        OnlyPlayerPlates       = true ,
        IgnoreEmergencyVehicles = true,
        ShowCleanScans         = true,
        EmergencyVehicleModels = {
            'police','police2','police3','police4','policeb','policet',
            'policeold1','policeold2',
            'sheriff','sheriff2','fbi','fbi2','riot','riot2','pranger',
            'ambulance','firetruk','lguard',
        },
        EmergencyPlatePatterns = {},
    }

    Config.Display = {
        DisplayDuration = 15,
        ShowPopup       = true,
        ShowChat        = true,
        ChatCleanFormat    = '~g~[PLATE READER]~w~ %s | %s %s %s | Owner: %s | ~g~CLEAN',
        ChatFlagFormat     = '~r~[PLATE READER]~w~ %s | %s %s %s | Owner: %s | ~r~FLAGS: %s',
        ChatNotFoundFormat = '~y~[PLATE READER]~w~ %s | ~y~NOT IN SYSTEM',
    }

    Config.Permissions = {
        RestrictToJobs = true,
        AllowedJobs = { 'police','sheriff','statepolice','trooper','highway','ranger','marshal' },
        UseQBCore = false,
        UseESX    = false,
    }

    Config.Notifications = {
        UseOxLib = false,
        Position = 'top-right',
        Duration = 8000,
        Detailed = true,
    }

    Config.Debug = false

    _G.WraithConfig = Config
end

-- ════════════════════════════════════════════════════════════════════
-- ERS (Emergency Response Simulator bridge)
-- ════════════════════════════════════════════════════════════════════
do
    local Config = {}

    Config.Enabled = true

    Config.EnableDebug             = false
    Config.CreateCallOnAccept      = true
    Config.CloseCallOnEnd          = true
    Config.AttachUnitOnAccept      = true
    Config.UpdateOnArrival         = true
    Config.CreateCivilians         = true
    Config.CreateVehicles          = true
    Config.EnableDispatchCallouts  = true
    Config.DispatchPollInterval    = 30
    Config.CreateOnTrafficStop     = true
    Config.ToggleDutyOnShift       = true

    _G.ErsConfig = Config
end
