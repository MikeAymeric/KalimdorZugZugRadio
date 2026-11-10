-- Banner: "Now playing" toast above the chat window when a new track starts.
local _, ns = ...
local L = ns.L

local B = {}
ns.Banner = B

local SHOW_TIME, FADE_TIME = 4, 0.4
local DEFAULT_COVER = "Interface\\Icons\\INV_Misc_QuestionMark"
local f, lastTrack, hideTimer

local function anchor()
  f:ClearAllPoints()
  local chat = _G.ChatFrame1 or _G.DEFAULT_CHAT_FRAME
  if chat and chat.IsShown and chat:IsShown() then
    f:SetPoint("BOTTOMLEFT", chat, "TOPLEFT", -4, 28) -- above the chat tabs
  else
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 220)
  end
end

local function applySkin()
  local classic = (ns.db.ui.skin or "classic") == "classic"
  if f.SetBackdrop then
    if classic then
      f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                      tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
      f:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
      f:SetBackdropBorderColor(1, 0.82, 0, 1)
    else
      f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
      f:SetBackdropColor(0.06, 0.05, 0.05, 0.92)
      f:SetBackdropBorderColor(1, 0.5, 0.1, 0.8)
    end
  end
end

function B:Build()
  if f then return end
  f = CreateFrame("Frame", "KalimdorZugZugRadioBanner", UIParent, "BackdropTemplate")
  f:SetSize(300, 52)
  f:SetFrameStrata("MEDIUM")
  f:EnableMouse(false) -- never blocks clicks on the chat
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
  ns.On("SETTINGS_CHANGED", function() applySkin() end)
  applySkin()
end

function B:OnTrack(track)
  -- podcasts fire TRACK_CHANGED for every part: only announce a new track
  if not track or track == lastTrack or not ns.Player.playing then return end
  lastTrack = track
  if not ns.db.ui.banner then return end
  self:Show(track)
end

function B:Show(track)
  if not f then return end
  anchor()
  f.cover:SetTexture(ns.CoverOf(track) or DEFAULT_COVER)
  ns.SetText(f.title, track.title or "?", "GameFontHighlight")
  ns.SetText(f.artist, track.artist or "", "GameFontDisableSmall")
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

function B:IsShown()
  return f and f:IsShown()
end
