do
    local Config = CivConfig

VehicleUtils = {}
_G.VehicleUtils = VehicleUtils

-- GTA V standard vehicle color indices to readable color names
local GTA_COLORS = {
    [0] = 'Metallic Black',
    [1] = 'Metallic Graphite Black',
    [2] = 'Metallic Black Steel',
    [3] = 'Metallic Dark Silver',
    [4] = 'Metallic Silver',
    [5] = 'Metallic Blue Silver',
    [6] = 'Metallic Steel Gray',
    [7] = 'Metallic Shadow Silver',
    [8] = 'Metallic Stone Silver',
    [9] = 'Metallic Midnight Silver',
    [10] = 'Metallic Gun Metal',
    [11] = 'Metallic Anthracite Gray',
    [12] = 'Matte Black',
    [13] = 'Matte Gray',
    [14] = 'Matte Light Gray',
    [15] = 'Util Black',
    [16] = 'Util Black Poly',
    [17] = 'Util Dark Silver',
    [18] = 'Util Silver',
    [19] = 'Util Gun Metal',
    [20] = 'Util Shadow Silver',
    [21] = 'Worn Black',
    [22] = 'Worn Graphite',
    [23] = 'Worn Silver Gray',
    [24] = 'Worn Silver',
    [25] = 'Worn Blue Silver',
    [26] = 'Worn Shadow Silver',
    [27] = 'Metallic Red',
    [28] = 'Metallic Torino Red',
    [29] = 'Metallic Formula Red',
    [30] = 'Metallic Blaze Red',
    [31] = 'Metallic Graceful Red',
    [32] = 'Metallic Garnet Red',
    [33] = 'Metallic Desert Red',
    [34] = 'Metallic Cabernet Red',
    [35] = 'Metallic Candy Red',
    [36] = 'Metallic Sunrise Orange',
    [37] = 'Classic Red',
    [38] = 'Metallic Red',
    [39] = 'Metallic Dark Red',
    [40] = 'Matte Red',
    [41] = 'Matte Dark Red',
    [42] = 'Metallic Orange',
    [43] = 'Matte Orange',
    [44] = 'Metallic Light Orange',
    [45] = 'Metallic Rust Orange',
    [46] = 'Matte Rust Orange',
    [47] = 'Util Red',
    [48] = 'Util Bright Red',
    [49] = 'Util Garnet Red',
    [50] = 'Worn Red',
    [51] = 'Worn Golden Red',
    [52] = 'Worn Dark Red',
    [53] = 'Metallic Dark Green',
    [54] = 'Metallic Racing Green',
    [55] = 'Metallic Sea Green',
    [56] = 'Metallic Olive Green',
    [57] = 'Metallic Green',
    [58] = 'Metallic Gas Green',
    [59] = 'Matte Lime Green',
    [60] = 'Util Dark Green',
    [61] = 'Util Green',
    [62] = 'Worn Dark Green',
    [63] = 'Worn Green',
    [64] = 'Worn Sea Wash',
    [65] = 'Metallic Midnight Blue',
    [66] = 'Metallic Dark Blue',
    [67] = 'Metallic Saxony Blue',
    [68] = 'Metallic Blue',
    [69] = 'Metallic Mariner Blue',
    [70] = 'Metallic Harbor Blue',
    [71] = 'Metallic Diamond Blue',
    [72] = 'Metallic Surf Blue',
    [73] = 'Metallic Nautical Blue',
    [74] = 'Metallic Bright Blue',
    [75] = 'Metallic Purple Blue',
    [76] = 'Metallic Spinnaker Blue',
    [77] = 'Metallic Ultra Blue',
    [78] = 'Metallic Bright Blue',
    [79] = 'Util Dark Blue',
    [80] = 'Util Midnight Blue',
    [81] = 'Util Blue',
    [82] = 'Util Sea Foam Blue',
    [83] = 'Util Lightning Blue',
    [84] = 'Util Maui Blue Poly',
    [85] = 'Util Bright Blue',
    [86] = 'Matte Dark Blue',
    [87] = 'Matte Blue',
    [88] = 'Matte Midnight Blue',
    [89] = 'Worn Dark Blue',
    [90] = 'Worn Blue',
    [91] = 'Worn Light Blue',
    [92] = 'Metallic Taxi Yellow',
    [93] = 'Metallic Race Yellow',
    [94] = 'Metallic Bronze',
    [95] = 'Metallic Yellow Bird',
    [96] = 'Metallic Lime',
    [97] = 'Metallic Champagne',
    [98] = 'Metallic Pueblo Beige',
    [99] = 'Metallic Dark Ivory',
    [100] = 'Metallic Choco Brown',
    [101] = 'Metallic Golden Brown',
    [102] = 'Metallic Light Brown',
    [103] = 'Metallic Straw Beige',
    [104] = 'Metallic Moss Brown',
    [105] = 'Metallic Bison Brown',
    [106] = 'Metallic Creek Brown',
    [107] = 'Metallic Dark Beechwood',
    [108] = 'Metallic Beechwood',
    [109] = 'Metallic Dark Beechwood',
    [110] = 'Metallic Choco Orange',
    [111] = 'Worn Brown',
    [112] = 'Worn Honey Beige',
    [113] = 'Worn Brown',
    [114] = 'Worn Dark Brown',
    [115] = 'Worn Straw Beige',
    [116] = 'Brushed Steel',
    [117] = 'Brushed Black Steel',
    [118] = 'Brushed Aluminium',
    [119] = 'Chrome',
    [120] = 'Worn Off White',
    [121] = 'Util Off White',
    [122] = 'Worn Orange',
    [123] = 'Worn Light Orange',
    [124] = 'Metallic Securicor Green',
    [125] = 'Worn Taxi Yellow',
    [126] = 'Police Car Blue',
    [127] = 'Matte Green',
    [128] = 'Matte Brown',
    [129] = 'Worn Orange',
    [130] = 'Matte White',
    [131] = 'Worn White',
    [132] = 'Worn Olive Army Green',
    [133] = 'Pure White',
    [134] = 'Hot Pink',
    [135] = 'Salmon Pink',
    [136] = 'Metallic Vermillion Pink',
    [137] = 'Orange',
    [138] = 'Green',
    [139] = 'Blue',
    [140] = 'Mettalic Black Blue',
    [141] = 'Metallic Black Purple',
    [142] = 'Metallic Black Red',
    [143] = 'Hunter Green',
    [144] = 'Metallic Purple',
    [145] = 'Metallic V Dark Blue',
    [146] = 'Modshop Black',
    [147] = 'Matte Purple',
    [148] = 'Matte Dark Purple',
    [149] = 'Metallic Lava Red',
    [150] = 'Matte Forest Green',
    [151] = 'Matte Olive Drab',
    [152] = 'Matte Desert Brown',
    [153] = 'Matte Desert Tan',
    [154] = 'Matte Foliage Green',
    [155] = 'Default Alloy',
    [156] = 'Epsilon Blue',
    [157] = 'Pure Gold',
    [158] = 'Brushed Gold',
}

