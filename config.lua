
do
    local Config
Config = {}


Config.TabletURL = "https://cdecad.com/login2"

Config.TabletKey         = "LBRACKET"
Config.TabletDescription = "Open/Close CAD Tablet"

Config.TabletDimmer = false

Config.TabletUnloadAfter = 300

Config.PreventAutoRedirect = true

Config.EnableCallPopup = true

Config.CallPopupKey         = "G"
Config.CallPopupDescription = "Toggle Call Details Popup"

Config.CallPollInterval = 10000

Config.CallPopupAutoHide = 0

Config.Framework = {
    Standalone = true,
}

Config.RequireOnDuty = false

Config.LocationTracking = {
    Enabled         = false,

    DutySource      = 'auto',

    Interval        = 10000,
    MinDistance     = 50.0,
    LEOOnly         = false,

    CADActiveCheckInterval = 30000,

    SendOfflineOnDisconnect = true,
}

Config.EnableDebug = false
    _G.TabletConfig = Config
end

do
    local Config

Config = {}


Config.Command = "d"
Config.AlternativeCommand = "duty"

Config.ShowDutyBlips = true

Config.Enable911Chat = true

Config.EnablePaychecks = true


Config.Departments = {
    ["police"] = {
        name = "Police Department",
        type = "leo",
        color = 38,
        blipSprite = 60,
        paycheck = 1500,
        callSign = "POLICE"
    },
    ["fire"] = {
        name = "Fire / EMS Department",
        type = "fire",
        color = 1,
        blipSprite = 436,
        paycheck = 1400,
        callSign = "FIRE"
    }
}

Config.DutyTypes = {
    ["leo"]    = "police",
    ["police"] = "police",
    ["fire"]   = "fire",
    ["ems"]    = "fire",
}


Config.WeaponLoadouts = {
    ["leo"] = {
        health = 200,
        armor = 100,
        weapons = {
            {
                weapon = "WEAPON_COMBATPISTOL",
                ammo = 250,
                attachments = {
                    "COMPONENT_AT_PI_FLSH",
                }
            },
            {
                weapon = "WEAPON_CARBINERIFLE",
                ammo = 500,
                attachments = {
                    "COMPONENT_AT_AR_FLSH",
                    "COMPONENT_CARBINERIFLE_CLIP_02"
                }
            },
            {
                weapon = "WEAPON_PUMPSHOTGUN",
                ammo = 100,
                attachments = {
                    "COMPONENT_AT_AR_FLSH"
                }
            },
            {weapon = "WEAPON_NIGHTSTICK", ammo = 1},
            {weapon = "WEAPON_FLASHLIGHT", ammo = 1},
            {weapon = "WEAPON_BAT", ammo = 1},
            {weapon = "WEAPON_PETROLCAN", ammo = 100},
            {weapon = "WEAPON_STUNGUN", ammo = 100},
   		    {weapon = "WEAPON_FIREEXTINGUISHER", ammo = 2000},
            {weapon = "weapon_lesslauncher", ammo = 50},
            {weapon = "weapon_beanbag", ammo = 100},
            {weapon = "weapon_pepperspray", ammo = 100}
        }
    },
    ["swat"] = {
        health = 200,
        armor = 200,
        weapons = {
            {
                weapon = "WEAPON_PISTOL_MK2",
                ammo = 250,
                attachments = {
                    "COMPONENT_AT_PI_FLSH_02",
                    "COMPONENT_PISTOL_MK2_CLIP_02",
                    "COMPONENT_AT_PI_SUPP_02",
                    "COMPONENT_AT_PI_COMP"
                }
            },
            {
                weapon = "WEAPON_CARBINERIFLE_MK2",
                ammo = 500,
                attachments = {
                    "COMPONENT_AT_AR_FLSH",
                    "COMPONENT_CARBINERIFLE_MK2_CLIP_02",
                    "COMPONENT_AT_SCOPE_MEDIUM_MK2",
                    "COMPONENT_AT_AR_AFGRIP_02",
                    "COMPONENT_AT_MUZZLE_01"
                }
            },
            {
                weapon = "WEAPON_PUMPSHOTGUN_MK2",
                ammo = 100,
                attachments = {
                    "COMPONENT_AT_AR_FLSH",
                    "COMPONENT_AT_SCOPE_SMALL_MK2",
                    "COMPONENT_AT_MUZZLE_08"
                }
            },
            {
                weapon = "WEAPON_MARKSMANRIFLE",
                ammo = 200,
                attachments = {
                    "COMPONENT_AT_AR_FLSH",
                    "COMPONENT_MARKSMANRIFLE_CLIP_02",
                    "COMPONENT_AT_SCOPE_LARGE_FIXED_ZOOM",
                    "COMPONENT_AT_AR_SUPP"
                }
            },
            {
                weapon = "WEAPON_SMG_MK2",
                ammo = 300,
                attachments = {
                    "COMPONENT_AT_AR_FLSH",
                    "COMPONENT_SMG_MK2_CLIP_02",
                    "COMPONENT_AT_SCOPE_SMALL_SMG_MK2",
                    "COMPONENT_AT_PI_SUPP"
                }
            },
            {weapon = "WEAPON_SMOKEGRENADE", ammo = 10},
            {weapon = "WEAPON_BZGAS", ammo = 10},
            {weapon = "WEAPON_FLASHBANG", ammo = 5},
            {weapon = "WEAPON_NIGHTSTICK", ammo = 1},
            {weapon = "WEAPON_FLASHLIGHT", ammo = 1},
            {weapon = "WEAPON_PETROLCAN", ammo = 100},
            {weapon = "WEAPON_STUNGUN", ammo = 100},
            {weapon = "weapon_lesslauncher", ammo = 100},
            {weapon = "weapon_beanbag", ammo = 200}
        }
    },
    ["police"] = "leo",
    ["fire"] = {
        health = 200,
        armor = 50,
        weapons = {
            {weapon = "WEAPON_FLASHLIGHT", ammo = 1},
            {weapon = "WEAPON_FIREEXTINGUISHER", ammo = 2000},
            {weapon = "WEAPON_HATCHET", ammo = 1},
            {weapon = "WEAPON_CROWBAR", ammo = 1},
            {weapon = "WEAPON_FLARE", ammo = 5}
        }
    }
}


