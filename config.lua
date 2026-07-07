
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

-- Keybind to open/close the tablet (rebindable in FiveM keybind settings)
Config.TabletKey         = "LBRACKET"
Config.TabletDescription = "Open/Close CAD Tablet"

-- Fade the tablet to 15% opacity when the cursor leaves it
Config.TabletDimmer = false

-- Block the NUI from auto-redirecting to /home after login
Config.PreventAutoRedirect = true

-- ========================================
-- CALL DETAILS POPUP SETTINGS
-- ========================================
-- On-screen popup showing details of calls you are attached to
Config.EnableCallPopup = true

-- Keybind to toggle the call details popup (default: G key)
Config.CallPopupKey         = "G"
Config.CallPopupDescription = "Toggle Call Details Popup"

-- How often (ms) to poll the CAD for call updates (only while popup is visible)
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
-- LOCATION TRACKING (optional - replaces cde_lm livemap)
-- ========================================
-- Pushes player GPS locations to the CAD livemap on a timer.
-- Leave disabled if cde_lm is running (duplicate updates).
Config.LocationTracking = {
    Enabled         = false,         -- Master switch (off by default)

    -- Duty status source: 'auto' (CDE_Duty > ESX > QBCore > CAD), 'cde_duty',
    -- 'esx', 'qbcore', or 'cad' (polls /api/fivem/unit-active, no duty script needed)
    DutySource      = 'auto',

    Interval        = 10000,         -- ms between location pushes
    MinDistance     = 50.0,          -- GTA units; skip update if moved less
    LEOOnly         = false,         -- only track LEO (police/sheriff) depts

    -- For DutySource = 'cad': ms between active-unit checks against the CAD
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
-- CDE Duty System Configuration

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
-- /ts POSTs to /api/fivem/traffic-stop, creating a Traffic Stop call and
-- attaching the calling unit (resolved by Discord ID)

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
        SaveInterval = 900, -- Seconds between time-data saves
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

-- Selected-civilian persistence: 'kvp' (built-in storage) or 'mysql' (requires oxmysql)
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

    -- Command to open the admin bank panel (bank employees only)
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

    -- Card renderer: 'template' (community-uploaded license template PNG),
    -- 'html' (classic card, uses CardStyle below), 'auto' (template, fallback to html)
    LicenseMode = 'auto',

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

    -- Card appearance for LicenseMode = 'html' (and 'auto' fallback)
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

    -- Enable /adminbank (CAD validates the player's bank-employee role)
    AdminEnabled = true
}

-- =============================================================================
-- VEHICLE REGISTRATION CONFIGURATION
-- =============================================================================

Config.VehicleRegistration = {
    -- Enable vehicle registration
    Enabled = true,
    
    -- Registration fee
    Fee = 500,
    
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

-- Capture an in-game mugshot on civilian select and upload it to the CAD
-- as a fallback photo (never overwrites a photo uploaded via the CAD)
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
Config.LbPhone         = true                 -- Attach caller's phone number to /911 calls: lb-phone when running, else the active civilian's registered number (anonymous calls excluded)
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
        Cooldown = 60,      -- seconds between gunshot reports from same player
        Radius   = 200.0,   -- NPCs within this many GTA units must be alive to "witness"
    },
    Fights = {
        Enabled  = true,
        Cooldown = 60,
    },
    -- Speed cameras: add { coords = vector3(x,y,z), speedLimit = 50, name = "..." } entries
    SpeedCamera = {
        Enabled    = false,
        Cooldown   = 60,
        Cameras    = {},
    },
}

