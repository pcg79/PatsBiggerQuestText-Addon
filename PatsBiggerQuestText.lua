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
local function ApplyScale()
    local s = GetScale()
    if QuestFrame and QuestFrame.SetScale then QuestFrame:SetScale(s) end
    if GossipFrame and GossipFrame.SetScale then GossipFrame:SetScale(s) end
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

-- Hook QuestInfo_Display so our sizes are re-applied every time the quest frame
-- lays itself out. Installed lazily in case the function isn't a global yet.
local hooked = false
local function TryHook()
    if not hooked and type(QuestInfo_Display) == "function" then
        hooksecurefunc("QuestInfo_Display", ApplyFontSizes)
        hooked = true
    end
end

-- The gossip frame (NPC dialog) was rewritten into a dynamic scroll list, so
-- there are no static FontStrings to target. Instead we locate the scroll box
-- and resize every FontString inside each currently visible element. Everything
-- is nil-guarded, so if Blizzard changes the layout this quietly does nothing
-- rather than erroring.
local function GetGossipScrollBox()
    if not GossipFrame then return nil end
    local panel = GossipFrame.GreetingPanel
    if panel then
        if panel.ScrollBox then return panel.ScrollBox, panel end
    end
    if GossipFrame.ScrollBox then return GossipFrame.ScrollBox, GossipFrame end
    return nil
end

-- Resize every FontString on a single gossip scroll element (the greeting
-- paragraph, an option row, a quest row, etc.).
local function ResizeGossipFrame(frame, size)
    if not frame then return end
    -- Button label (option / quest rows are buttons).
    if frame.GetFontString then
        ResizeFontString(frame:GetFontString(), size)
    end
    -- Any other FontString regions on the element.
    if frame.GetRegions then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "FontString" then
                ResizeFontString(region, size)
            end
        end
    end
end

local gossipRelayout = false
local function ResizeGossip()
    local scrollBox, panel = GetGossipScrollBox()
    local size = GetSize()

    -- Greeting paragraph, if it's a standalone FontString on the panel.
    if panel then
        ResizeFontString(panel.GreetingText, size)
    end

    if not scrollBox then return end

    if scrollBox.GetFrames then
        for _, frame in ipairs(scrollBox:GetFrames()) do
            ResizeGossipFrame(frame, size)
        end
    end

    -- Re-run the scroll layout so element heights are re-measured against the
    -- new (persistent) font sizes. Without this the taller greeting paragraph
    -- overflows into the option rows anchored beneath it. Guarded so the
    -- re-layout (which re-initializes frames) can't recurse.
    if scrollBox.FullUpdate and not gossipRelayout then
        gossipRelayout = true
        scrollBox:FullUpdate(ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately or true)
        gossipRelayout = false
    end
end

local gossipHooked = false
local function TryHookGossip()
    if gossipHooked then return end
    if GossipFrame and type(GossipFrame.Update) == "function" then
        hooksecurefunc(GossipFrame, "Update", ResizeGossip)
        -- Resize each element as it's (re)initialized, so newly created or
        -- recycled scroll frames carry the right font *before* they're measured.
        local scrollBox = GetGossipScrollBox()
        if scrollBox and ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
            ScrollUtil.AddInitializedFrameCallback(scrollBox, function(frame)
                ResizeGossipFrame(frame, GetSize())
            end, scrollBox, true)
        end
        gossipHooked = true
    end
end

local function SetSize(n, announce)
    PBQT_DB.size = Clamp(n)
    ApplyFontSizes()
    ResizeGossip()
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
        ApplyScale()
    elseif event == "GOSSIP_SHOW" then
        -- NPC dialog is opening; hook re-renders, apply the window scale and
        -- resize after this frame's layout completes.
        TryHookGossip()
        ApplyScale()
        C_Timer.After(0, ResizeGossip)
    else
        -- A quest window is opening; make sure the hook is in place and the
        -- sizes are applied after Blizzard finishes its layout this frame.
        TryHook()
        C_Timer.After(0, ApplyFontSizes)
    end
end)