-- Strip common prefixes (Metallic, Matte, Util, Worn, Brushed, Classic)
local function simplifyColor(colorName)
    if not colorName then return 'Unknown' end
    local simplified = colorName
        :gsub('^Metallic ', '')
        :gsub('^Matte ', '')
        :gsub('^Util ', '')
        :gsub('^Worn ', '')
        :gsub('^Brushed ', '')
        :gsub('^Classic ', '')
    return simplified
end

--- Convert RGB values to a basic color name.
function VehicleUtils.RGBToColorName(r, g, b)
    local brightness = (r + g + b) / 3

    if brightness < 30 then return 'Black' end
    if brightness > 225 and math.abs(r - g) < 30 and math.abs(g - b) < 30 then return 'White' end

    if math.abs(r - g) < 20 and math.abs(g - b) < 20 then
        if brightness < 80 then return 'Dark Gray' end
        if brightness < 160 then return 'Gray' end
        return 'Light Gray'
    end

    if r > g and r > b then
        if g > b + 40 then
            if r > 200 and g > 150 then return 'Yellow' end
            return 'Orange'
        end
        if b > g + 20 then return 'Pink' end
        return 'Red'
    end

    if g > r and g > b then
        if b > r + 20 then return 'Teal' end
        return 'Green'
    end

    if b > r and b > g then
        if r > g + 20 then return 'Purple' end
        return 'Blue'
    end

    return 'Unknown'