-- ═══════════════════════════════════════════════════════════════════
-- ALPR CAMERAS (Automatic License Plate Readers)
-- Fixed camera posts placed in-game. Passing plates are matched against
-- the CAD flagged-plate list; a hit auto-opens a 911 call at the camera.
-- ═══════════════════════════════════════════════════════════════════
Config.ALPR = {
    Enabled = true,

    -- Chat command to manage cameras: /alprcam place|remove|list|clear
    Command = 'alprcam',
    -- Additional command aliases
    CommandAliases = { 'alpr' },

    -- Only on-duty LEOs may place/remove cameras (false = anyone)
    RequireOnDutyLEO = true,

    -- Detection geometry.
    CameraRadius      = 35.0,   -- how close (m) a vehicle must pass to be read
    ClientActiveRange = 200.0,  -- only clients within this of a camera scan it
    ScanInterval      = 1200,   -- ms between proximity sweeps on each client

    -- When true, only read plates inside a forward-facing cone of FOV total
    -- degrees; false = scan all directions within CameraRadius
    Directional = true,
    FOV         = 120.0,

    -- Placement preview: , and . cycle models, mouse wheel rotates, Enter
    -- confirms, Backspace cancels. false = place instantly at your feet
    PlacementUI = true,

    IgnoreEmergencyVehicles = true,  -- skip GTA emergency-class (18) vehicles
    -- Only read plates on player-driven vehicles (ignore AI traffic)
    OnlyPlayerVehicles      = true,

    -- Server-side dedup: one auto-911 per (camera, plate) within this window
    CallCooldownSeconds = 300,

    -- 'caution' = every flagged plate fires; 'alert' = only stolen/BOLO/warrant.
    -- Non-empty AlertFlags overrides: hit fires only on matching flag keywords,
    -- e.g. { 'STOLEN', 'BOLO', 'WARRANT' }
    MinAlertLevel = 'caution',
    AlertFlags    = {},

    -- Speed-limit choices offered by the /alpr panel picker
    SpeedOptions = { 25, 35, 45, 55, 65, 70, 80 },

    -- LEO alert on a camera hit: chat line, flashing map blip, sound
    Alerts = {
        Enabled      = true,
        LEOOnly      = true,   -- only on-duty LEOs get it (false = everyone)
        Chat         = true,
        Blip         = true,
        BlipDuration = 60,     -- seconds the flashing hit blip stays up
        Sound        = true,
    },

    -- Call type for speed-camera hits (/alpr speed <id> <mph> sets a limit)
    SpeedCallType = 'ALPR Speed',

    -- Scene photo on each hit, uploaded to the CAD (requires screenshot-basic;
    -- skipped when it isn't running)
    Screenshots = {
        Enabled        = true,
        RetentionHours = 24,   -- CAD deletes the image after this (1-72)

        -- true = capture from the camera's viewpoint (brief render switch),
        -- false = capture the reporting officer's own view
        CameraPOV = true,
        POVFov    = 55.0,

        -- Burn a CCTV-style overlay into the photo (REC dot, name, time, plate)
        Overlay = true,
    },

    -- Auto-911 call appearance
    CallType   = 'ALPR Hit',
    CallerName = 'ALPR Camera',
    -- Priority follows the plate's alertLevel: alert = high, caution = normal

    -- Minutes between flagged-plate cache refreshes (/alpr refresh forces one)
    CacheRefreshMinutes = 60,

    -- Map blip for each camera.
    Blip = {
        Enabled = true,
        Sprite  = 184,   -- camera icon
        Color   = 5,     -- yellow
        Scale   = 0.8,
        Label   = 'ALPR Camera',
    },

    -- Camera prop spawned at each placement; models must be valid base-game
    -- props. /alprcam place <number|model> picks one, Model is the default
    Prop = {
        Enabled = true,
        Model   = 'prop_cctv_cam_04a',
        -- Degrees added to the stored heading so the detection cone and blip
        -- match the lens (stock cctv props face backwards). 0 = lens faces forward
        LensOffset = 180.0,
        Models  = {
            'prop_cctv_cam_04a',
            'prop_cctv_cam_04b',
            'prop_cctv_cam_05a',
            'prop_cctv_cam_02a',
            'prop_cctv_cam_01b',
        },
    },

    -- Ground marker drawn when standing near a camera
    Marker = {
        Enabled      = false,
        DrawDistance = 40.0,
    },
}
    _G.Cad911Config = Config
end

-- ════════════════════════════════════════════════════════════════════
-- WRAITH (Wraith ARS 2X plate reader integration)
-- ════════════════════════════════════════════════════════════════════
do
    local Config = {}

    -- Master toggle; when false the wraith scripts register nothing
    Config.Enabled = true

    -- API URL + key + community ID come from convars (read at the top of each module's server.lua).

    Config.PlateReader = {
        LookupOnLock           = true,
        LookupOnScan           = true,
        LookupCooldown         = 10,
        OnlyPlayerPlates       = false,
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

    -- /reader: MDT-style in-car ALPR console. Display-only passive sweep of
    -- nearby vehicles against the CAD flag cache; never fires alerts or 911s.
    -- /cdelockfront and /cdelockrear lock the plate ahead/behind through the
    -- CAD pipeline, for wk builds that don't emit wk:onPlateLocked.
    Config.LockFallback = {
        Enabled = true,
        Range   = 35.0,  -- meters to search ahead/behind for the target
    }

    Config.Reader = {
        Enabled = true,
        Command = 'reader',
        ScanRadius    = 45.0,  -- read vehicles within this many meters
        ScanInterval  = 1500,  -- ms between sweeps while the console is open
        PlateCooldown = 45,    -- seconds before re-listing the same plate
    }

    Config.Debug = false

    _G.WraithConfig = Config
end

-- ════════════════════════════════════════════════════════════════════
-- ERS (Emergency Response Simulator bridge)
-- ════════════════════════════════════════════════════════════════════
do
    local Config = {}

    -- Master toggle; when false the ers scripts register nothing
    Config.Enabled = true

    -- CADEndpoint + APIKey come from convars (read at the top of each module's server.lua).

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

-- ════════════════════════════════════════════════════════════════════
-- PANIC BUTTON
-- ════════════════════════════════════════════════════════════════════
do
    local Config
Config = {}

Config.Debug = false                     -- Print HTTP request/response debug info

-- ═══════════════════════════════════════════════════════════════════
-- COMMAND & KEYBIND
-- ═══════════════════════════════════════════════════════════════════
Config.Command       = 'panic'      -- Chat command (/panic)
Config.KeybindKey    = 'Y'          -- Default key (players can rebind in FiveM settings)
Config.KeybindLabel  = 'Panic Button'

Config.CooldownSeconds     = 30     -- Cooldown between panic activations (per player)
Config.BlipDurationSeconds = 60     -- How long the red blip/route shows

-- ═══════════════════════════════════════════════════════════════════
-- DUTY RESTRICTIONS
-- ═══════════════════════════════════════════════════════════════════
-- Only on-duty LEOs may activate the panic button, and only on-duty LEOs
-- receive the panic blip/route/alert. Uses the bundle's own duty state
-- (the duty module's IsOnDutyLEO / IsPlayerOnDutyLEO / GetOnDutyLEOUnits).
Config.RequireOnDutyLEO   = true    -- Only on-duty LEOs can press panic
Config.BroadcastToLEOOnly = true    -- Only on-duty LEOs receive the alert

-- ═══════════════════════════════════════════════════════════════════
-- AUTO 911 CALL
-- ═══════════════════════════════════════════════════════════════════
Config.Auto911          = true              -- Automatically create a 911 call on panic
Config.Auto911CallType  = 'Officer Panic'   -- Call type shown in CAD
Config.Auto911Caller    = 'SYSTEM - PANIC'  -- Caller name shown in CAD

-- ═══════════════════════════════════════════════════════════════════
-- BLIP SETTINGS
-- ═══════════════════════════════════════════════════════════════════
Config.BlipSprite   = 526   -- Blip icon (526 = skull / danger)
Config.BlipColor    = 1     -- Red
Config.BlipScale    = 1.5   -- Blip size on map
Config.BlipFlashes  = true  -- Blip flashes on minimap
Config.ShowRoute    = true  -- Draw GPS route to panicking officer

-- ═══════════════════════════════════════════════════════════════════
-- CHAT MESSAGES
-- ═══════════════════════════════════════════════════════════════════
Config.ChatEnabled = true
Config.ChatColor   = { 255, 50, 50 }  -- Red text

Config.Messages = {
    activated = '^1[PANIC] ^0Officer ^3%s^0 has activated their panic button! Location: ^3%s',
    cooldown  = '^1[PANIC] ^0You must wait %d seconds before using panic again.',
    cleared   = '^1[PANIC] ^0Panic alert for ^3%s^0 has expired.',
    notOnDuty = '^1[PANIC] ^0Only on-duty LEOs can use the panic button.',
}

    _G.PanicConfig = Config
end
