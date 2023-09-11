local addonName, addon = ...


---------------------------
-- Lua Upvalues
---------------------------
local pairs    = pairs
local unpack   = unpack
local next     = next
local select   = select
local tinsert  = table.insert
local tonumber = tonumber
local min      = math.min


---------------------------
-- WoW API Upvalues
---------------------------
local CopyTable = CopyTable
local GetTime = GetTime
local UnitClass = UnitClass
local after = C_Timer.After
local wipe = wipe
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local GetMasteryEffect = GetMasteryEffect


---------------------------
-- Database Defaults
---------------------------
local defaults = {
    throttle = 0.01,
    lb = true,
    lbColor = { 0, 1, 0, 1 },
    sotf = true,
    sotfColor = { 0.66, 0, 1, 1 },
    ver = 1,
}


--------------------------------
-- Spells Affected by SoTF
-- [spellId] = sotf multiplier
--------------------------------
local sotfSpells = {
    [774] = 2.4, -- Rejuv
    [155777] = 2.4, -- Germination
    [8936] = 2.4, -- Regrowth
    [48438] = 1.45, -- Wild Growth
}


---------------------------
-- Lifebloom SpellIds
---------------------------
local lifeblooms = {
    [33763] = true, -- Normal
    [188550] = true, -- Undergrowth
}


---------------------------------------
-- All Druid hots that affect mastery
---------------------------------------
local druidHots = {
    [774] = true, -- Rejuv
    [155777] = true, -- Germination
    [8936] = true, -- Regrowth
    [48438] = true, -- Wild Growth
    [33763] = true, -- Lifebloom
    [188550] = true, -- Undergrowth
    [740] = true, -- Tranquility
    [102352] = true, -- Cenarion Ward Hot
    [200389] = true, -- Cultivation
    [22842] = true, -- Frenzied Regen
    [383193] = true, -- Grove Tending
    [207386] = true, -- Spring Blossoms
}


---------------------------
-- Event Handling
---------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    addon[event](addon, ...)
end)


---------------------------
-- Print Functions
---------------------------
function addon:Print(msg)
    print("|cFF50C878L|rifebloom|cFF50C878G|rlow: " .. msg)
end


---------------------------------
-- Hidden Tooltip
-- Credit: WeakAuras
-- For processing tooltip info
---------------------------------
function addon:GetHiddenTooltip()
    if not self.hiddenTooltip then
        self.hiddenTooltip = CreateFrame("GameTooltip", "LifebloomGlowTooltip", nil, "GameTooltipTemplate")
        self.hiddenTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
        self.hiddenTooltip:AddFontStrings(
            self.hiddenTooltip:CreateFontString("$parentTextLeft1", nil, "GameTooltipText"),
            self.hiddenTooltip:CreateFontString("$parentTextRight1", nil, "GameTooltipText")
        )
    end


    return self.hiddenTooltip
end


----------------------------------------
-- Get Tooltip Info
-- Credit: WeakAuras
-- Replace with C_TooltipInfo in 10.0.2
----------------------------------------
function addon:GetTooltipInfo(unit, auraInstanceID)
    local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)


    local tooltip = addon:GetHiddenTooltip()
    tooltip:ClearLines()


    if aura then
        tooltip:SetUnitBuffByAuraInstanceID(unit, auraInstanceID)
    end


    local tooltipTextLine = select(5, tooltip:GetRegions())
    local text = tooltipTextLine and tooltipTextLine:GetObjectType() == "FontString" and tooltipTextLine:GetText() or ""
    local tooltipSize = {}


    if text then
        for t in text:gmatch("(%d[%d%.,]*)") do
            if (LARGE_NUMBER_SEPERATOR == ",") then
                t = t:gsub(",", "");
            else
                t = t:gsub("%.", "");
                t = t:gsub(",", ".");
            end
            tinsert(tooltipSize, tonumber(t));
        end
    end


    if #tooltipSize then
        return text, unpack(tooltipSize)
    else
        return text, 0, 1
    end
end


---------------------------
-- Glow Frame Func
---------------------------
local function CreateGlowFrame(buffFrame)
    -- Use this frame to ensure the glow is always on top of the buff frame
    local glowFrame = CreateFrame("Frame", nil, buffFrame)
    glowFrame:SetAllPoints()
    glowFrame:SetFrameLevel(buffFrame:GetFrameLevel() + 10)


    local glow = glowFrame:CreateTexture(nil, "OVERLAY")
    glow:SetTexture([[Interface\TargetingFrame\UI-TargetingFrame-Stealable]])
    glow:SetDesaturated(true)
    glow:SetPoint("TOPLEFT", -2.5, 2.5)
    glow:SetPoint("BOTTOMRIGHT", 2.5, -2.5)
    glow:SetBlendMode("ADD")
    buffFrame.glow = glow
