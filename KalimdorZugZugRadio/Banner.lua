-- Banner: "Now playing" toast above the chat window when a new track starts.
local _, ns = ...
local L = ns.L

local B = {}
ns.Banner = B

local SHOW_TIME, FADE_TIME = 4, 0.4
local f, lastTrack, hideTimer, moving, dragged

-- db.ui.bannerPos = {point, relPoint, x, y} once the user has moved it; nil = above the chat
local function anchor()
  f:ClearAllPoints()
  local pos = ns.db.ui.bannerPos
  if pos then
    f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    return
  end
  local chat = _G.ChatFrame1 or _G.DEFAULT_CHAT_FRAME
  if chat and chat.IsShown and chat:IsShown() then
    f:SetPoint("BOTTOMLEFT", chat, "TOPLEFT", -4, 28) -- above the chat tabs
  else
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 220)
  end
end

function B:Build()
  if f then return end
  f = CreateFrame("Frame", "KalimdorZugZugRadioBanner", UIParent, "BackdropTemplate")
  f:SetSize(300, 52)
  f:SetFrameStrata("MEDIUM")
  f:EnableMouse(false) -- never blocks clicks on the chat (only while being moved)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if moving then dragged = true self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    ns.db.ui.bannerPos = { point, relPoint, x, y }
  end)
  f:SetScript("OnMouseUp", function(_, button)
    if not moving then return end
    if button == "RightButton" then
      ns.db.ui.bannerPos = nil
      anchor()
    elseif not dragged then
      B:SetMoving(false) -- a plain click ends the move mode
    end
    dragged = false
  end)
  f:Hide()

  f.cover = f:CreateTexture(nil, "ARTWORK")
  f.cover:SetSize(38, 38)
  f.cover:SetPoint("LEFT", 8, 0)

  f.label = f:CreateFontString(nil, "OVERLAY", ns.Font("GameFontNormalSmall"))
  f.label:SetPoint("TOPLEFT", f.cover, "TOPRIGHT", 8, -1)
  f.label:SetText(L.NOW_PLAYING)

  f.title = f:CreateFontString(nil, "OVERLAY", ns.Font("GameFontHighlight"))
  f.title:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -2)
  f.title:SetWidth(240)
  f.title:SetJustifyH("LEFT")
  f.title:SetWordWrap(false)

  f.artist = f:CreateFontString(nil, "OVERLAY", ns.Font("GameFontDisableSmall"))
  f.artist:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -1)
  f.artist:SetWidth(240)
  f.artist:SetJustifyH("LEFT")
  f.artist:SetWordWrap(false)

  -- fade in / out with animation groups
  f.fadeIn = f:CreateAnimationGroup()
  local a = f.fadeIn:CreateAnimation("Alpha")
  a:SetFromAlpha(0) a:SetToAlpha(1) a:SetDuration(FADE_TIME)
  f.fadeIn:SetScript("OnPlay", function() f:SetAlpha(0) f:Show() end)
  f.fadeIn:SetScript("OnFinished", function() f:SetAlpha(1) end)
  f.fadeOut = f:CreateAnimationGroup()
  local b = f.fadeOut:CreateAnimation("Alpha")
  b:SetFromAlpha(1) b:SetToAlpha(0) b:SetDuration(FADE_TIME)
  f.fadeOut:SetScript("OnFinished", function() f:Hide() end)

  ns.On("TRACK_CHANGED", function(track) B:OnTrack(track) end)
  ns.On("SETTINGS_CHANGED", function() ns.SkinToast(f) end)
  ns.SkinToast(f)
end

function B:OnTrack(track)
  -- podcasts fire TRACK_CHANGED for every part: only announce a new track
  if not track or track == lastTrack or not ns.Player.playing then return end
  lastTrack = track
  if not ns.db.ui.banner then return end
  self:Show(track)
end

local function fill(track)
  f.cover:SetTexture(track and ns.CoverOf(track) or ns.DEFAULT_COVER)
  ns.SetText(f.title, track and track.title or "Kalimdor ZugZug Radio", "GameFontHighlight")
  if moving then
    f.artist:SetFontObject(ns.Font("GameFontDisableSmall"))
    f.artist:SetText(L.BANNER_MOVE_HINT)
    f.artist:SetTextColor(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3])
  else
    ns.SetText(f.artist, track and track.artist or "", "GameFontDisableSmall")
  end
end

function B:Show(track)
  if not f then return end
  fill(track)
  if moving then return end -- stays put and visible until the move mode ends
  anchor()
  f.fadeOut:Stop()
  if not f:IsShown() then
    f:SetAlpha(0)
    f:Show()
    f.fadeIn:Play()
  else
    f:SetAlpha(1)
  end
  if hideTimer then hideTimer:Cancel() end
  hideTimer = C_Timer.NewTimer(SHOW_TIME, function()
    hideTimer = nil
    f.fadeOut:Play()
  end)
end

-- Move mode: the banner stays visible and takes the mouse; drag it, right-click resets the
-- position, a plain click ends the mode (so does /kzz banner or the Settings button again).
function B:SetMoving(on)
  if not f then return end
  on = on and true or false
  if on == (moving or false) then return end
  moving = on
  dragged = false
  if hideTimer then hideTimer:Cancel() hideTimer = nil end
  f.fadeIn:Stop()
  f.fadeOut:Stop()
  f:EnableMouse(on)
  if on then
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    anchor()
    fill(ns.Player.track)
    f:SetAlpha(1)
    f:Show()
  else
    fill(ns.Player.track)
    f.fadeOut:Play()
  end
end

function B:ToggleMoving()
  self:SetMoving(not moving)
end

function B:IsMoving()
  return moving and true or false
end

function B:IsShown()
  return f and f:IsShown()
end
