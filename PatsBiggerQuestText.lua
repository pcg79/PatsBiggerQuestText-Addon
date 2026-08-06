-- Pat's Bigger Quest Text
-- Enlarges the text in the quest dialog and NPC gossip windows, and optionally
-- scales up the whole window so larger text doesn't feel cramped. Both are
-- configurable via /pbqt or the addon options sliders, and saved account-wide.

local addonName = ...

local DEFAULT_SIZE = 16
local MIN_SIZE = 10
local MAX_SIZE = 30

-- Window scale multiplies the entire quest / gossip frame (background, text and
-- buttons together), so the text-to-window ratio stays comfortable at any font
-- size. 1.0 = Blizzard default.
local DEFAULT_SCALE = 1.0
local MIN_SCALE = 1.0
local MAX_SCALE = 2.0
local SCALE_STEP = 0.05

-- The FontStrings in the quest dialog whose size we control. Each is looked up
-- by its global name and guarded individually, so a name missing on a given
-- game build is simply skipped. Add or remove lines here to taste.
local FONT_STRINGS = {
    "QuestInfoDescriptionText", -- the quest story / description paragraph
    "QuestInfoObjectivesText",  -- the objectives paragraph
    "QuestInfoRewardText",      -- the "You will receive:" flavor line
    "QuestInfoGroupSize",       -- suggested number of players
    "QuestProgressText",        -- text shown when returning before completion
}

-- Global FONT OBJECTS used by the quest and (crucially) the gossip frame.
-- The gossip window is a scroll list whose row heights are computed by an
-- "extent calculator" that reads these font objects -- NOT the individual
-- FontStrings. So resizing instances alone made rows render big while the
-- layout still budgeted the old height, causing overlap. Resizing the objects
-- keeps rendering and measurement in sync. Names confirmed via /pbqt debug:
-- QuestFont (gossip greeting / quest body), QuestFontLeft (gossip options).
-- The rest are guarded by existence and only affect quest/gossip text.
local FONT_OBJECTS = {
    "QuestFont",
    "QuestFontLeft",
    "QuestFontNormalSmall",
    "QuestFontHighlight",
    "GossipFont",
}

-- Forward declaration so the slash handler can refresh the options sliders.
local RefreshControls

local function GetSize()
    return (PBQT_DB and PBQT_DB.size) or DEFAULT_SIZE
end

local function GetScale()
    return (PBQT_DB and PBQT_DB.scale) or DEFAULT_SCALE
end

local function Clamp(n)
    n = math.floor(n + 0.5)
    if n < MIN_SIZE then return MIN_SIZE end
    if n > MAX_SIZE then return MAX_SIZE end
    return n
end

local function ClampScale(n)
    -- Round to the nearest step so the value stays clean.
    n = math.floor(n / SCALE_STEP + 0.5) * SCALE_STEP
    if n < MIN_SCALE then return MIN_SCALE end
    if n > MAX_SCALE then return MAX_SCALE end
    return n
end

-- Apply the window scale to the quest and gossip frames. SetScale persists
-- across shows, so calling this once (and on change) is enough per frame.
--
-- Touching a Blizzard frame from addon code taints that frame, and GossipFrame
-- is registered with UIWidgetManager as a widget-set container -- so a tainted
-- GossipFrame leaks our taint into unrelated widget passes (map POI tooltips
-- and the like). Keep the blast radius as small as possible: never call
-- SetScale at the default scale, and never call it redundantly.
local scaleTouched = false

local function ApplyScaleTo(frame, s)
    if not frame or not frame.SetScale then return end
    if frame.GetScale and math.abs((frame:GetScale() or 1) - s) < 0.001 then return end
    frame:SetScale(s)
end

local function ApplyScale()
    local s = GetScale()
    -- Players who never move the slider off 1.0 pay no taint cost at all. Once
    -- we have scaled a frame we must keep applying, so 2.0 -> 1.0 still resets.
    if s == DEFAULT_SCALE and not scaleTouched then return end
    scaleTouched = true
    ApplyScaleTo(QuestFrame, s)
    ApplyScaleTo(GossipFrame, s)
end

-- Re-set a FontString's height while preserving its font file and flags, so the
-- player's locale font and any outline styling are kept intact.
local function ResizeFontString(fs, size)
    if not fs or not fs.GetFont then return end
    local file, _, flags = fs:GetFont()
    if file then
        fs:SetFont(file, size, flags)
    end
end

local function ApplyFontSizes()
    local size = GetSize()
    for _, name in ipairs(FONT_STRINGS) do
        ResizeFontString(_G[name], size)
    end
end

-- Resize the global quest/gossip font objects to the current size, preserving
-- each object's font file and flags. Returns true if any object's size actually
-- changed -- the caller uses that to decide whether a re-layout is needed (the
-- gossip extent calculator will have already run with the old metrics).
local function ApplyFontObjects()
    local size = GetSize()
    local changed = false
    for _, name in ipairs(FONT_OBJECTS) do
        local obj = _G[name]
        if obj and obj.GetFont then
            local file, cur, flags = obj:GetFont()
            if file and cur ~= size then
                obj:SetFont(file, size, flags)
                changed = true
            end
        end
    end
    return changed