end


---------------------------
-- SotF Tables
---------------------------
local sotfCache = {}
local amts = {}


---------------------------
-- SotF Glow Func
---------------------------
local function glowSotf(buffFrame, aura, amtNeeded, glow)
    if glow then
        buffFrame.glow:SetVertexColor(unpack(addon.db.sotfColor))
        buffFrame.glow:Show()
    end


    sotfCache[aura.auraInstanceID] = sotfCache[aura.auraInstanceID] or {}
    sotfCache[aura.auraInstanceID].state = amtNeeded
    sotfCache[aura.auraInstanceID].aura = aura
end
----------------------------
-- SotF Decider
---------------------------
if not addon.db.staticAmtNeeded then
    addon.db.staticAmtNeeded = 12000  -- Initialize with default value
end


local function glowIfSotf(aura, buffFrame)
    local unit = buffFrame:GetParent().unit
    local _, curTick, _ = addon:GetTooltipInfo(unit, aura.auraInstanceID)

    if curTick >= addon.db.staticAmtNeeded then
        glowSotf(buffFrame, aura, curTick, true)
        return
    end
end
---------------------------
-- LB Decider
---------------------------
local function glowIfLB(aura, buffFrame)
    if lifeblooms[aura.spellId] then
        addon.lbInstances[aura.auraInstanceID] = true
        addon.lbAuras[buffFrame] = aura
        addon.lbUpdate:Show()
    else
        addon.lbAuras[buffFrame] = nil
    end
end


-------------------------------------
-- Decide if we care about the aura
-------------------------------------
function addon:HandleAura(buffFrame, aura)
    if not buffFrame.glow then
        CreateGlowFrame(buffFrame)
    end


    buffFrame.glow:Hide()


    if not aura then return end


    if self.db.lb then
        glowIfLB(aura, buffFrame)
    end


    if not aura.isFromPlayerOrPlayerPet
    or aura.isHarmful then return end


    if self.db.sotf and sotfSpells[aura.spellId] then
        for k, v in pairs(sotfCache) do
            local a = v.aura
            if a and (a.expirationTime < GetTime()) then
                sotfCache[k] = nil
            end
        end
        glowIfSotf(aura, buffFrame)
    end
end


---------------------------
-- Target/Focus Frame Core
---------------------------
function addon:TargetFocus(root)
    for buffFrame in root.auraPools:EnumerateActive() do
        self:HandleAura(buffFrame, C_UnitAuras.GetAuraDataByAuraInstanceID(root.unit, buffFrame.auraInstanceID))
    end
end


---------------------------
-- Updating Mastery
---------------------------
function addon:COMBAT_RATING_UPDATE()
    self.mastery = GetMasteryEffect() / 100
end


---------------------------
-- Talent Updates
---------------------------
function addon:TRAIT_TREE_CURRENCY_INFO_UPDATED()
    -- Get the rank for Harmonius Blooming to determine mastery stacks with lifebloom
    local hbNode = C_Traits.GetNodeInfo(C_ClassTalents.GetActiveConfigID(), 82065)
    local hbRank = hbNode and hbNode.activeRank or 0


    self.harmBlooming = hbRank + 1


    for spellId in pairs(sotfSpells) do
        local spell = Spell:CreateFromSpellID(spellId)


        spell:ContinueOnSpellLoad(function()
            local desc = spell:GetSpellDescription()


            desc = desc:gsub(",", "")
            local amount, dur = desc:match("(%d[%d%.]*) over (%d[%d%.]*) sec")
            if not amount or not dur then return end


            self.baseTickCache[spellId] = amount / dur
        end)
    end
end


function addon:ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
    self:TRAIT_TREE_CURRENCY_INFO_UPDATED()
end


-----------------------------------
-- Localized functions for CLEU
-- so C_Timer doesn't have to
-- create new functions every run
-----------------------------------
local function disableOvergrowth()
    addon.overgrowth = false
end


local function disableSotfAura()
    addon.sotfUp = false
end


