local addonName, addon = ...

-- Function to count items in bags
local function GetItemCount(itemId)
    local count = 0
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemLink = C_Container.GetContainerItemLink(bag, slot)
            if itemLink then
                local _, _, itemString = strfind(itemLink, "item:(%d+)")
                if itemString and tonumber(itemString) == itemId then
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info then
                        count = count + info.stackCount
                    end
                end
            end
        end
    end
    return count
end

-- Function to get item name from ID
local function GetItemNameFromID(itemId)
    local itemName = GetItemInfo(itemId)
    return itemName
end

local function SpellIsKnown(spell_id)
    local spellName = GetSpellInfo(spell_id)
    if not spellName then
        return false
    end
    local localized = GetSpellInfo(spellName)
    return localized ~= nil
end

local function HaveMats(spell_id)
    local usable = IsUsableSpell(spell_id)
    return usable
end

local function HasEnchantCursor()
    return (SpellIsTargeting() or CursorHasSpell()) and not CursorHasItem()
end

local function NotifyPlayer(message)
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(message, 1, 0.1, 0.1, 1.0)
    else
        print(message)
    end
end

local function ParseSpellIdFromRecipeLink(recipeLink)
    if not recipeLink then
        return nil
    end

    local enchantId = recipeLink:match("enchant:(%d+)")
    if enchantId then
        return tonumber(enchantId)
    end

    local spellId = recipeLink:match("spell:(%d+)")
    if spellId then
        return tonumber(spellId)
    end

    return nil
end

local function FindTradeSkillIndex(spellID, spellName)
    if not GetNumTradeSkills or not GetTradeSkillInfo then
        return nil
    end

    local numSkills = GetNumTradeSkills()
    if not numSkills or numSkills <= 0 then
        return nil
    end

    for skillIndex = 1, numSkills do
        local recipeName, recipeType = GetTradeSkillInfo(skillIndex)
        if recipeType and recipeType ~= "header" then
            if recipeName and spellName and recipeName == spellName then
                return skillIndex
            end

            if GetTradeSkillRecipeLink and spellID then
                local recipeLink = GetTradeSkillRecipeLink(skillIndex)
                local recipeSpellID = ParseSpellIdFromRecipeLink(recipeLink)
                if recipeSpellID == spellID then
                    return skillIndex
                end
            end
        end
    end

    return nil
end

local function TryDoTradeSkillBySpellID(spellID, spellName)
    if not spellID and not spellName then
        return false
    end

    if DoTradeSkill then
        local skillIndex = FindTradeSkillIndex(spellID, spellName)
        if skillIndex then
            DoTradeSkill(skillIndex, 1)
            return true
        end
    end

    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.CraftRecipe then
        local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
        if recipeIDs then
            for _, recipeID in ipairs(recipeIDs) do
                local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
                if recipeInfo and not recipeInfo.isHeader then
                    if (spellName and recipeInfo.name == spellName) or (spellID and recipeInfo.spellID == spellID) then
                        C_TradeSkillUI.CraftRecipe(recipeID, 1)
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function FindCraftIndex(spellID, spellName)
    if not GetNumCrafts or not GetCraftInfo then
        return nil
    end

    local numCrafts = GetNumCrafts()
    if not numCrafts or numCrafts <= 0 then
        return nil
    end

    for craftIndex = 1, numCrafts do
        local craftName, craftSubSpellName, craftType = GetCraftInfo(craftIndex)
        if craftType and craftType ~= "header" then
            if spellName and (craftName == spellName or craftSubSpellName == spellName) then
                return craftIndex
            end

            if GetCraftRecipeLink and spellID then
                local recipeLink = GetCraftRecipeLink(craftIndex)
                local recipeSpellID = ParseSpellIdFromRecipeLink(recipeLink)
                if recipeSpellID == spellID then
                    return craftIndex
                end
            end
        end
    end

    return nil
end

local function TryDoCraftBySpellID(spellID, spellName)
    if not DoCraft then
        return false
    end

    local craftIndex = FindCraftIndex(spellID, spellName)
    if craftIndex then
        DoCraft(craftIndex, 1)
        return true
    end

    return false
end

local function WaitForEnchantCursor(maxAttempts, interval, onSuccess, onFailure)
    local attempts = 0
    local ticker = nil
    ticker = C_Timer.NewTicker(interval, function()
        attempts = attempts + 1
        if HasEnchantCursor() then
            ticker:Cancel()
            onSuccess()
            return
        end

        if attempts >= maxAttempts then
            ticker:Cancel()
            onFailure()
        end
    end)
end