end

-- NOTE: we deliberately never call GossipFrame:Update() (or ScrollBox:FullUpdate)
-- ourselves to force a re-render after a size change.
--
-- GossipFrameMixin:Update registers gossip widget sets with the shared
-- UIWidgetManager. Driving it from addon code runs that registration under our
-- taint, which writes our taint into the widget manager's internal tables --
-- and every later widget pass that reads them then runs tainted too, including
-- the map area-POI tooltips. Since 12.0 added secret values, tainted execution
-- can no longer do arithmetic on the widget templates' measured text heights,
-- so that showed up as a hard Lua error on map mouseover.
--
-- Font objects are persistent, so pre-sizing them (at login, and whenever the
-- setting changes) is enough for every gossip window opened afterwards. The
-- only case we give up is re-flowing a window that is already on screen when
-- the size changes; that now takes effect the next time the window opens.

-- Hook QuestInfo_Display so our sizes are re-applied every time the quest frame
-- lays itself out. Installed lazily in case the function isn't a global yet.
local hooked = false
local function TryHook()
    if not hooked and type(QuestInfo_Display) == "function" then
        hooksecurefunc("QuestInfo_Display", ApplyFontSizes)
        hooked = true
    end
end

-- The gossip frame (NPC dialog) is a dynamic scroll list with no static
-- FontStrings to target, which is why we size the shared font objects instead.
-- This locator is only used by `/pbqt debug` to inspect the live list; it is
-- nil-guarded so a Blizzard layout change makes it quietly return nothing.
local function GetGossipScrollBox()
    if not GossipFrame then return nil end
    local panel = GossipFrame.GreetingPanel
    if panel then
        if panel.ScrollBox then return panel.ScrollBox, panel end
    end
    if GossipFrame.ScrollBox then return GossipFrame.ScrollBox, GossipFrame end
    return nil
end

-- Temporary diagnostic: with a gossip window open, `/pbqt debug` dumps the
-- scroll box structure so we can see how each element's height/extent is
-- determined and which font object it uses. Remove once the scroll issue is
-- fixed.
local function DebugGossip()
    local scrollBox, panel = GetGossipScrollBox()
    print("|cff33ff99PBQT debug|r  GossipFrame:", GossipFrame and "y" or "n",
        "| scrollBox:", scrollBox and "y" or "n",
        "| panel.GreetingText:", (panel and panel.GreetingText) and "y" or "n")
    if not scrollBox then
        print("  (open a gossip/NPC dialog window first)")
        return
    end
    local view = scrollBox.GetView and scrollBox:GetView()
    print("  view extentCalculator:", (view and view.elementExtentCalculator ~= nil) and "YES" or "no",
        "| scrollBox height:", scrollBox.GetHeight and math.floor(scrollBox:GetHeight() or 0))
    if not scrollBox.GetFrames then return end
    for i, f in ipairs(scrollBox:GetFrames()) do
        print(("  [%d] %s h=%d"):format(i,
            (f.GetObjectType and f:GetObjectType()) or "?",
            math.floor((f.GetHeight and f:GetHeight()) or 0)))
        if f.GetRegions then
            for _, r in ipairs({ f:GetRegions() }) do
                if r.GetObjectType and r:GetObjectType() == "FontString" then
                    local _, sz = r:GetFont()
                    local o = r.GetFontObject and r:GetFontObject()
                    local txt = (r.GetText and r:GetText()) or ""
                    print(("      FS obj=%s size=%s strH=%d txt=%q"):format(
                        (o and o.GetName and o:GetName()) or "nil",
                        tostring(sz),
                        math.floor((r.GetStringHeight and r:GetStringHeight()) or 0),
                        txt:sub(1, 20)))
                end
            end
        end
    end
end

local function SetSize(n, announce)
    PBQT_DB.size = Clamp(n)
    ApplyFontSizes()          -- quest frame FontStrings
    ApplyFontObjects()        -- quest + gossip font objects (fixes gossip layout)
    if RefreshControls then RefreshControls() end
    if announce then
        print("|cff33ff99Pat's Bigger Quest Text|r: quest text size set to " .. PBQT_DB.size .. ".")
    end
end

local function SetScaleValue(n, announce)
    PBQT_DB.scale = ClampScale(n)
    ApplyScale()
    if RefreshControls then RefreshControls() end
    if announce then
        print(("|cff33ff99Pat's Bigger Quest Text|r: window scale set to %.2f."):format(PBQT_DB.scale))
    end
end