---------------------------
-- CLEU
---------------------------
function addon:COMBAT_LOG_EVENT_UNFILTERED()
    if not self.db.sotf then
        eventFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end


    local _, event, _, sourceGUID, _, _, _, _, _, _, _, spellId = CombatLogGetCurrentEventInfo()


    if sourceGUID ~= self.playerGUID then return end


    if event == "SPELL_CAST_SUCCESS" and spellId == 203651 then
        self.overgrowth = true
        after(0, disableOvergrowth)
    elseif event == "SPELL_AURA_APPLIED" and spellId == 114108 then
        self.sotfUp = true
    elseif event == "SPELL_AURA_REMOVED" and spellId == 114108 then
        after(0, disableSotfAura)
    end
end


---------------------------
-- Toggle Sotf
---------------------------
function addon:EnableSotf(enable)
    self.db.sotf = enable


    if self.playerClass == "DRUID" and enable then
        eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        eventFrame:RegisterEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED")
        eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
        eventFrame:RegisterEvent("COMBAT_RATING_UPDATE")
        self:TRAIT_TREE_CURRENCY_INFO_UPDATED()
        self:COMBAT_RATING_UPDATE()
    else
        eventFrame:UnregisterAllEvents()
    end
end


---------------------------
-- Initialize
---------------------------
function addon:PLAYER_LOGIN()
    LifebloomGlowDB = LifebloomGlowDB or CopyTable(defaults)


    ---------------------------
    -- DB Validation
    ---------------------------
    local ver = LifebloomGlowDB.ver or 0
    if ver < 1 then
        LifebloomGlowDB = CopyTable(defaults)
    else
        for k in pairs(defaults) do
            if LifebloomGlowDB[k] == nil then
                LifebloomGlowDB = CopyTable(defaults)
                break
            end
        end
    end


    self.db = LifebloomGlowDB
    self.baseTickCache = {}
    self.lbInstances = {}
    self.lbAuras = {}
    self.playerGUID = UnitGUID("player")
    self.playerClass = select(2, UnitClass("player"))


    self:Options()


    ---------------------------
    -- Slash Handler
    ---------------------------
    SLASH_LIFEBLOOMGLOW1 = "/sotf"
    function SlashCmdList.LIFEBLOOMGLOW(msg)
        if msg == "help" then
            self:Print("Available commands:")
            self:Print("/sotf help - Show this help")
        else
            InterfaceOptionsFrame_OpenToCategory(addonName)
            InterfaceOptionsFrame_OpenToCategory(addonName)
        end
    end


    -- Only load for druids
    if (self.playerClass ~= "DRUID") then
        self:Print("Functionality disabled when not playing a |cffff7c0aDruid|r")
        return
    end


    self:EnableSotf(self.db.sotf)


    ---------------------------
    -- Hooks
    ---------------------------
    hooksecurefunc("CompactUnitFrame_UtilSetBuff", function(s, ...)
        self:HandleAura(s, ...)
    end)


    hooksecurefunc(TargetFrame, "UpdateAuras", function(s)
        self:TargetFocus(s)
    end)


    hooksecurefunc(FocusFrame, "UpdateAuras", function(s)
        self:TargetFocus(s)
    end)


    ----------------------------------------
    -- Lifebloom Update Frame (Main Loop)
    ----------------------------------------
    self.lbUpdate = CreateFrame("Frame")
    local lastUpdate = 0
    self.lbUpdate:SetScript("OnUpdate", function(s, elapsed)
        if not self.db.lb then
            s:Hide()
            return
        end


        lastUpdate = lastUpdate + elapsed
        if lastUpdate >= self.db.throttle then
            lastUpdate = 0


            if next(self.lbAuras) == nil then
                s:Hide()
                return
            end


            for buffFrame, aura in pairs(self.lbAuras) do
                if aura.expirationTime < GetTime() then
                    buffFrame.glow:Hide()
                    self.lbAuras[buffFrame] = nil
                    self.lbInstances[aura.auraInstanceID] = nil
                elseif self.lbInstances[aura.auraInstanceID] then
                    local timeRemaining = (aura.expirationTime - GetTime()) / aura.timeMod
                    local refreshTime = aura.duration * 0.3


                    if (timeRemaining <= refreshTime) then
                        buffFrame.glow:SetVertexColor(unpack(self.db.lbColor))
                        buffFrame.glow:Show()
                    else
                        buffFrame.glow:Hide()
                    end
                else
                    buffFrame.glow:Hide()
                    self.lbAuras[buffFrame] = nil
                end
            end
        end
    end)
    self.lbUpdate:Hide()


    print("SotfChecker Loaded. Type /sotf for options.")
end
