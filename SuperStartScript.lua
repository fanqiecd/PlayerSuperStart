--==============================================================
-- Player Super Start
-- 按高级设置赠送开局额外单位。
--==============================================================

local RUIVO_DONE_PROPERTY = "RUIVO_START_UNITS_DONE"
local RUIVO_TARGET_HUMAN_ONLY = "HUMAN_ONLY"
local RUIVO_TARGET_ALL_MAJOR = "ALL_MAJOR"
local RUIVO_ERA_ANCIENT_ONLY = "ANCIENT_ONLY"
local RUIVO_ERA_ANY_ERA = "ANY_ERA"
local RUIVO_SCRIPT_START_TURN = Game.GetCurrentGameTurn()

local RUIVO_ERA_INDEX = {
    ERA_ANCIENT = 0,
    ERA_CLASSICAL = 1,
    ERA_MEDIEVAL = 2,
    ERA_RENAISSANCE = 3,
    ERA_INDUSTRIAL = 4,
    ERA_MODERN = 5,
    ERA_ATOMIC = 6,
    ERA_INFORMATION = 7,
    ERA_FUTURE = 8,
}

local RUIVO_DEFAULTS = {
    RUIVO_SETTLER_COUNT = 1,
    RUIVO_WARRIOR_COUNT = 3,
    RUIVO_SCOUT_COUNT = 1,
    RUIVO_BUILDER_COUNT = 1,
    RUIVO_SLINGER_COUNT = 0,
    RUIVO_TRADER_COUNT = 0,
    RUIVO_TARGET_PLAYERS = RUIVO_TARGET_HUMAN_ONLY,
    RUIVO_ERA_LIMIT = RUIVO_ERA_ANCIENT_ONLY,
}

local function RUIVO_Log(message)
    print("[PlayerSuperStart] " .. tostring(message))
end

local function RUIVO_GetConfigValue(key)
    local value = GameConfiguration.GetValue(key)
    if value == nil then
        return RUIVO_DEFAULTS[key]
    end
    return value
end

local function RUIVO_GetCount(key)
    local value = tonumber(RUIVO_GetConfigValue(key)) or RUIVO_DEFAULTS[key] or 0
    if value < 0 then
        return 0
    end
    return math.floor(value)
end

local function RUIVO_GetEraIndexFromValue(value)
    if value == nil then
        return nil
    end

    if type(value) == "string" then
        if RUIVO_ERA_INDEX[value] ~= nil then
            return RUIVO_ERA_INDEX[value]
        end

        local numericValue = tonumber(value)
        if numericValue ~= nil then
            return numericValue
        end
    end

    if type(value) == "number" then
        for eraRow in GameInfo.Eras() do
            if eraRow.Index == value or eraRow.Hash == value then
                return RUIVO_ERA_INDEX[eraRow.EraType]
            end
        end

        return value
    end

    return nil
end

local function RUIVO_GetStartEraIndex()
    if GameConfiguration.GetStartEra ~= nil then
        local startEraIndex = RUIVO_GetEraIndexFromValue(GameConfiguration.GetStartEra())
        if startEraIndex ~= nil then
            return startEraIndex
        end
    end

    local startEraKeys = {
        "START_ERA",
        "GameStartEra",
        "GAME_START_ERA",
        "StartEra",
        "STARTING_ERA",
    }

    for _, key in ipairs(startEraKeys) do
        local startEraIndex = RUIVO_GetEraIndexFromValue(GameConfiguration.GetValue(key))
        if startEraIndex ~= nil then
            return startEraIndex
        end
    end

    if Game.GetEras ~= nil then
        local eras = Game.GetEras()
        if eras ~= nil and eras.GetCurrentEra ~= nil then
            local currentEraIndex = RUIVO_GetEraIndexFromValue(eras:GetCurrentEra())
            if currentEraIndex ~= nil then
                return currentEraIndex
            end
        end
    end

    return 0
end

local function RUIVO_GetAvailableUnitEraIndex()
    local startEraIndex = RUIVO_GetStartEraIndex()
    if startEraIndex <= 0 then
        return 0
    end

    return startEraIndex - 1
end

local function RUIVO_IsEraAllowed()
    local eraLimit = RUIVO_GetConfigValue("RUIVO_ERA_LIMIT")
    if eraLimit == RUIVO_ERA_ANY_ERA then
        return true
    end

    return RUIVO_GetStartEraIndex() <= 0
end

local function RUIVO_PcallBoolean(object, methodName, defaultValue)
    if object == nil or object[methodName] == nil then
        return defaultValue
    end

    local ok, result = pcall(function()
        return object[methodName](object)
    end)

    if not ok or result == nil then
        return defaultValue
    end
    return result
