-- Minimap: minimap button (draggable along the edge) + Addon Compartment entry.
-- Left-click: player · Right-click: library · Shift-click: play/stop · Ctrl-click: settings
local _, ns = ...
local L = ns.L

local MM = {}
ns.Minimap = MM

ns.ICON = "Interface\\Icons\\INV_Misc_Drum_01"
local atan2 = math.atan2 or math.atan
local btn

local function onClick(mouseButton)
  if IsShiftKeyDown and IsShiftKeyDown() then
    ns.Player:Toggle()
  elseif IsControlKeyDown and IsControlKeyDown() then
    ns.Settings:Open()
  elseif mouseButton == "RightButton" then
    ns.LibraryUI:Toggle()
  else
    ns.UI:Toggle()
  end
end

local function showTooltip(owner)
  local lines = { { "Kalimdor ZugZug Radio", 1, 0.5, 0.1 } }
  local P = ns.Player
  if P.track then
    lines[#lines + 1] = (P.playing and L.TT_PLAYING or L.TT_STOPPED) .. ns.TrackLabel(P.track)
  end
  local grey, green = { 0.7, 0.7, 0.7 }, { 0.3, 1, 0.3 }
  local function add(text, color) lines[#lines + 1] = { text, color[1], color[2], color[3] } end
  if not ns.db.enabled then
    add(L.STATUS_RADIO_OFF, grey)
  elseif ns.db.mode == "auto" then
    local key = ns.Rules.current
    add(L.TT_AUTO .. (key and ns.SituationLabel(key) or L.ZONE_MUSIC), grey)
  else
    add(L.TT_FREE .. ns.PlaylistLabel(ns.db.mode), grey)
  end
  lines[#lines + 1] = " "
  add(L.TT_LEFT, green)
  add(L.TT_RIGHT, green)
  add(L.TT_SHIFT, green)
  add(L.TT_CTRL, green)
  add(L.TT_DRAG, green)
  ns.ShowTooltip(owner, "ANCHOR_LEFT", lines)
end

local function updatePosition()
  local angle = math.rad(ns.db.minimap.angle or 225)
  local radius = (Minimap:GetWidth() / 2) + 10
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function dragUpdate()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  ns.db.minimap.angle = math.deg(atan2(py / scale - my, px / scale - mx)) % 360
  updatePosition()
end

function MM:Build()
  if btn or not Minimap then return end
  btn = CreateFrame("Button", "KalimdorZugZugRadioMinimapButton", Minimap)
  btn:SetSize(31, 31)
  -- above the minimap and its borders, whatever level they have on this client
  btn:SetFrameStrata(Minimap:GetFrameStrata() == "BACKGROUND" and "LOW" or Minimap:GetFrameStrata())
  btn:SetFrameLevel(math.max(8, Minimap:GetFrameLevel() + 10))
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)

  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ns.ICON)
  icon:SetSize(17, 17)
  icon:SetPoint("TOPLEFT", 7, -6)
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  btn.icon = icon

  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  btn:SetScript("OnClick", function(_, mouseButton) onClick(mouseButton) end)
  btn:SetScript("OnEnter", showTooltip)
  btn:SetScript("OnLeave", ns.HideTooltip)
  btn:SetScript("OnDragStart", function(self)
    ns.HideTooltip()
    self:SetScript("OnUpdate", dragUpdate)
  end)
  btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  -- greyed-out icon when the radio is silent
  ns.On("STATE_CHANGED", function() icon:SetDesaturated(not ns.Player.playing) end)
  icon:SetDesaturated(true)

  updatePosition()
  btn:SetShown(not ns.db.minimap.hide)
end

function MM:DebugInfo()
  if not btn then return "button not created" end
  local function c(f)
    local x, y = f:GetCenter()
    return ("%s,%s"):format(x and math.floor(x) or "?", y and math.floor(y) or "?")
  end
  return ("button center %s strata %s level %d alpha %.2f | Minimap center %s size %dx%d strata %s level %d scale %.2f shape %s"):format(
    c(btn), btn:GetFrameStrata(), btn:GetFrameLevel(), btn:GetEffectiveAlpha(),
    c(Minimap), Minimap:GetWidth(), Minimap:GetHeight(), Minimap:GetFrameStrata(), Minimap:GetFrameLevel(),
    Minimap:GetEffectiveScale(), tostring(GetMinimapShape and GetMinimapShape() or "ROUND"))
end

function MM:SetShown(show)
  ns.db.minimap.hide = not show
  if btn then btn:SetShown(show) end
  ns.Fire("SETTINGS_CHANGED")
end

function MM:Toggle()
  self:SetShown(ns.db.minimap.hide)
  ns.Print(ns.db.minimap.hide and "MSG_MINIMAP_HIDDEN" or "MSG_MINIMAP_SHOWN")
end

-- Addon Compartment (the minimap addon menu in the modern client), declared in the .toc.
function KZZR_OnCompartmentClick(_, mouseButton) onClick(mouseButton) end
function KZZR_OnCompartmentEnter(_, frame) showTooltip(frame) end
function KZZR_OnCompartmentLeave() ns.HideTooltip() end
