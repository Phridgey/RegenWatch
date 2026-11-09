-- RegenWatch: your own health regeneration.
-- Every rise in your health is collected into a "tick" (the game regenerates every
-- 2 seconds). Heals, potions, bandages and food that show in the combat log are
-- taken off, so what is left is natural regeneration.
--   /regen        show or hide the number (shift-drag it to move; hover for averages)
--   /regen reset  start counting again

local getn, format, floor, max, find = table.getn, string.format, math.floor, math.max, string.find

RegenWatchDB = RegenWatchDB or {}

local lastHP, lastMax          -- your health as last seen
local bucket                   -- {start, last, amount, capped} rises being collected into one tick
local credits = {}             -- {time, amount} heals seen in the combat log
local ignoreUntil = 0          -- just after a max-health change or resurrection
local stats                    -- running totals, see reset()

local function reset()
  stats = {
    total = 0,
    ooc = { ticks = 0, sum = 0, best = 0 },
    ic = { ticks = 0, sum = 0, best = 0 },
    last = nil, lastInCombat = nil, lastAt = nil,
    started = GetTime(),
  }
end
reset()

-- Heals on you, from the combat log -------------------------------------------------------
local HEAL_PATTERNS = {
  "heals you for (%d+)",          -- "Bob's Heal heals you for 500." / "Your Heal critically heals you for 700."
  "^You gain (%d+) health",       -- "You gain 61 health from Food." / bandages, potions over time, Renew
}
local function onHealMessage(msg)
  if not msg then return end
  for i = 1, getn(HEAL_PATTERNS) do
    local _, _, n = find(msg, HEAL_PATTERNS[i])
    if n then tinsert(credits, { GetTime(), tonumber(n) }); return end
  end
end

-- Takes heals seen around a tick off it; heals older than 2s are dropped.
local function healsNear(t0, t1)
  local now, used, i = GetTime(), 0, 1
  while i <= getn(credits) do
    local c = credits[i]
    if c[1] >= t0 - .7 and c[1] <= t1 + .7 then used = used + c[2]; tremove(credits, i)
    elseif now - c[1] > 2 then tremove(credits, i)
    else i = i + 1 end
  end
  return used
end

-- A tick is finished once health has stopped rising for half a second.
local function finishTick()
  local b = bucket
  bucket = nil
  local regen = b.amount - healsNear(b.start, b.last)
  if regen <= 0 then return end
  local inCombat = UnitAffectingCombat("player")
  stats.total = stats.total + regen
  stats.last, stats.lastInCombat, stats.lastAt = floor(regen + .5), inCombat, b.last
  -- a tick that reached full health was cut short, so it doesn't count toward averages
  if b.capped then return end
  local s = inCombat and stats.ic or stats.ooc
  s.ticks = s.ticks + 1
  s.sum = s.sum + regen
  if regen > s.best then s.best = regen end
end

local function onHealth()
  local hp, mx = UnitHealth("player"), UnitHealthMax("player")
  local now = GetTime()
  if UnitIsDeadOrGhost("player") or mx ~= lastMax or now < ignoreUntil or not lastHP or lastHP <= 0 then
    lastHP, lastMax = hp, mx
    return
  end
  local delta = hp - lastHP
  lastHP = hp
  if delta <= 0 then return end
  if bucket and now - bucket.last > .5 then finishTick() end
  bucket = bucket or { start = now, amount = 0 }
  bucket.last = now
  bucket.amount = bucket.amount + delta
  if hp >= mx then bucket.capped = true end
end

