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
local function refreshRows()
    for _, row in ipairs(rows) do
        if UnitExists(row.unit) then
            row.bar:SetMinMaxValues(0, UnitHealthMax(row.unit))
            row.bar:SetValue(UnitHealth(row.unit))
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
local function setup()
    restore()
    for i, unit in ipairs({"player", "party1", "party2", "party3", "party4"}) do
        local b = CreateFrame("Button", "DiscDeskUnit" .. i, header, "SecureActionButtonTemplate")
        b:SetSize(128, 28)
        b:SetPoint("TOP", header, "BOTTOM", (i-3)*134, -10)
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
        name:SetPoint("LEFT", hp, "LEFT", 22, 0)
        name:SetPoint("RIGHT", hp, "RIGHT", -3, 0)
        name:SetWordWrap(false)
        rows[i] = {unit = unit, bar = hp, name = name, role = role}
        addSpellButtons(b, unit)
        RegisterUnitWatch(b)
    end
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
        for _, name in ipairs({"GROUP_ROSTER_UPDATE","PLAYER_ROLES_ASSIGNED","PLAYER_ENTERING_WORLD","UNIT_HEALTH",
            "UNIT_AURA","UNIT_MAXHEALTH","UNIT_NAME_UPDATE","UNIT_POWER_UPDATE","UNIT_MAXPOWER"}) do
            self:RegisterEvent(name)
        end
    elseif event == "UNIT_AURA" then
        if auraRows[unit] then refreshAuras(unit, auraRows[unit]) end
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        if unit == "player" then updateMana() end
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_NAME_UPDATE" then
        if unit == "player" or (unit and unit:match("^party[1-4]$")) then refreshRows() end
    else
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
