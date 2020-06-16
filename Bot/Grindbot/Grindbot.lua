local DMW = DMW
DMW.Bot.Grindbot = {}
local Grindbot = DMW.Bot.Grindbot
local Navigation = DMW.Bot.Navigation
local Gathering = DMW.Bot.Gathering
local Vendor = DMW.Bot.Vendor
local Combat = DMW.Bot.Combat
local Log = DMW.Bot.Log
local Misc = DMW.Bot.Misc

local Throttle = false
local VendorTask = false
local InformationOutput = false
local skinBlacklist = {}
local lootBlacklist = {}
local moveToLootTime

local PauseFlags = {
    movingToLoot = false,
    Interacting = false,
    Skinning = false,
    Information = false,
    CantEat = false,
    CantDrink = false,
    skinDelay = false,
    waitingForLootable = false,
}

local Modes = {
    Resting = 0,
    Dead = 1,
    Combat = 2,
    Grinding = 3,
    Vendor = 4,
    Roaming = 5,
    Looting = 6,
    Gathering = 7,
    Idle = 8
}

Grindbot.Mode = 0

local Settings = {
    RestHP = 60,
    RestMana = 50,
    RepairPercent = 40,
    MinFreeSlots = 5,
    BuyFood = false,
    BuyWater = false,
    FoodName = '',
    WaterName = ''
}

-- Just to show our mode
local ModeFrame = CreateFrame("Frame",nil,UIParent)
ModeFrame:SetWidth(1)
ModeFrame:SetHeight(1)
ModeFrame:SetAlpha(.90);
ModeFrame:SetPoint("CENTER",0,-200)
ModeFrame.text = ModeFrame:CreateFontString(nil,"ARTWORK")
ModeFrame.text:SetFont("Fonts\\ARIALN.ttf", 13, "OUTLINE")
ModeFrame.text:SetPoint("CENTER",0,0)
--

local evFrame=CreateFrame("Frame");
evFrame:RegisterEvent("CHAT_MSG_WHISPER");
evFrame:RegisterEvent("LOOT_CLOSED");
evFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
evFrame:SetScript("OnEvent",function(self,event,msg,ply)
    if DMW.Settings.profile then
        if DMW.Settings.profile.Grind.ignoreWhispers then
            if event == "CHAT_MSG_WHISPER" then
                Log:DebugInfo('Added [' .. ply .. '] To Ignore List')
                RunMacroText('/Ignore ' .. ply)
            end
        end
        if DMW.Settings.profile.Grind.doSkin then
            if event == "LOOT_CLOSED" then
                PauseFlags.skinDelay = true C_Timer.After(1.8, function() PauseFlags.skinDelay = false end)
            end
        end
        if DMW.Settings.profile.Helpers.AutoLoot then
            if event == "COMBAT_LOG_EVENT_UNFILTERED" then
                local _, type = CombatLogGetCurrentEventInfo()
                if type == "PARTY_KILL" then
                    PauseFlags.waitingForLootable = true C_Timer.After(1, function() PauseFlags.waitingForLootable = false end)
                end
            end 
        end
    end
end)

-- < Global functions
function ClearHotspot()
    for k in pairs (DMW.Settings.profile.Grind.HotSpots) do
        DMW.Settings.profile.Grind.HotSpots[k] = nil
    end
    Log:DebugInfo('Hotspots Cleared!')
end

-- < Global functions
function ClearVendorWaypoints()
    for k in pairs (DMW.Settings.profile.Grind.VendorWaypoints) do
        DMW.Settings.profile.Grind.VendorWaypoints[k] = nil
    end
    Log:DebugInfo('VendorWaypoints Cleared!')
end

function addSkinBlacklist()
    table.insert(skinBlacklist, DMW.Player.Target.Pointer)
end

function blackListContains(unit)
    for i=1, #skinBlacklist do
        if skinBlacklist[i] == unit then
           return true
        end
     end
     return false
end
-- Global functions />