-- On-screen number -----------------------------------------------------------------------
-- One number: the health your last regeneration tick gave (ticks are every 2s).
-- Greyed out when no tick has come for a while (full health, or regen stopped).
local f = CreateFrame("Frame", "RegenWatchFrame", UIParent)
f:SetWidth(110); f:SetHeight(26)
f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton"); f:SetClampedToScreen(true)
f:SetScript("OnDragStart", function() if IsShiftKeyDown() then this:StartMoving() end end)
f:SetScript("OnDragStop", function()
  this:StopMovingOrSizing()
  RegenWatchDB.x, RegenWatchDB.y = this:GetLeft(), this:GetTop()
end)
f:SetScript("OnEnter", function()
  GameTooltip:SetOwner(this, "ANCHOR_TOP")
  GameTooltip:SetText("Regen per tick (every 2s)", 1, 1, 1)
  local o, c = stats.ooc, stats.ic
  if o.ticks > 0 then GameTooltip:AddDoubleLine("Out of combat, average", format("%d  (%.1f/s)", floor(o.sum / o.ticks + .5), o.sum / o.ticks / 2)) end
  if c.ticks > 0 then GameTooltip:AddDoubleLine("In combat, average", format("%d  (%.1f/s)", floor(c.sum / c.ticks + .5), c.sum / c.ticks / 2)) end
  GameTooltip:AddLine("Shift-drag to move", .6, .6, .6)
  GameTooltip:Show()
end)
f:SetScript("OnLeave", function() GameTooltip:Hide() end)

local num = f:CreateFontString(nil, "OVERLAY")
num:SetFont("Fonts\\ARIALN.TTF", 20, "OUTLINE")
num:SetPoint("RIGHT", f, "CENTER", 4, 0)
local unit = f:CreateFontString(nil, "OVERLAY")
unit:SetFont("Fonts\\ARIALN.TTF", 11, "OUTLINE")
unit:SetPoint("LEFT", num, "RIGHT", 3, -2)
unit:SetText("regen")

local function paint()
  if not stats.last then num:SetText("–"); num:SetTextColor(.6, .6, .6); return end
  num:SetText("+"..stats.last)
  if GetTime() - stats.lastAt > 6 then num:SetTextColor(.55, .58, .62)       -- nothing lately
  elseif stats.lastInCombat then num:SetTextColor(1, .75, .3)                   -- in combat
  else num:SetTextColor(.3, 1, .45) end
end

local elapsed = 0
f:SetScript("OnUpdate", function()
  elapsed = elapsed + arg1
  if bucket and GetTime() - bucket.last > .5 then finishTick() end
  if elapsed < .25 then return end
  elapsed = 0
  paint()
end)

-- Events ----------------------------------------------------------------------------------
local HEAL_EVENTS = {
  "CHAT_MSG_SPELL_SELF_BUFF", "CHAT_MSG_SPELL_PARTY_BUFF", "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
  "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF", "CHAT_MSG_SPELL_CREATURE_VS_PARTY_BUFF",
  "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS", "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS",
  "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS", "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS",
  "CHAT_MSG_SPELL_SELF_DAMAGE",   -- drains and leeches that heal you
}
local ev = CreateFrame("Frame")
ev:RegisterEvent("VARIABLES_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("UNIT_HEALTH")
ev:RegisterEvent("UNIT_MAXHEALTH")
ev:RegisterEvent("PLAYER_ALIVE")
ev:RegisterEvent("PLAYER_UNGHOST")
for i = 1, getn(HEAL_EVENTS) do ev:RegisterEvent(HEAL_EVENTS[i]) end
ev:SetScript("OnEvent", function()
  if event == "UNIT_HEALTH" then
    if arg1 == "player" then onHealth() end
  elseif event == "UNIT_MAXHEALTH" then
    if arg1 == "player" then ignoreUntil = GetTime() + .3; lastHP, lastMax = UnitHealth("player"), UnitHealthMax("player") end
  elseif event == "VARIABLES_LOADED" then
    if RegenWatchDB.x then f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", RegenWatchDB.x, RegenWatchDB.y)
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, -120) end
    if RegenWatchDB.hidden then f:Hide() end
  elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
    ignoreUntil = GetTime() + 1; lastHP, lastMax = UnitHealth("player"), UnitHealthMax("player")
  else
    onHealMessage(arg1)
  end
end)

SLASH_REGENWATCH1 = "/regen"
SLASH_REGENWATCH2 = "/regenwatch"
SlashCmdList["REGENWATCH"] = function(msg)
  if msg == "reset" then reset(); DEFAULT_CHAT_FRAME:AddMessage("|cff33d6b0RegenWatch|r: counting from now.")
  elseif f:IsShown() then f:Hide(); RegenWatchDB.hidden = true
  else f:Show(); RegenWatchDB.hidden = nil end
end