local function FindCTradeSkillRecipeID(spellID, spellName)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetAllRecipeIDs or not C_TradeSkillUI.GetRecipeInfo then
        return nil
    end

    local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
    if not recipeIDs then
        return nil
    end

    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if recipeInfo and not recipeInfo.isHeader then
            if (spellName and recipeInfo.name == spellName) or (spellID and recipeInfo.spellID == spellID) then
                return recipeID
            end
        end
    end

    return nil
end

-- Create main frame
local function CreateMainFrame()
    local frame = CreateFrame("Frame", "EnchantListFrame", UIParent)
    frame:SetSize(256, 400)
    frame:EnableMouse(false)
    frame:Hide() -- Start hidden
    
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0)
    
    -- Add container for enchant buttons
    frame.enchantContainer = CreateFrame("Frame", nil, frame)
    frame.enchantContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -25)
    frame.enchantContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    
    return frame
end

-- Function to update frame position relative to trade window
local function UpdateFramePosition(frame)
    if TradeFrame and TradeFrame:IsVisible() then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", TradeFrame, "BOTTOMRIGHT", 5, 0)
        frame:Show()
    else
        frame:Hide()
    end
end

-- Create individual essence frame
local function CreateEssenceFrame(parent, essence, index, totalButtons)
    local frame = CreateFrame("Button", "EssenceButton"..index, parent, "SecureActionButtonTemplate")
    frame:SetSize(240, 23)
    -- Calculate position from bottom
    local bottomOffset = 25 * (totalButtons - index)
    frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, bottomOffset)
    
    local itemName = GetItemNameFromID(essence.item_id)
    if not itemName then
        print("Warning: Could not find item info for ID:", essence.item_id)
        return
    end
    
    frame:SetAttribute("type", "item")
    frame:SetAttribute("item", itemName)
    frame:SetAttribute("type1", "item")
    frame:SetAttribute("item1", itemName)
    frame:RegisterForClicks("AnyDown", "AnyUp")
    frame:EnableMouse(true)
    
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0)
    
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", frame, "LEFT", 4, 0)
    icon:SetTexture(essence.icon_id)
    
    local text = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    text:SetText(itemName)
    
    -- Check if it's a split or join based on name
    local isSplit = string.find(essence.name, "split")
    local itemCount = GetItemCount(essence.item_id)
    
    -- Set color based on whether we have enough items
    if (isSplit and itemCount >= 1) or (not isSplit and itemCount >= 3) then
        text:SetTextColor(0, 1, 0)  -- Green if we have enough
    else
        text:SetTextColor(1, 0, 0)  -- Red if we don't
    end
    
    frame:SetScript("OnEnter", function(self)
        bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    end)
    frame:SetScript("OnLeave", function(self)
        bg:SetColorTexture(0.1, 0.1, 0.1, 0)
    end)
    
    return frame
end

-- Create individual enchant frame
local function CreateEnchantFrame(parent, enchant, index, totalButtons)
    local frame = CreateFrame("Button", "EnchantButton"..index, parent, "SecureActionButtonTemplate")
    frame:SetSize(240, 23)
    -- Calculate position from bottom
    local bottomOffset = 25 * (totalButtons - index)
    frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, bottomOffset)
    
    local spellName = enchant.spell_name or GetSpellInfo(enchant.spell_id)
    local spellIcon = enchant.icon_id
    if not spellName then
        print("Warning: Could not find spell info for ID:", enchant.spell_id)
        return
    end

    frame:SetAttribute("type", "macro")
    frame:SetAttribute("macrotext", "/cast " .. spellName)
    frame:SetAttribute("type1", "macro")
    frame:SetAttribute("macrotext1", "/cast " .. spellName)
    frame:RegisterForClicks("AnyDown", "AnyUp")
    
    frame:EnableMouse(true)
    
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0)
    
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", frame, "LEFT", 4, 0)
    icon:SetTexture(spellIcon)
    
    local text = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    text:SetText(spellName)
    text:SetTextColor(0, 1, 0)
    
    frame:SetScript("OnEnter", function(self)
        bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    end)
    frame:SetScript("OnLeave", function(self)
        bg:SetColorTexture(0.1, 0.1, 0.1, 0)
    end)

    frame:HookScript("PostClick", function(self, button, down)
        if down then
            return
        end

        local mappedTradeSkillIndex = enchant.trade_skill_index or FindTradeSkillIndex(enchant.spell_id, spellName)
        local mappedRecipeID = enchant.recipe_id or FindCTradeSkillRecipeID(enchant.spell_id, spellName)
        local mappedCraftIndex = enchant.craft_index or FindCraftIndex(enchant.spell_id, spellName)

        if not HasEnchantCursor() then
            if mappedTradeSkillIndex and DoTradeSkill then
                DoTradeSkill(mappedTradeSkillIndex, 1)
            elseif mappedRecipeID and C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
                C_TradeSkillUI.CraftRecipe(mappedRecipeID, 1)
            elseif mappedCraftIndex and DoCraft then
                DoCraft(mappedCraftIndex, 1)
            else
                local started = TryDoTradeSkillBySpellID(enchant.spell_id, spellName)
                if not started then
                    TryDoCraftBySpellID(enchant.spell_id, spellName)
                end
            end
        end

        WaitForEnchantCursor(8, 0.08,
        function()
                NotifyPlayer("Enchant ready. Click the trade item to apply.")
        end,
        function()
            NotifyPlayer("Could not start enchant cast.")
        end)
    end)
    
    return frame