function Grindbot:ClearBlackList()
    for i = 1, #skinBlacklist do
        if skinBlacklist[i] and not ObjectExists(skinBlacklist[i]) then
            skinBlacklist[i] = nil
        end
    end
    local cleanBlacklist = CleanNils(skinBlacklist)
    skinBlacklist = cleanBlacklist
end

function Grindbot:OnLootBlacklist(unit)
    for i=1, #lootBlacklist do
        if lootBlacklist[i] == unit then
           return true
        end
     end
     return false
end

function Grindbot:CanLoot()
    if not DMW.Settings.profile.Helpers.AutoLoot then return false end
    if Misc:GetFreeSlots() == 0 then return false end
    if DMW.Player.Casting then return false end
    if PauseFlags.skinDelay then return end

        local Table = {}
        for _, Unit in pairs(DMW.Units) do
            if Unit.Dead and not blackListContains(Unit.Pointer) and not self:OnLootBlacklist(Unit.Pointer) and (UnitCanBeLooted(Unit.Pointer) or UnitCanBeSkinned(Unit.Pointer) and DMW.Settings.profile.Grind.doSkin) then
                table.insert(Table, Unit)
            end
        end

        if #Table > 1 then
            table.sort(
                Table,
                function(x, y)
                    return x.Distance < y.Distance
                end
            )
        end

        for _, Unit in ipairs(Table) do
            if Unit.Distance <= 30 then
                return true, Unit
            end
        end
    return false
end