Config.CallDisplay = {
    ShowInChat = true,
    ShowNotification = true,
    PlaySound = true,
    SoundName = "CHALLENGE_UNLOCKED",
    SoundSet = "HUD_AWARDS",
    ChatColor = {255, 0, 0}
}


Config.LEOCannotTrigger911 = true


Config.GPSRouting = {
    AutoRoute = true,
    ShowDistance = true,
    RouteDuration = 300,
    WaypointSprite = 162,
    WaypointColor = 5,
    ToggleCommand = "gps",
    ClearCommand = "cleargps",
    PanicCommand = "route911"
}


Config.Paychecks = {
    Enabled = true,

    Interval = 35,

    OnDutyPay = 1200,

}


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


Config.CAD = {
    Debug = false,
}

Config.TrafficStop = {
    Command            = 'ts',
    AltCommand         = 'trafficstop',
    CooldownSeconds    = 5,
    RequireLEO         = true,
    PlateMaxAgeSeconds = 120,
}


Config.Advanced = {
    RemoveWeaponsOffDuty = true,
    SaveCivilianWeapons = true,
    PersistDutyStatus = false,
    DebugMode = false
}


Config.Discord = {
    Enabled = true,


    TimeTracking = {
        Enabled = true,
        SaveInterval = 900,
        ShowTimeInWebhook = true,
        MinimumDutyTime = 300
    },
    
    BotName = "CDE Duty System",
    
    Colors = {
        DutyOn = 65280,
        DutyOff = 16711680,
        SWAT = 16776960
    }
}


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

do
    local Config

Config = {}



Config.Persistence = 'kvp'

Config.MySQLTable = 'cdecad_selected_civs'


Config.Commands = {
    SelectCiv = 'setciv',
    
    ShowInfo = 'myciv',
    
    RegisterVehicle = 'regveh',
    
    ShowID = 'showid',
    
    ClearCiv = 'clearciv'
}


Config.IDCard = {
    ShowHTML = true,

    LicenseMode = 'auto',

    ShowInChat = true,

    UseOxNotify = false,

    DisplayDuration = 10000,

    ShowRange = 3.0,

    UseOxTarget = true,

    CardStyle = {
        StateName = 'San Andreas',

        CardTitle = "DRIVER'S LICENSE",

        BackgroundColor = '#1a365d',

        TextColor = '#ffffff',

        AccentColor = '#3182ce'
    }
}


Config.Fingerprint = {
    Enabled = true,

    UseOxTarget = true,

    TargetLabel = 'Scan Fingerprint',

    Command = 'scanprint',

    RequireLEO = true,

    Range = 2.5,

    ScanDuration = 2500,

    DisplayDuration = 20000,

    NotifySubject = true
}



Config.VehicleRegistration = {
    Enabled = true,
    
    RequireInVehicle = true,
    
    AutoDetect = true,
    
    AllowStolen = false
}


Config.Notifications = {
    UseOxLib = true,
    
    Duration = 5000,
    
    Position = 'top-right'
}


Config.CaptureFiveMMugshot = false


Config.Debug = true
    _G.CivConfig = Config
end

do
    local Config
Config = {}

Config.Debug = false