end

local function RUIVO_IsEligiblePlayer(playerID)
    local player = Players[playerID]
    if player == nil then
        return false
    end

    local isMajor = RUIVO_PcallBoolean(player, "IsMajor", true)
    if not isMajor then
        return false
    end

    local targetPlayers = RUIVO_GetConfigValue("RUIVO_TARGET_PLAYERS")
    if targetPlayers ~= RUIVO_TARGET_ALL_MAJOR and not player:IsHuman() then
        return false
    end

    return true
end

local function RUIVO_GetUnitType(player, unitID)
    local unit = player:GetUnits():FindID(unitID)
    if unit == nil then
        return nil
    end

    local typeInfo = GameInfo.Types[unit:GetTypeHash()]
    if typeInfo == nil then
        return nil
    end

    return typeInfo.Type
end

local function RUIVO_FindFirstSettler(playerID)
    local player = Players[playerID]
    if player == nil then
        return nil
    end

    for _, unit in player:GetUnits():Members() do
        local typeInfo = GameInfo.Types[unit:GetTypeHash()]
        if typeInfo ~= nil and typeInfo.Type == "UNIT_SETTLER" then
            return unit
        end
    end

    return nil
end

local function RUIVO_GetTraitTypes(playerID)
    local playerConfig = PlayerConfigurations[playerID]
    if playerConfig == nil then
        return {}
    end

    local traitTypes = {}
    local civilizationType = playerConfig:GetCivilizationTypeName()
    local leaderType = playerConfig:GetLeaderTypeName()

    for traitRow in GameInfo.CivilizationTraits() do
        if traitRow.CivilizationType == civilizationType then
            traitTypes[traitRow.TraitType] = true
        end
    end

    for traitRow in GameInfo.LeaderTraits() do
        if traitRow.LeaderType == leaderType then
            traitTypes[traitRow.TraitType] = true
        end
    end

    return traitTypes
end

local function RUIVO_GetUnitEraIndex(unitRow)
    local eraIndex = 0

    if unitRow.PrereqTech ~= nil then
        local techRow = GameInfo.Technologies[unitRow.PrereqTech]
        if techRow ~= nil and RUIVO_ERA_INDEX[techRow.EraType] ~= nil then
            eraIndex = math.max(eraIndex, RUIVO_ERA_INDEX[techRow.EraType])
        end
    end

    if unitRow.PrereqCivic ~= nil then
        local civicRow = GameInfo.Civics[unitRow.PrereqCivic]
        if civicRow ~= nil and RUIVO_ERA_INDEX[civicRow.EraType] ~= nil then
            eraIndex = math.max(eraIndex, RUIVO_ERA_INDEX[civicRow.EraType])
        end
    end

    return eraIndex
end

local function RUIVO_GetUnitPower(unitRow)
    local combat = tonumber(unitRow.Combat) or 0
    local rangedCombat = tonumber(unitRow.RangedCombat) or 0
    local bombard = tonumber(unitRow.Bombard) or 0
    local cost = tonumber(unitRow.Cost) or 0
    return math.max(combat, rangedCombat, bombard), cost
end

local function RUIVO_UnitHasPrereq(unitRow)
    return (unitRow.PrereqTech ~= nil and unitRow.PrereqTech ~= "")
        or (unitRow.PrereqCivic ~= nil and unitRow.PrereqCivic ~= "")
end

local function RUIVO_PlayerHasTech(playerID, techType)
    if techType == nil or techType == "" then
        return true
    end

    local player = Players[playerID]
    local techRow = GameInfo.Technologies[techType]
    if player == nil or techRow == nil or techRow.Index == nil or player.GetTechs == nil then
        return false
    end

    local playerTechs = player:GetTechs()
    if playerTechs == nil or playerTechs.HasTech == nil then
        return false
    end

    local ok, hasTech = pcall(function()
        return playerTechs:HasTech(techRow.Index)
    end)

    return ok and hasTech == true
end

local function RUIVO_PlayerHasCivic(playerID, civicType)
    if civicType == nil or civicType == "" then
        return true
    end

    local player = Players[playerID]
    local civicRow = GameInfo.Civics[civicType]
    if player == nil or civicRow == nil or civicRow.Index == nil or player.GetCulture == nil then
        return false
    end

    local playerCulture = player:GetCulture()
    if playerCulture == nil or playerCulture.HasCivic == nil then
        return false
    end

    local ok, hasCivic = pcall(function()
        return playerCulture:HasCivic(civicRow.Index)
    end)

    return ok and hasCivic == true
