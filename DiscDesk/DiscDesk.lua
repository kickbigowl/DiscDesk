local ru = GetLocale() == "ruRU"
local function tr(en, russian)
    return ru and russian or en
end
local function restricted(value)
    return issecretvalue and issecretvalue(value)
end
local function bar(parent)
    local f = CreateFrame("StatusBar", nil, parent)
    f:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(.08, .09, .12, .95)
    return f
end
local function label(f)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("CENTER")
    return t
end
local header = CreateFrame("Frame", nil, UIParent)
header:SetSize(156, 17)
header:SetMovable(true)
header:SetClampedToScreen(true)
header:EnableMouse(true)
header:RegisterForDrag("LeftButton")
local mana = bar(header)
mana:SetAllPoints()
local manaText = label(mana)
local rows = {}
local function restore()
    header:ClearAllPoints()
    local p = DiscDeskPosition
    if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
        header:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
    else
        header:SetPoint("CENTER", UIParent, "CENTER", 0, -78)
    end
end
header:SetScript("OnDragStart", function()
    if not InCombatLockdown() then header:StartMoving() end
end)
header:SetScript("OnDragStop", function()
    header:StopMovingOrSizing()
    local x, y = header:GetCenter()
    local cx, cy = UIParent:GetCenter()
    DiscDeskPosition = {x = x - cx, y = y - cy}
end)
local timer = bar(header)
timer:SetSize(156, 16)
timer:SetPoint("BOTTOM", header, "TOP", 0, 2)
timer:SetMinMaxValues(0, 5)
timer:SetStatusBarColor(.12, .52, .70)
local timerText = label(timer)
local previousMana, previousMax, deadline
local function drawTimer()
    if not previousMana then
        timer:SetValue(0)
        timerText:SetText(tr("5 sec: unavailable", "5 с: нет данных"))
        return
    end
    local left = math.max(0, (deadline or 0) - GetTime())
    timer:SetValue(left)
    if left > 0 then
        timerText:SetFormattedText(tr("Regen in %.1f", "До регена %.1f с"), left)
    else
        timerText:SetText(tr("Full regen", "Полный реген"))
    end
end
local elapsed = 0
timer:SetScript("OnUpdate", function(_, dt)
    if deadline then
        elapsed = elapsed + dt
        if elapsed >= .1 then
            elapsed = 0
            drawTimer()
            if GetTime() >= deadline then deadline = nil end
        end
    end
end)
local function updateMana()
    local current, maximum = UnitPower("player", 0), UnitPowerMax("player", 0)
    mana:SetMinMaxValues(0, maximum)
    mana:SetValue(current)
    local title = tr("Mana", "Мана")
    mana:SetStatusBarColor(.1, .38, .78)
    if restricted(current) or restricted(maximum) or maximum <= 0 then
        previousMana, previousMax, deadline = nil, nil, nil
        drawTimer()
        manaText:SetText(title)
        return
    end
    if previousMax == maximum and previousMana and current < previousMana then
        deadline = GetTime() + 5
    end
    previousMana, previousMax = current, maximum
    drawTimer()
    local percent = math.floor(100 * current / maximum + .5)
    if percent <= 25 then mana:SetStatusBarColor(.76, .18, .15) end
    manaText:SetFormattedText("%s  %d%%", title, percent)
end
local group, visibilityPending
local function updateHealth(row)
    local hp, maximum = UnitHealth(row.unit), UnitHealthMax(row.unit)
    row.bar:SetMinMaxValues(0, maximum)
    row.bar:SetValue(hp)
    local shield
    if UnitGetTotalAbsorbs then shield = UnitGetTotalAbsorbs(row.unit) end
    if restricted(shield) or type(shield) ~= "number" then shield = nil end
    local readable = not restricted(hp) and not restricted(maximum)
    if DiscDeskOptions.numbers and readable then
        row.numbers:SetFormattedText("%d+%s/%d", hp, shield and tostring(shield) or "?", maximum)
    else
        row.numbers:SetText("")
    end
    -- A separate thin strip stays visible even when health is full.
    if shield and readable and maximum > 0 and shield > 0 then
        row.absorb:SetWidth(math.max(1, row.bar:GetWidth() * math.min(1, shield / maximum)))
        row.absorb:Show()
    else
        row.absorb:Hide()
    end