-- Options panel: font-size and window-scale sliders registered with the modern
-- Settings API.
local settingsCategory
local function BuildOptions()
    local panel = CreateFrame("Frame")
    panel.name = "Pat's Bigger Quest Text"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Pat's Bigger Quest Text")

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("Font size for the quest and gossip text.")

    -- Font size slider.
    local sizeSlider = CreateFrame("Slider", "PBQT_SizeSlider", panel, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 4, -32)
    sizeSlider:SetWidth(280)
    sizeSlider:SetMinMaxValues(MIN_SIZE, MAX_SIZE)
    sizeSlider:SetValueStep(1)
    sizeSlider:SetObeyStepOnDrag(true)
    _G[sizeSlider:GetName() .. "Low"]:SetText(MIN_SIZE)
    _G[sizeSlider:GetName() .. "High"]:SetText(MAX_SIZE)
    local sizeText = _G[sizeSlider:GetName() .. "Text"]

    sizeSlider:SetScript("OnValueChanged", function(_, value)
        value = Clamp(value)
        sizeText:SetText("Quest Text Size: " .. value)
        if PBQT_DB.size ~= value then
            SetSize(value, false)
        end
    end)

    -- Window scale slider.
    local scaleSlider = CreateFrame("Slider", "PBQT_ScaleSlider", panel, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, -48)
    scaleSlider:SetWidth(280)
    scaleSlider:SetMinMaxValues(MIN_SCALE, MAX_SCALE)
    scaleSlider:SetValueStep(SCALE_STEP)
    scaleSlider:SetObeyStepOnDrag(true)
    _G[scaleSlider:GetName() .. "Low"]:SetText(MIN_SCALE .. "x")
    _G[scaleSlider:GetName() .. "High"]:SetText(MAX_SCALE .. "x")
    local scaleText = _G[scaleSlider:GetName() .. "Text"]

    scaleSlider:SetScript("OnValueChanged", function(_, value)
        value = ClampScale(value)
        scaleText:SetText(("Window Scale: %.2fx"):format(value))
        if PBQT_DB.scale ~= value then
            SetScaleValue(value, false)
        end
    end)

    RefreshControls = function()
        sizeSlider:SetValue(GetSize())
        sizeText:SetText("Quest Text Size: " .. GetSize())
        scaleSlider:SetValue(GetScale())
        scaleText:SetText(("Window Scale: %.2fx"):format(GetScale()))
    end

    panel:SetScript("OnShow", RefreshControls)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(settingsCategory)
    elseif InterfaceOptions_AddCategory then -- pre-Dragonflight fallback
        InterfaceOptions_AddCategory(panel)
    end
end

-- Slash command: /pbqt <size> | /pbqt scale <n> | /pbqt config
SLASH_PBQT1 = "/pbqt"
SLASH_PBQT2 = "/biggerquesttext"
SlashCmdList["PBQT"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd or ""

    if cmd == "config" or cmd == "options" then
        if settingsCategory and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(settingsCategory:GetID())
        end
        return
    end

    if cmd == "debug" then
        DebugGossip()
        return
    end

    if cmd == "scale" then
        local n = tonumber(rest)
        if n then
            SetScaleValue(n, true)
        else
            print(("|cff33ff99Pat's Bigger Quest Text|r: window scale is %.2fx. Usage: /pbqt scale <%.1f-%.1f>")
                :format(GetScale(), MIN_SCALE, MAX_SCALE))
        end
        return
    end

    local n = tonumber(cmd)
    if n then
        SetSize(n, true)
    else
        print("|cff33ff99Pat's Bigger Quest Text|r: size " .. GetSize()
            .. (", scale %.2fx."):format(GetScale()))
        print("  /pbqt <" .. MIN_SIZE .. "-" .. MAX_SIZE .. ">  |  /pbqt scale <"
            .. MIN_SCALE .. "-" .. MAX_SCALE .. ">  |  /pbqt config")
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("QUEST_DETAIL")
f:RegisterEvent("QUEST_PROGRESS")
f:RegisterEvent("QUEST_COMPLETE")
f:RegisterEvent("QUEST_GREETING")
f:RegisterEvent("GOSSIP_SHOW")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            PBQT_DB = PBQT_DB or {}
            if type(PBQT_DB.size) ~= "number" then
                PBQT_DB.size = DEFAULT_SIZE
            end
            if type(PBQT_DB.scale) ~= "number" then
                PBQT_DB.scale = DEFAULT_SCALE
            end
        end
    elseif event == "PLAYER_LOGIN" then
        BuildOptions()
        TryHook()
        ApplyFontSizes()
        ApplyFontObjects() -- pre-size objects so the first gossip open is correct
        ApplyScale()
    elseif event == "GOSSIP_SHOW" then
        -- NPC dialog is opening. Size the font objects now: GossipFont and
        -- friends may only have come into existence when Blizzard_GossipFrame
        -- loaded, so login alone isn't guaranteed to have caught them. This is
        -- a no-op once they already carry the right size, and it never calls
        -- into Blizzard's layout code -- see the note above TryHook.
        ApplyFontObjects()
        ApplyScale()
    else
        -- A quest window is opening; make sure the hook is in place and the
        -- sizes are applied after Blizzard finishes its layout this frame.
        TryHook()
        C_Timer.After(0, ApplyFontSizes)
    end
end)