end

local function RUIVO_IsUnitUnlockedForPlayer(playerID, unitRow)
    if unitRow == nil then
        return false
    end

    return RUIVO_PlayerHasTech(playerID, unitRow.PrereqTech)
        and RUIVO_PlayerHasCivic(playerID, unitRow.PrereqCivic)
end

local function RUIVO_IsUnitAvailableForStart(playerID, unitRow, availableEraIndex)
    if unitRow == nil then
        return false
    end

    local startEraIndex = RUIVO_GetStartEraIndex()
    local eraIndex = RUIVO_GetUnitEraIndex(unitRow)
    if eraIndex > availableEraIndex then
        return false
    end

    -- Ancient start should only grant units with no tech/civic prerequisite.
    if startEraIndex <= 0 and RUIVO_UnitHasPrereq(unitRow) then
        return false
    end

    if startEraIndex > 0 and not RUIVO_IsUnitUnlockedForPlayer(playerID, unitRow) then
        return false
    end

    return true
end

local function RUIVO_IsHeroUnit(unitRow)
    if unitRow == nil or unitRow.UnitType == nil then
        return false
    end

    if string.sub(unitRow.UnitType, 1, 10) == "UNIT_HERO_" then
        return true
    end

    if GameInfo.HeroClasses ~= nil then
        for heroRow in GameInfo.HeroClasses() do
            if heroRow.UnitType == unitRow.UnitType then
                return true
            end
        end
    end

    if GameInfo.TypeProperties ~= nil then
        for propertyRow in GameInfo.TypeProperties() do
            if propertyRow.Type == unitRow.UnitType and propertyRow.Name == "LIFESPAN" then
                return true
            end
        end
    end

    return false
end

local function RUIVO_IsBaseStartUnitCandidate(unitRow, promotionClass)
    return unitRow.PromotionClass == promotionClass
        and (unitRow.TraitType == nil or unitRow.TraitType == "")
        and (tonumber(unitRow.Cost) or 0) > 0
        and not RUIVO_IsHeroUnit(unitRow)
end

local function RUIVO_GetBestBaseUnitByPromotionClass(playerID, promotionClass, fallbackUnitType)
    local availableEraIndex = RUIVO_GetAvailableUnitEraIndex()
    local bestUnitType = fallbackUnitType
    local bestEraIndex = -1
    local bestPower = -1
    local bestCost = -1
    local bestHasPrereq = true

    for unitRow in GameInfo.Units() do
        if RUIVO_IsBaseStartUnitCandidate(unitRow, promotionClass) then
            local eraIndex = RUIVO_GetUnitEraIndex(unitRow)
            local power, cost = RUIVO_GetUnitPower(unitRow)
            local hasPrereq = RUIVO_UnitHasPrereq(unitRow)

            if RUIVO_IsUnitAvailableForStart(playerID, unitRow, availableEraIndex) then
                local better = false
                if eraIndex > bestEraIndex then
                    better = true
                elseif eraIndex == bestEraIndex then
                    if power > bestPower then
                        better = true
                    elseif power == bestPower then
                        if cost > bestCost then
                            better = true
                        elseif cost == bestCost and not hasPrereq and bestHasPrereq then
                            better = true
                        end
                    end
                end

                if better then
                    bestUnitType = unitRow.UnitType
                    bestEraIndex = eraIndex
                    bestPower = power
                    bestCost = cost
                    bestHasPrereq = hasPrereq
                end
            end
        end
    end

    return bestUnitType
end

local function RUIVO_FindUnitReplacement(playerID, baseUnitType)
    local traitTypes = RUIVO_GetTraitTypes(playerID)
    local availableEraIndex = RUIVO_GetAvailableUnitEraIndex()

    for unitRow in GameInfo.Units() do
        if traitTypes[unitRow.TraitType] and (tonumber(unitRow.Cost) or 0) > 0 and not RUIVO_IsHeroUnit(unitRow) then
            for replaceRow in GameInfo.UnitReplaces() do
                local replacementUnitType = replaceRow.CivUniqueUnitType or replaceRow.UnitType
                if replacementUnitType == unitRow.UnitType and replaceRow.ReplacesUnitType == baseUnitType then
                    if RUIVO_IsUnitAvailableForStart(playerID, unitRow, availableEraIndex) then
                        return unitRow.UnitType
                    end
                end
            end
        end
    end

    return baseUnitType
end

local function RUIVO_FindUnitForStartEra(playerID, fallbackUnitType, promotionClass)
    if promotionClass == nil then
        return fallbackUnitType
    end

    local baseUnitType = RUIVO_GetBestBaseUnitByPromotionClass(playerID, promotionClass, fallbackUnitType)
    return RUIVO_FindUnitReplacement(playerID, baseUnitType)