end
local function refreshRows()
    for _, row in ipairs(rows) do
        if UnitExists(row.unit) then
            updateHealth(row)
            row.name:SetText(UnitName(row.unit))
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(row.unit)
            if not restricted(role) and (role == "TANK" or role == "HEALER" or role == "DAMAGER") then
                row.role:SetTexture("Interface\\AddOns\\DiscDesk\\roles\\" .. role)
                row.role:Show()
            else
                row.role:Hide()
            end
        end
    end
end
local function spellName(id, en, russian)
    return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or tr(en, russian)
end
local function bind(button, key, click, name)
    button:SetAttribute(key .. "type" .. click, "spell")
    button:SetAttribute(key .. "spell" .. click, name)
end
local spells = {
    {17, "Power Word: Shield", "Слово силы: Щит", "PowerWordShield"},
    {139, "Renew", "Обновление", "Renew"},
    {2050, "Lesser Heal", "Малое исцеление", "LesserHeal"},
    {2061, "Flash Heal", "Быстрое исцеление", "FlashHeal"},
    {2054, "Heal", "Исцеление", "Heal"},
}
local auraRows = {}
local shieldDebuff = spellName(6788, "Weakened Soul", "Ослабленная душа")
local renewBuff = spellName(139, "Renew", "Обновление")
local function hasAura(unit, filter, wanted)
    local index = 1
    while true do
        local name
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
            if restricted(aura) or not aura then return false end
            name = aura.name
        elseif UnitAura then
            name = UnitAura(unit, index, filter)
        else
            return false
        end
        if not restricted(name) then
            if not name then return false end
            if name == wanted then return true end
        end
        index = index + 1
    end
end
local function refreshAuras(unit, textures)
    local exists = UnitExists(unit)
    local shield = exists and hasAura(unit, "HARMFUL", shieldDebuff)
    local renew = exists and hasAura(unit, "HELPFUL", renewBuff)
    local shieldLight = shield and .32 or 1
    local renewLight = renew and .32 or 1
    textures[1]:SetVertexColor(shieldLight, shieldLight, shieldLight)
    textures[2]:SetVertexColor(renewLight, renewLight, renewLight)
end
local function refreshPartyAuras()
    for unit, textures in pairs(auraRows) do refreshAuras(unit, textures) end
end
local function addSpellButtons(parent, unit)
    local textures = {}
    auraRows[unit] = textures
    for index, spell in ipairs(spells) do
        local name = spellName(spell[1], spell[2], spell[3])
        local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
        button:SetSize(24, 24)
        button:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", (index-1)*26, -3)
        button:SetAttribute("unit", unit)
        bind(button, "", "1", name)
        button:RegisterForClicks("AnyDown", "AnyUp")
        button:SetNormalTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell[1]))
            or ("Interface\\Icons\\Spell_Holy_" .. spell[4]))
        if index <= 2 then textures[index] = button:GetNormalTexture() end
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(name)
            GameTooltip:AddLine(UnitName(unit), 1, 1, 1)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
end
local function applyVisibility()
    if not InCombatLockdown() then group:SetShown(DiscDeskOptions.visible) end
end
local function bindVisibilityToggle(button)
    button:SetFrameRef("party", group)
    button:SetAttribute("_onclick", [[
        if button == "LeftButton" then
            local party = self:GetFrameRef("party")
            if party:IsShown() then party:Hide() else party:Show() end
        end
    ]])
end
local function makePanel(parent, width, height)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(width, height)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(.06, .07, .10, .97)
    panel:Hide()
    return panel
end
local function menuItem(panel, y, title, action)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", 6, y)
    b:SetSize(panel:GetWidth()-12, 25)
    b:SetText(title)
    b:HookScript("OnClick", action)
    return b