end

--- Resolve a GTA V color value to a readable color name.
--- Handles: number (color index), table (RGB array), string, nil.
function VehicleUtils.ResolveColor(colorValue)
    if colorValue == nil then
        return 'Unknown'
    end

    if type(colorValue) == 'number' then
        local colorName = GTA_COLORS[math.floor(colorValue)]
        if colorName then
            return simplifyColor(colorName)
        end
        return 'Unknown'
    end

    if type(colorValue) == 'table' then
        local r = colorValue[1] or colorValue.r
        local g = colorValue[2] or colorValue.g
        local b = colorValue[3] or colorValue.b
        if r and g and b then
            r, g, b = tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0
            return VehicleUtils.RGBToColorName(r, g, b)
        end
        if colorValue[1] and type(colorValue[1]) == 'number' then
            return VehicleUtils.ResolveColor(colorValue[1])
        end
        return 'Unknown'
    end

    if type(colorValue) == 'string' then
        if colorValue:find('lua_rapidjson') or colorValue:find('table:') then
            return 'Unknown'
        end
        local num = tonumber(colorValue)
        if num then
            return VehicleUtils.ResolveColor(num)
        end
        return colorValue
    end

    return 'Unknown'
end

--- Resolve vehicle make and model from framework shared data, falling back to
--- GTA natives when no framework is available. Runs on both client and server.
--- @param spawnName string The vehicle spawn/model name
--- @param modelHash number|nil Optional model hash for native fallback (client only)
--- @return string make, string model
function VehicleUtils.ResolveMakeModel(spawnName, modelHash)
    if not spawnName or spawnName == '' then
        if modelHash then
            local nativeMake = GetMakeNameFromVehicleModel and GetMakeNameFromVehicleModel(modelHash)
            local nativeModel = GetDisplayNameFromVehicleModel and GetDisplayNameFromVehicleModel(modelHash)
            return nativeMake or 'Unknown', nativeModel or 'Unknown'
        end
        return 'Unknown', 'Unknown'
    end

    local lower = spawnName:lower()

    -- QBox shared vehicles
    if GetResourceState and GetResourceState('qbx_core') == 'started' then
        local ok, vehicles = pcall(function()
            return exports.qbx_core:GetVehiclesByName()
        end)
        if ok and vehicles then
            local vehData = vehicles[lower] or vehicles[spawnName]
            if vehData then
                return vehData.brand or vehData.make or 'Unknown',
                       vehData.name or vehData.model or spawnName
            end
        end
    end

    -- QBCore shared vehicles
    if GetResourceState and GetResourceState('qb-core') == 'started' then
        local ok, QBCore = pcall(function()
            return exports['qb-core']:GetCoreObject()
        end)
        if ok and QBCore and QBCore.Shared and QBCore.Shared.Vehicles then
            local vehData = QBCore.Shared.Vehicles[lower] or QBCore.Shared.Vehicles[spawnName]
            if vehData then
                return vehData.brand or vehData.make or 'Unknown',
                       vehData.name or vehData.model or spawnName
            end
        end
    end

    -- Native fallback (client-side only; these natives don't exist server-side)
    if modelHash and GetMakeNameFromVehicleModel then
        local nativeMake = GetMakeNameFromVehicleModel(modelHash)
        local nativeModel = GetDisplayNameFromVehicleModel(modelHash)
        if nativeModel and nativeModel ~= '' and nativeModel ~= 'CARNOTFOUND' then
            local make = (nativeMake and nativeMake ~= '' and nativeMake ~= 'CARNOTFOUND') and nativeMake or 'Unknown'
            return make, nativeModel
        end
    end

    -- Last resort: capitalize the spawn name so it looks like a model
    local cleaned = spawnName:gsub('^%a%a?%d+', '')
    if cleaned == '' then cleaned = spawnName end
    local model = cleaned:sub(1, 1):upper() .. cleaned:sub(2)
    return 'Unknown', model
end

return VehicleUtils

end