end

local function RUIVO_IsValidUnitType(unitType)
    return unitType ~= nil and GameInfo.Units[unitType] ~= nil
end

local function RUIVO_GrantUnits(playerID, unitType, count, x, y)
    if count <= 0 then
        return
    end

    if not RUIVO_IsValidUnitType(unitType) then
        RUIVO_Log("Skip invalid unit: " .. tostring(unitType))
        return
    end

    for _ = 1, count do
        UnitManager.InitUnitValidAdjacentHex(playerID, unitType, x, y, 1)
    end
end

local function RUIVO_GrantStartUnits(playerID, x, y)
    local player = Players[playerID]
    if player == nil then
        return
    end

    if player:GetProperty(RUIVO_DONE_PROPERTY) then
        return
    end

    if not RUIVO_IsEligiblePlayer(playerID) then
        return
    end

    if not RUIVO_IsEraAllowed() then
        player:SetProperty(RUIVO_DONE_PROPERTY, true)
        RUIVO_Log("Skipped player " .. tostring(playerID) .. " because starting era is not Ancient.")
        return
    end

    local warriorType = RUIVO_FindUnitForStartEra(playerID, "UNIT_WARRIOR", "PROMOTION_CLASS_MELEE")
    local scoutType = RUIVO_FindUnitForStartEra(playerID, "UNIT_SCOUT", "PROMOTION_CLASS_RECON")
    local slingerType = RUIVO_FindUnitForStartEra(playerID, "UNIT_SLINGER", "PROMOTION_CLASS_RANGED")

    RUIVO_Log("Start era index " ..
        tostring(RUIVO_GetStartEraIndex()) ..
        ", available unit era index " ..
        tostring(RUIVO_GetAvailableUnitEraIndex()) ..
        ", melee " .. warriorType .. ", recon " .. scoutType .. ", ranged " .. slingerType .. ".")

    RUIVO_GrantUnits(playerID, "UNIT_SETTLER", RUIVO_GetCount("RUIVO_SETTLER_COUNT"), x, y)
    RUIVO_GrantUnits(playerID, warriorType, RUIVO_GetCount("RUIVO_WARRIOR_COUNT"), x, y)
    RUIVO_GrantUnits(playerID, scoutType, RUIVO_GetCount("RUIVO_SCOUT_COUNT"), x, y)
    RUIVO_GrantUnits(playerID, "UNIT_BUILDER", RUIVO_GetCount("RUIVO_BUILDER_COUNT"), x, y)
    RUIVO_GrantUnits(playerID, slingerType, RUIVO_GetCount("RUIVO_SLINGER_COUNT"), x, y)
    RUIVO_GrantUnits(playerID, "UNIT_TRADER", RUIVO_GetCount("RUIVO_TRADER_COUNT"), x, y)

    player:SetProperty(RUIVO_DONE_PROPERTY, true)
    RUIVO_Log("Granted start units to player " .. tostring(playerID) .. ".")
end

function RUIVO_OnUnitTeleported(playerID, unitID, x, y)
    if Game.GetCurrentGameTurn() > RUIVO_SCRIPT_START_TURN + 1 then
        Events.UnitTeleported.Remove(RUIVO_OnUnitTeleported)
        return
    end

    local player = Players[playerID]
    if player == nil or player:GetProperty(RUIVO_DONE_PROPERTY) then
        return
    end

    if RUIVO_GetUnitType(player, unitID) ~= "UNIT_SETTLER" then
        return
    end

    RUIVO_GrantStartUnits(playerID, x, y)
end

function RUIVO_OnPlayerTurnActivated(playerID, isFirstTimeThisTurn)
    if Game.GetCurrentGameTurn() > RUIVO_SCRIPT_START_TURN + 1 then
        Events.PlayerTurnActivated.Remove(RUIVO_OnPlayerTurnActivated)
        return
    end

    if isFirstTimeThisTurn == false then
        return
    end

    local player = Players[playerID]
    if player == nil or player:GetProperty(RUIVO_DONE_PROPERTY) then
        return
    end

    local settler = RUIVO_FindFirstSettler(playerID)
    if settler == nil then
        return
    end

    RUIVO_GrantStartUnits(playerID, settler:GetX(), settler:GetY())
end

Events.UnitTeleported.Add(RUIVO_OnUnitTeleported)
Events.PlayerTurnActivated.Add(RUIVO_OnPlayerTurnActivated)

--==============================================================