Config.Command911      = '911'
Config.CommandAnon     = 'a911'

Config.DefaultCallType = '911 Call'
Config.AnonCallerName  = 'Anonymous'
Config.LbPhone         = true
Config.DefaultPriority = 'normal'
Config.CooldownSeconds = 10
Config.NotifyOnDuty    = true

Config.ChatEnabled = true

Config.Messages = {
    sent     = '^2[911] ^0Your call has been dispatched. Help is on the way.',
    sentAnon = '^2[911] ^0Anonymous report submitted.',
    cooldown = '^1[911] ^0Please wait %d seconds before calling again.',
    noMsg    = '^1[911] ^0Usage: /911 <description of your emergency>',
}

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
        Enabled    = false,
        Cooldown   = 60,
        Cameras    = {},
    },
}

Config.ALPR = {
    Enabled = true,

    Command = 'alprcam',
    CommandAliases = { 'alpr' },

    RequireOnDutyLEO = true,

    CameraRadius      = 35.0,
    ClientActiveRange = 200.0,
    ScanInterval      = 1200,

    MaxCameras = 50,

    Directional = true,
    FOV         = 120.0,

    PlacementUI = true,

    IgnoreEmergencyVehicles = true,
    OnlyPlayerVehicles      = true,

    CallCooldownSeconds = 300,

    MinAlertLevel = 'caution',
    AlertFlags    = {},

    SpeedOptions = { 25, 35, 45, 55, 65, 70, 80 },

    Alerts = {
        Enabled      = true,
        LEOOnly      = true,
        Chat         = true,
        Blip         = true,
        BlipDuration = 60,
        Sound        = true,
    },

    SpeedCallType = 'ALPR Speed',

    Screenshots = {
        Enabled        = true,
        RetentionHours = 24,

        CameraPOV = true,
        POVFov    = 55.0,

        Overlay = true,
    },

    CallType   = 'ALPR Hit',
    CallerName = 'ALPR Camera',

    CacheRefreshMinutes = 60,

    Blip = {
        Enabled = true,
        Sprite  = 184,
        Color   = 5,
        Scale   = 0.8,
        Label   = 'ALPR Camera',
    },

    Prop = {
        Enabled = true,
        Model   = 'prop_cctv_cam_04a',
        LensOffset = 180.0,
        Models  = {
            'prop_cctv_cam_04a',
            'prop_cctv_cam_04b',
            'prop_cctv_cam_05a',
            'prop_cctv_cam_02a',
            'prop_cctv_cam_01b',
        },
    },

    Marker = {
        Enabled      = false,
        DrawDistance = 40.0,
    },
}
    _G.Cad911Config = Config
end

do
    local Config = {}

    Config.Enabled = true


    Config.PlateReader = {
        LookupOnLock           = true,
        LookupOnScan           = true,
        LookupCooldown         = 10,
        OnlyPlayerPlates       = true,
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

    Config.Notifications = {
        UseOxLib = false,
        Position = 'top-right',
        Duration = 8000,
        Detailed = true,
    }

    Config.LockFallback = {
        Enabled = true,
        Range   = 35.0,
    }

    Config.SeamlessLock = {
        Enabled = true,
        PollMs  = 250,
        LockExport        = nil,
        PlateExport       = nil,
        LockedPlateExport = nil,
    }

    Config.Reader = {
        Enabled = true,
        Command = 'reader',
        ScanRadius    = 45.0,
        ScanInterval  = 1500,
        PlateCooldown = 45,
    }

    Config.Debug = false

    _G.WraithConfig = Config
end

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

do
    local Config
Config = {}

Config.Debug = false

Config.Command       = 'panic'
Config.KeybindKey    = 'Y'
Config.KeybindLabel  = 'Panic Button'

Config.CooldownSeconds     = 30
Config.BlipDurationSeconds = 60

Config.RequireOnDutyLEO   = true
Config.BroadcastToLEOOnly = true

Config.Auto911          = true
Config.Auto911CallType  = 'Officer Panic'
Config.Auto911Caller    = 'SYSTEM - PANIC'

Config.BlipSprite   = 526
Config.BlipColor    = 1
Config.BlipScale    = 1.5
Config.BlipFlashes  = true
Config.ShowRoute    = true

Config.ChatEnabled = true
Config.ChatColor   = { 255, 50, 50 }

Config.Messages = {
    activated = '^1[PANIC] ^0Officer ^3%s^0 has activated their panic button! Location: ^3%s',
    cooldown  = '^1[PANIC] ^0You must wait %d seconds before using panic again.',
    cleared   = '^1[PANIC] ^0Panic alert for ^3%s^0 has expired.',
    notOnDuty = '^1[PANIC] ^0Only on-duty LEOs can use the panic button.',
}

    _G.PanicConfig = Config
end