end
local layoutPending, anchor, handle, syncSettings
local slots = {"player", "party1", "party2", "party3", "party4"}
-- This snippet also runs when the party changes during combat.
local arrange = [[
    local count = tonumber(self:GetAttribute("state-count")) or 1
    local visible = 0
    local vertical = self:GetAttribute("vertical")
    for i = 1, 5 do
        local slot = self:GetAttribute("slot"..i)
        if slot <= count and (slot ~= 1 or self:GetAttribute("includePlayer")) then
            local frame = self:GetFrameRef("unit"..slot)
            frame:ClearAllPoints()
            if vertical then
                frame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -visible*74)
            else
                frame:SetPoint("TOPLEFT", self, "TOPLEFT", visible*134, 0)
            end
            visible = visible + 1
        end
    end
    if self:GetAttribute("includePlayer") then
        self:GetFrameRef("unit1"):Show()
    else
        self:GetFrameRef("unit1"):Hide()
    end
    self:SetWidth((vertical or visible == 0) and 128 or visible*134-6)
]]
local function applyLayout()
    if InCombatLockdown() then
        layoutPending = true
        return
    end
    layoutPending = nil
    for i, slot in ipairs(DiscDeskOptions.order) do group:SetAttribute("slot"..i, slot) end
    group:SetAttribute("includePlayer", DiscDeskOptions.includePlayer)
    group:SetAttribute("vertical", DiscDeskOptions.vertical)
    group:Execute(arrange)
end
local function placeAnchor()
    anchor:ClearAllPoints()
    anchor:SetPoint("TOP", header, "BOTTOM", DiscDeskOptions.x or 0, DiscDeskOptions.y or -10)
end
local function setupAnchor()
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetSize(128, 20)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    placeAnchor()
    handle = CreateFrame("Button", nil, anchor, "UIPanelButtonTemplate")
    handle:SetSize(190,24)
    handle:SetPoint("BOTTOM", anchor, "TOP")
    handle:SetText(tr("Drag the HP panel", "Перетащи панель ХП"))
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        if not InCombatLockdown() then anchor:StartMoving() end
    end)
    handle:SetScript("OnDragStop", function()
        anchor:StopMovingOrSizing()
        if not InCombatLockdown() then
            local x = anchor:GetCenter()
            local hx = header:GetCenter()
            DiscDeskOptions.x = x - hx
            DiscDeskOptions.y = anchor:GetTop() - header:GetBottom()
            placeAnchor()
        end
        handle:Hide()
    end)
    handle:Hide()