function Grindbot:Pulse()
    -- < Do Stuff With Timer
    if not Throttle then
        self:LoadSettings()
        if DMW.Settings.profile.Grind.openClams then Misc:ClamTask() end
        Misc:DeleteTask()
        self:ClearBlackList()
        self:SetFoodAndWater()
        Throttle = true
        C_Timer.After(0.1, function() Throttle = false end)
    end
    -- Do stuff with timer end />

    if #DMW.Settings.profile.Grind.HotSpots < 2 then
        if not PauseFlags.Information then
            Log:DebugInfo('You need atleast 2 hotspots.')
            PauseFlags.Information = true
            RunMacroText('/LILIUM HUD Grindbot 2')
            C_Timer.After(1, function() PauseFlags.Information = false end)
        end
        return
    end

    -- Call the enable and disable function of rotation when going to and from vendor.
    --Misc:RotationToggle()
    if DMW.Player.Casting then self:ResetMoveToLoot() end -- Reset if casting
    -- self:AntiObject()

    if not InformationOutput then
        Log:NormalInfo('Food Vendor [' .. DMW.Settings.profile.Grind.FoodVendorName .. '] Distance [' .. math.floor(GetDistanceBetweenPositions(DMW.Player.PosX, DMW.Player.PosY, DMW.Player.PosZ, DMW.Settings.profile.Grind.FoodVendorX, DMW.Settings.profile.Grind.FoodVendorY, DMW.Settings.profile.Grind.FoodVendorZ)) .. ' Yrds]')
        Log:NormalInfo('Repair Vendor [' .. DMW.Settings.profile.Grind.RepairVendorName .. '] Distance [' .. math.floor(GetDistanceBetweenPositions(DMW.Player.PosX, DMW.Player.PosY, DMW.Player.PosZ, DMW.Settings.profile.Grind.RepairVendorX, DMW.Settings.profile.Grind.RepairVendorY, DMW.Settings.profile.Grind.RepairVendorZ)) .. ' Yrds]')
        Log:NormalInfo('Number of hotspots: ' .. #DMW.Settings.profile.Grind.HotSpots)
        InformationOutput = true
    end

    -- This sets our state
    if not (PauseFlags.skinDelay and DMW.Settings.profile.Grind.doSkin) and not (PauseFlags.waitingForLootable and DMW.Settings.profile.Helpers.AutoLoot) then self:SwapMode() end

    if Grindbot.Mode ~= Modes.Looting then Grindbot:ResetMoveToLoot() end
    -- Do whatever our mode says.
    if Grindbot.Mode == Modes.Dead then
        Navigation:MoveToCorpse()
        ModeFrame.text:SetText('Corpse Run')
    end

    if Grindbot.Mode == Modes.Combat then
        Combat:AttackCombat()
        ModeFrame.text:SetText('Combat Attack')
    end

    if Grindbot.Mode == Modes.Resting then
        self:Rest()
        ModeFrame.text:SetText('Resting')
    end

    if Grindbot.Mode == Modes.Vendor then
        Vendor:DoTask()
        ModeFrame.text:SetText('Vendor run')
    end

    if Grindbot.Mode == Modes.Looting then
        self:GetLoot()
        ModeFrame.text:SetText('Looting')
    end

    if Grindbot.Mode == Modes.Gathering then
        Gathering:Gather()
        ModeFrame.text:SetText('Gathering')
    end

    if Grindbot.Mode == Modes.Grinding then
        Combat:Grinding()
        ModeFrame.text:SetText('Grinding')
    end

    if Grindbot.Mode == Modes.Roaming then
        Navigation:GrindRoam()
        ModeFrame.text:SetText('Roaming')
    end

    if Grindbot.Mode == Modes.Idle then
        Navigation:StopMoving()
        ModeFrame.text:SetText('Rotation')
    end
end

function Grindbot:DisabledFunctions()
    Misc:Hotspotter()
    Navigation:ResetPath()
    Navigation:SortHotspots()
    if InformationOutput then InformationOutput = false end
    ModeFrame.text:SetText('Disabled')
end

function Grindbot:AntiObject()
    for _, Object in pairs(DMW.GameObjects) do
        if (Object.Name == "Campfire" or Object.Name == "Pillar of Diamond") and Object.Distance <= 5 then
            local px, py, pz = ObjectPosition('player')
            MoveTo(px + 5, py + 5, pz + 1, true)
        end
    end
end

function Grindbot:GetLoot()
    local hasLoot, LootUnit = self:CanLoot()
    local px, py, pz = ObjectPosition('player')
    local lx, ly, lz = ObjectPosition(LootUnit)

    if hasLoot and ObjectExists(LootUnit.Pointer) then
        if LootUnit.Distance > 5 then
            Navigation:MoveTo(LootUnit.PosX, LootUnit.PosY, LootUnit.PosZ)
            if Navigation:ReturnPathEnd() ~= nil then
                if not PauseFlags.movingToLoot then PauseFlags.movingToLoot = true moveToLootTime = DMW.Time end
                local endX, endY, endZ = Navigation:ReturnPathEnd()
                local endPathToUnitDist = GetDistanceBetweenPositions(LootUnit.PosX, LootUnit.PosY, LootUnit.PosZ, endX, endY, endZ)
                if endPathToUnitDist > 3 or DMW.Time - moveToLootTime > 10 then
                    -- Blacklist unit
                    Log:SevereInfo('Added LootUnit to badBlacklist Dist: ' .. endPathToUnitDist .. ' Time: ' .. DMW.Time-moveToLootTime)
                    table.insert(lootBlacklist, LootUnit.Pointer)
                end
                end
        else
            self:ResetMoveToLoot()
            if IsMounted() then Dismount() end
            if not PauseFlags.Interacting then
                for _, Unit in pairs(DMW.Units) do
                    if Unit.Dead and Unit.Distance < 5 then
                        if UnitCanBeLooted(Unit.Pointer) then
                            if InteractUnit(Unit.Pointer) then PauseFlags.Interacting = true C_Timer.After(0.1, function() PauseFlags.Interacting = false end) end
                        end
                    end
                end
                if DMW.Settings.profile.Grind.doSkin and UnitCanBeSkinned(LootUnit.Pointer) and not PauseFlags.Skinning then
                    if not DMW.Player.Casting then
                        if InteractUnit(LootUnit.Pointer) then PauseFlags.Skinning = true C_Timer.After(0.45, function() PauseFlags.Skinning = false end) end
                        return
                    end
                end
            end
        end
    end
    Misc:LootAllSlots()
end

function Grindbot:ResetMoveToLoot()
    moveToLootTime = DMW.Time
    PauseFlags.movingToLoot = false
end

function Grindbot:Rest()
    local Eating = DMW.Player.Eating
    local Drinking = DMW.Player.Drinking
    local Bandaging = DMW.Player.Bandaging
    local RecentlyBandaged = DMW.Player.RecentlyBandaged

    if DMW.Player.Moving then Navigation:StopMoving() return end
    if DMW.Player.Casting then return end

    CancelShapeshiftForm()

    if DMW.Settings.profile.Grind.firstAid then
        bandage = getBestUsableBandage()
        if DMW.Player.HP < Settings.RestHP and not Eating and not Drinking and not RecentlyBandaged and bandage then
            UseItemByName(bandage.Name, 'player')
            return
        end
    end

    local drinkName, drinkCount = Vendor:scanBagsForDrink();
    local foodName, foodCount = Vendor:scanBagsForFood();

    if drinkCount > 0 then
        if UnitPower('player', 0) / UnitPowerMax('player', 0) * 100 < Settings.RestMana and not Drinking and not Bandaging and not PauseFlags.CantDrink then
            UseItemByName(drinkName)
            PauseFlags.CantDrink = true
            C_Timer.After(1, function() PauseFlags.CantDrink = false end)
        end
    end

    if foodCount > 0 then
        if DMW.Player.HP < Settings.RestHP and not Eating and not Bandaging and not PauseFlags.CantEat then
            UseItemByName(foodName)
            PauseFlags.CantEat = true
            C_Timer.After(1, function() PauseFlags.CantEat = false end)
        end
    end
end

function Grindbot:SwapMode()
    if UnitIsDeadOrGhost('player') then
        Grindbot.Mode = Modes.Dead
        return
    end

    local Eating = AuraUtil.FindAuraByName('Food', 'player')
    local Drinking = AuraUtil.FindAuraByName('Drink', 'player')
    local hasEnemy, theEnemy = Combat:SearchEnemy()
    local hasAttackable, theAttackable = Combat:SearchAttackable()
    local hasOre = Gathering:OreSearch()
    local hasHerb = Gathering:HerbSearch()

    -- If we arent in combat and we arent standing (if our health is less than 95 percent and we currently have the eating buff or we are a caster and our mana iss less than 95 and we have the drinking buff) then set mode to rest.
    if not DMW.Player.Swimming and not DMW.Player.Combat and not DMW.Player:Standing() and (DMW.Player.HP < 95 and Eating or UnitPower('player', 0) > 0 and (UnitPower('player', 0) / UnitPowerMax('player', 0) * 100) < 95 and Drinking) then
        Grindbot.Mode = Modes.Resting
        return
    else
        -- If the above is not true and we arent standing, we stand.
        if not DMW.Player:Standing() then DoEmote('STAND') end
    end

    -- (TRIAL!)
    if Navigation:NearHotspot(200) and hasEnemy then
        Grindbot.Mode = Modes.Combat
        return
    end

    -- if we dont have skip aggro enabled in pathing and we arent mounted and we are in combat, fight back.
    if not DMW.Settings.profile.Grind.SkipCombatOnTransport and not IsMounted() and hasEnemy then
        Grindbot.Mode = Modes.Combat
        return
    end

    -- If we are not in combat and not mounted and our health is less than we decided or if we use mana and its less than decided do the rest function.
    if not DMW.Player.Swimming and not DMW.Player.Combat and not IsMounted() and (DMW.Player.HP < Settings.RestHP or UnitPower('player', 0) > 0 and (UnitPower('player', 0) / UnitPowerMax('player', 0) * 100) < Settings.RestMana) then
        Grindbot.Mode = Modes.Resting
        return
    end

    -- Loot out of combat?
    if self:CanLoot() and not hasEnemy then
        Grindbot.Mode = Modes.Looting
        return
    end

    -- If we are on vendor task and the Vendor.lua has determined the task to be done then we set the vendor task to false.
    if VendorTask and Vendor:TaskDone() then
        VendorTask = false
        return
    end

    -- Force vendor while vendor task is true, this is set in Vendor.lua file to make sure we complete it all.
    if VendorTask then
        Grindbot.Mode = Modes.Vendor
        return
    end

    -- If our durability is less than we decided or our bag slots is less than decided, vendor task :)
    if (Vendor:GetDurability() <= Settings.RepairPercent or Misc:GetFreeSlots() < Settings.MinFreeSlots) then
        Grindbot.Mode = Modes.Vendor
        if not VendorTask then
            Vendor:Reset()
            VendorTask = true
        end
        return
    end

    -- if we chose to buy food and we dont have any food, if we chose to buy water and we dont have any water, Vendor task.
    if (Settings.BuyFood and foodCount == 0) or (Settings.BuyWater and drinkCount == 0) then
        Grindbot.Mode = Modes.Vendor
        if not VendorTask then
            Vendor:Reset()
            VendorTask = true
        end
        return
    end

    -- Gather when we are within 100 yards of hotspot
    if (hasOre and DMW.Settings.profile.Grind.mineOre or hasHerb and DMW.Settings.profile.Grind.gatherHerb) then
        Grindbot.Mode = Modes.Gathering
        return
    end

     -- if we are not within 105 yards of the hotspots then walk to them no matter what. (IF WE CHOSE THE SKIP AGGRO SETTING)
    if not Navigation:NearHotspot(DMW.Settings.profile.Grind.RoamDistance) and DMW.Settings.profile.Grind.SkipCombatOnTransport and not Combat:HasTarget() then
        Grindbot.Mode = Modes.Roaming
        return
    end

    -- if we arent in combat and we arent casting and there are units around us, start grinding em.  (If we arent in combat or if we are in combat and our target is denied(grey) then search for new.)
    if (not DMW.Player.Combat or DMW.Player.Combat and DMW.Player.Target and (UnitIsTapDenied(DMW.Player.Target.Pointer) or not UnitAffectingCombat("DMW.Player.Target.Pointer"))) and not DMW.Player.Casting and hasAttackable then
        Grindbot.Mode = Modes.Grinding
        return
    end

    -- if there isnt anything to attack and we arent in combat then roam around till we find something.
    if not hasAttackable and (not DMW.Player.Combat or DMW.Player.Combat and DMW.Player.Target and (UnitIsTapDenied(DMW.Player.Target.Pointer) or not UnitAffectingCombat("DMW.Player.Target.Pointer"))) then
        Grindbot.Mode = Modes.Roaming
        return
    end

    if not Navigation:NearHotspot(100) then
        Grindbot.Mode = Modes.Roaming
        return
    end

    Grindbot.Mode = Modes.Idle