end

-- Function to clear all enchant buttons
local function ClearEnchantFrames(container)
    if container then
        local child = container:GetChildren()
        while child do
            child:Hide()
            child:SetParent(nil)
            child = container:GetChildren()
        end
    end
end

-- Function to update enchants based on traded item
local function onUpdate(mainFrame)
    UpdateFramePosition(mainFrame)
    -- Always clear existing enchant frames first
    ClearEnchantFrames(mainFrame.enchantContainer)

    -- Get valid enchants for the item
    local validEnchants = {}
    local tItemLink = GetTradeTargetItemLink(7)
    if tItemLink then 
        local itemName, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(tItemLink)
        if itemEquipLoc and EnchantList[itemEquipLoc] then
            for _, enchant in ipairs(EnchantList[itemEquipLoc]) do
                local spellName = GetSpellInfo(enchant.spell_id)
                if spellName and SpellIsKnown(enchant.spell_id) and HaveMats(enchant.spell_id) then
                    local tradeSkillIndex = FindTradeSkillIndex(enchant.spell_id, spellName)
                    local recipeID = FindCTradeSkillRecipeID(enchant.spell_id, spellName)
                    local craftIndex = FindCraftIndex(enchant.spell_id, spellName)
                    table.insert(validEnchants, {
                        spell_id = enchant.spell_id,
                        icon_id = enchant.icon_id,
                        name = enchant.name,
                        spell_name = spellName,
                        trade_skill_index = tradeSkillIndex,
                        recipe_id = recipeID,
                        craft_index = craftIndex,
                    })
                end
            end
        end
    end
    
    -- Get valid essence splits/joins
    local validEssences = {}
    for _, essence in ipairs(EnchantList["ESSENCE"]) do
        local itemCount = GetItemCount(essence.item_id)
        local isSplit = string.find(essence.name, "split")
        
        -- For splits we need at least 1, for joins we need at least 3
        if (isSplit and itemCount >= 1) or (not isSplit and itemCount >= 3) then
            table.insert(validEssences, essence)
        end
    end
    
    -- Create frames for item enchants
    local totalButtons = #validEnchants + #validEssences
    for index, enchant in ipairs(validEnchants) do
        CreateEnchantFrame(mainFrame.enchantContainer, enchant, index, totalButtons)
    end
    
    -- Create frames for essences after enchants
    for index, essence in ipairs(validEssences) do
        CreateEssenceFrame(mainFrame.enchantContainer, essence, index + #validEnchants, totalButtons)
    end
end

-- Initialize everything
local function InitializeAddon()
    local mainFrame = CreateMainFrame()
    return mainFrame
end

-- Event frame for initialization and trade window monitoring
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("TRADE_SHOW")
eventFrame:RegisterEvent("TRADE_CLOSED")
eventFrame:RegisterEvent("TRADE_UPDATE")
eventFrame:RegisterEvent("TRADE_TARGET_ITEM_CHANGED")
eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
eventFrame:RegisterEvent("TRADE_REPLACE_ENCHANT")

local mainFrame = nil

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        mainFrame = InitializeAddon()
    elseif event == "TRADE_SHOW" or event == "TRADE_CLOSED" then
        if mainFrame then
            onUpdate(mainFrame)
        end
    elseif event == "TRADE_UPDATE" or event == "TRADE_TARGET_ITEM_CHANGED" or event == "UNIT_INVENTORY_CHANGED" then
        if mainFrame and mainFrame:IsVisible() then
            onUpdate(mainFrame)
        end
    elseif event == "TRADE_REPLACE_ENCHANT" then
        local e1, e2 = ...
        local tMsg = "Replace " .. e1 .. " with " .. e2 .. "?"
        local tTradePartner = GetUnitName("NPC")
        SendChatMessage(tMsg, "WHISPER", "Common", tTradePartner)
    end
end)