end
local function setupMinimap()
    local icon = CreateFrame("Button", "DiscDeskMinimapButton", Minimap, "SecureHandlerClickTemplate")
    icon:SetSize(32,32)
    icon:SetFrameStrata("MEDIUM")
    icon:SetFrameLevel(Minimap:GetFrameLevel()+8)
    icon:SetPoint("CENTER", Minimap, "CENTER", -Minimap:GetWidth()*.36, -Minimap:GetHeight()*.36)
    icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bindVisibilityToggle(icon)
    local art = icon:CreateTexture(nil, "ARTWORK")
    art:SetPoint("CENTER")
    art:SetSize(24,24)
    art:SetTexture("Interface\\Icons\\Spell_Holy_PowerWordShield")
    local border = icon:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54,54)
    border:SetPoint("TOPLEFT", 0, 0)
    local menu = makePanel(UIParent, 194, 66)
    menu:SetPoint("TOPRIGHT", icon, "BOTTOMLEFT")
    local settings = makePanel(UIParent, 284, 388)
    settings:SetPoint("CENTER")
    local title = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText(tr("DiscDesk settings", "Настройки DiscDesk"))
    local function toggleOption(key)
        DiscDeskOptions[key] = not DiscDeskOptions[key]
        applyLayout()
        syncSettings()
    end
    local values = menuItem(settings, -30, "", function()
        DiscDeskOptions.numbers = not DiscDeskOptions.numbers
        refreshRows()
        syncSettings()
    end)
    local own = menuItem(settings, -57, "", function() toggleOption("includePlayer") end)
    local orientation = menuItem(settings, -84, "", function() toggleOption("vertical") end)
    local heading = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOP", 0, -117)
    heading:SetText(tr("Party frame order", "Порядок полос"))
    local labels = {}
    local function swap(index, step)
        local target = index + step
        local order = DiscDeskOptions.order
        if target < 1 or target > 5 then return end
        order[index], order[target] = order[target], order[index]
        applyLayout()
        syncSettings()
    end
    for i = 1, 5 do
        local index, y = i, -135-(i-1)*26
        local line = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        labels[i] = line
        line:SetPoint("TOPLEFT", 12, y-4)
        line:SetWidth(175)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        for _, step in ipairs({-1,1}) do
            local delta = step
            local arrow = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
            arrow:SetSize(40,24)
            arrow:SetPoint("TOPRIGHT", delta == -1 and -49 or -6, y)
            arrow:SetText(delta == -1 and "▲" or "▼")
            arrow:SetEnabled(index+delta >= 1 and index+delta <= 5)
            arrow:SetScript("OnClick", function() swap(index, delta) end)
        end
    end
    local function onOff(value)
        return value and tr("On", "вкл.") or tr("Off", "выкл.")
    end
    syncSettings = function()
        values:SetText(tr("HP numbers: ", "Цифры ХП: ") .. onOff(DiscDeskOptions.numbers))
        own:SetText(tr("Show myself: ", "Показывать себя: ") .. onOff(DiscDeskOptions.includePlayer))
        orientation:SetText(DiscDeskOptions.vertical and tr("Layout: column", "Расположение: столбец")
            or tr("Layout: row", "Расположение: строка"))
        for i, slot in ipairs(DiscDeskOptions.order) do
            local unit = slots[slot]
            local nm = UnitName(unit)
            local fallback = slot == 1 and tr("You", "Ты") or tr("Party slot ", "Место группы ") .. (slot-1)
            if not restricted(nm) and nm then fallback = nm end
            labels[i]:SetText(i .. ". " .. fallback)
        end
    end
    settings:HookScript("OnShow", syncSettings)
    menuItem(settings, -271, tr("Move HP panel", "Переместить панель ХП"), function()
        if InCombatLockdown() then print(tr("Move after combat.", "Перемещение доступно после боя.")) return end
        settings:Hide()
        handle:Show()
    end)
    menuItem(settings, -298, tr("Reset panel position", "Сбросить положение панели"), function()
        if InCombatLockdown() then print(tr("Move after combat.", "Перемещение доступно после боя.")) return end
        DiscDeskOptions.x, DiscDeskOptions.y = nil, nil
        placeAnchor()
        handle:Hide()
    end)
    menuItem(settings, -350, tr("Close", "Закрыть"), function() settings:Hide() end)
    menuItem(menu, -35, tr("Settings", "Настройки"), function()
        menu:Hide()
        settings:Show()
    end)
    local visibility = menuItem(menu, -5, "", function()
        menu:Hide()
        DiscDeskOptions.visible = not DiscDeskOptions.visible
        if InCombatLockdown() then
            visibilityPending = true
            print(tr("DiscDesk: visibility will change after combat.", "DiscDesk: видимость изменится после боя."))
        else
            applyVisibility()
        end
    end)
    icon:HookScript("OnClick", function(_, button)
        if button == "RightButton" then
            visibility:SetText(DiscDeskOptions.visible and tr("Hide HP bars", "Скрыть полосы ХП")
                or tr("Show HP bars", "Показать полосы ХП"))
            menu:SetShown(not menu:IsShown())
        else
            menu:Hide()
            visibilityPending = nil
            DiscDeskOptions.visible = group:IsShown()
        end
    end)
    icon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("DiscDesk")
        GameTooltip:AddLine(tr("Left: toggle HP bars", "ЛКМ: показать / скрыть ХП"),1,1,1)
        GameTooltip:AddLine(tr("Right: menu", "ПКМ: меню"),1,1,1)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