end

function Grindbot:LoadSettings()
    CheckNextProfile()

    if Settings.BuyWater ~= DMW.Settings.profile.Grind.BuyWater then
        Settings.BuyWater = DMW.Settings.profile.Grind.BuyWater
    end

    if Settings.BuyFood ~= DMW.Settings.profile.Grind.BuyFood then
        Settings.BuyFood = DMW.Settings.profile.Grind.BuyFood
    end

    if Settings.RepairPercent ~= DMW.Settings.profile.Grind.RepairPercent then
        Settings.RepairPercent = DMW.Settings.profile.Grind.RepairPercent
    end

    if Settings.MinFreeSlots ~= DMW.Settings.profile.Grind.MinFreeSlots then
        Settings.MinFreeSlots = DMW.Settings.profile.Grind.MinFreeSlots
    end

    if Settings.RestHP ~= DMW.Settings.profile.Grind.RestHP then
        Settings.RestHP = DMW.Settings.profile.Grind.RestHP
    end

    if Settings.RestMana ~= DMW.Settings.profile.Grind.RestMana then
        Settings.RestMana = DMW.Settings.profile.Grind.RestMana
    end

    if Settings.FoodName ~= DMW.Settings.profile.Grind.FoodName then
        Settings.FoodName = DMW.Settings.profile.Grind.FoodName
    end

    if Settings.WaterName ~= DMW.Settings.profile.Grind.WaterName then
        Settings.WaterName = DMW.Settings.profile.Grind.WaterName
    end
end