local function setup()
    DiscDeskOptions = DiscDeskOptions or {}
    if DiscDeskOptions.visible == nil then DiscDeskOptions.visible = true end
    if DiscDeskOptions.numbers == nil then DiscDeskOptions.numbers = true end
    if DiscDeskOptions.includePlayer == nil then DiscDeskOptions.includePlayer = true end
    DiscDeskOptions.order = DiscDeskOptions.order or {1,2,3,4,5}
    restore()
    setupAnchor()
    group = CreateFrame("Frame", nil, header, "SecureHandlerStateTemplate")
    group:SetPoint("TOP", anchor, "TOP")
    group:SetSize(128, 42)
    for i, unit in ipairs(slots) do
        local b = CreateFrame("Button", "DiscDeskUnit" .. i, group, "SecureActionButtonTemplate")
        b:SetSize(128, 42)
        b:SetPoint("TOPLEFT", group, "TOPLEFT", (i-1)*134, 0)
        b:SetAttribute("unit", unit)
        b:RegisterForClicks("AnyDown", "AnyUp")
        bind(b, "", "1", spellName(2054, "Heal", "Исцеление"))
        bind(b, "", "2", spellName(17, "Power Word: Shield", "Слово силы: Щит"))
        bind(b, "shift-", "1", spellName(2061, "Flash Heal", "Быстрое исцеление"))
        bind(b, "shift-", "2", spellName(1240720, "Penance", "Исповедь"))
        local hp = bar(b)
        hp:SetAllPoints()
        hp:SetStatusBarColor(.12, .47, .30)
        local role = hp:CreateTexture(nil, "OVERLAY")
        role:SetSize(17,17)
        role:SetPoint("LEFT", 3, 0)
        local name = label(hp)
        name:ClearAllPoints()
        name:SetPoint("TOPLEFT", hp, "TOPLEFT", 22, -3)
        name:SetWidth(102)
        name:SetWordWrap(false)
        local numbers = hp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        numbers:SetPoint("BOTTOM", 0, 6)
        local absorb = hp:CreateTexture(nil, "OVERLAY")
        absorb:SetPoint("BOTTOMLEFT")
        absorb:SetHeight(3)
        absorb:SetColorTexture(.35, .82, 1, 1)
        rows[i] = {unit = unit, bar = hp, name = name, role = role, numbers = numbers, absorb = absorb}
        addSpellButtons(b, unit)
        group:SetFrameRef("unit"..i, b)
        if i > 1 then RegisterUnitWatch(b) end
    end
    applyLayout()
    group:SetAttribute("_onstate-count", arrange)
    RegisterStateDriver(group, "count", "[@party4,exists] 5; [@party3,exists] 4; [@party2,exists] 3; [@party1,exists] 2; 1")
    applyVisibility()
    setupMinimap()
    refreshRows()
    refreshPartyAuras()
    updateMana()
end
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        if select(2, UnitClass("player")) ~= "PRIEST" then header:Hide() return end
        setup()
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        if UnitGetTotalAbsorbs then self:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED") end
        for _, name in ipairs({"GROUP_ROSTER_UPDATE","PLAYER_ROLES_ASSIGNED","PLAYER_ENTERING_WORLD","UNIT_HEALTH",
            "UNIT_AURA","UNIT_MAXHEALTH","UNIT_NAME_UPDATE","UNIT_POWER_UPDATE","UNIT_MAXPOWER"}) do
            self:RegisterEvent(name)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if layoutPending then applyLayout() end
        if visibilityPending then applyVisibility() visibilityPending = nil end
    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        for _, row in ipairs(rows) do
            if row.unit == unit and UnitExists(unit) then updateHealth(row) break end
        end
    elseif event == "UNIT_AURA" then
        if auraRows[unit] then refreshAuras(unit, auraRows[unit]) end
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        if unit == "player" then updateMana() end
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_NAME_UPDATE" then
        if unit == "player" or (unit and unit:match("^party[1-4]$")) then refreshRows() end
    else
        if syncSettings then syncSettings() end
        refreshRows()
        refreshPartyAuras()
        updateMana()
    end
end)
SLASH_DISCDESK1 = "/discdesk"
SlashCmdList.DISCDESK = function(msg)
    if msg == "reset" and not InCombatLockdown() then
        DiscDeskPosition = nil
        restore()
    else
        print(tr("DiscDesk: Left Heal / Right Shield / Shift-Left Flash Heal / Shift-Right Penance. Drag mana bar outside combat. /discdesk reset",
            "DiscDesk: ЛКМ Исцеление / ПКМ Щит / Shift-ЛКМ Быстрое исцеление / Shift-ПКМ Исповедь. Вне боя перетащи полосу маны. /discdesk reset"))
    end
end
