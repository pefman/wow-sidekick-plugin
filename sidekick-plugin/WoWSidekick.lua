-- =========================================================
-- WoW Sidekick - Optical Data Output Protocol
-- =========================================================
-- Transmits game state data via visual lightbox encoding.
-- External tools can capture the screen and decode the pixel
-- patterns to receive real-time combat and character information.
--
-- Protocol: 200 boxes in a 20x5 grid
-- - 8-color encoding (3 bits per box)
-- - 75-char JSON array payload per frame (600 bits)
-- Update Rate: 20 Hz (50ms frames)
-- =========================================================

-- =========================
-- CONFIGURATION
-- =========================
local DEFAULT_FPS = 10            -- Default frames per second (update rate)
local FPS = DEFAULT_FPS           -- Active FPS (can be overridden by saved config)
local FRAME_TIME = 1 / FPS        -- Time between frame updates
local BOX_SIZE = 5                -- Pixel size of each box
local BOX_GAP_X = 0               -- Horizontal gap between boxes
local BOX_GAP_Y = 0               -- Vertical gap between boxes
local BORDER_THICKNESS = 1        -- Border thickness in pixels
local BORDER_COLOR = {0, 1, 0}    -- Pure green border (RGB)
local OFFSET_X = 0                -- X offset from top-left (pixels)
local OFFSET_Y = 0                -- Y offset from top-left (pixels)
local SCHEMA_VERSION = 2          -- JSON schema version

-- Grid layout
local COLS = 40                   -- Number of columns
local ROWS = 5                    -- Number of rows
local BOX_COUNT = COLS * ROWS     -- Total boxes: 200

-- 8-color palette for 3-bit encoding (index 0-7)
local COLOR_PALETTE = {
    {0, 0, 0},       -- 0: black
    {1, 1, 1},       -- 1: white
    {1, 0, 0},       -- 2: red
    {0, 1, 0},       -- 3: green
    {0, 0, 1},       -- 4: blue
    {0, 1, 1},       -- 5: cyan
    {1, 0, 1},       -- 6: magenta
    {1, 1, 0},       -- 7: yellow
}

-- =========================
-- STATE
-- =========================
local frameTimer = 0              -- Timer for frame rate limiting
local boxes = {}                  -- Array of texture frames
local lastJson = ""               -- Last JSON payload for debugging

-- Saved settings
WoWSidekickDB = WoWSidekickDB or {}
if type(WoWSidekickDB.fps) ~= "number" then
    WoWSidekickDB.fps = DEFAULT_FPS
end
if type(WoWSidekickDB.debugJSON) ~= "boolean" then
    WoWSidekickDB.debugJSON = false
end
FPS = WoWSidekickDB.fps
FRAME_TIME = 1 / FPS

-- =========================
-- UTILITY FUNCTIONS
-- =========================

-- Calculates even parity bit for error detection
-- Returns 1 if odd number of 1s, 0 if even
local function evenParity(bits)
    local count = 0
    for _, b in ipairs(bits) do
        if b == 1 then count = count + 1 end
    end
    return (count % 2 == 0) and 0 or 1
end

-- Converts a decimal value to an array of n bits
-- Returns MSB-first bit array
local function valueToBits(v, n)
    local bits = {}
    for i = n - 1, 0, -1 do
        bits[#bits + 1] = bit.band(bit.rshift(v, i), 1)
    end
    return bits
end

-- Convert desired physical pixels to UI units
local function PixelToUI(value)
    local physW, physH = GetPhysicalScreenSize()
    local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()
    if physW and physH and uiW and uiH and physW > 0 and physH > 0 then
        -- UI units per pixel
        local ux = uiW / physW
        local uy = uiH / physH
        -- Use X scale for sizes (square pixels expected)
        return value * ux
    end
    local scale = UIParent:GetEffectiveScale()
    if scale and scale > 0 then
        return value / scale
    end
    return value
end

-- =========================
-- PAYLOAD BUILDER (JSON)
-- =========================
-- Emits a compact JSON array (fixed 75 chars), then converts to 600 bits.
-- Array order:
-- [schema, hp, thp, res, dist, inCombat, hasTarget, plvl, tlvl, facing,
--  pClass, tClass, pBuffs, tDebuffs, isCasting, inCC, posX, posY]
local function buildPayload()
    local bits = {}

    -- Player HP % (0-127)
    local hp = 0
    if UnitHealthMax("player") > 0 then
        hp = math.floor(UnitHealth("player") / UnitHealthMax("player") * 127)
    end

    -- Target HP % (0-127)
    local thp = 0
    if UnitExists("target") and UnitHealthMax("target") > 0 then
        thp = math.floor(UnitHealth("target") / UnitHealthMax("target") * 127)
    end

    -- Player Resource % (0-127) - mana/energy/rage/focus
    local resource = 0
    if UnitPowerMax("player") > 0 then
        resource = math.floor(UnitPower("player") / UnitPowerMax("player") * 127)
    end

    -- Distance to Target (0-31 yards)
    local distance = 0
    if UnitExists("target") then
        for i = 1, 4 do
            if CheckInteractDistance("target", i) then
                distance = i * 5
                break
            end
        end
        if distance == 0 then distance = 31 end
    end

    -- In Combat / Has Target
    local inCombat = UnitAffectingCombat("player") and 1 or 0
    local hasTarget = UnitExists("target") and 1 or 0

    -- Levels
    local playerLevel = UnitLevel("player") or 0
    local targetLevel = 0
    if UnitExists("target") then
        targetLevel = UnitLevel("target") or 0
    end

    -- Facing (0-7 compass)
    local facing = 0
    local playerFacing = GetPlayerFacing()
    if playerFacing then
        facing = math.floor((playerFacing / (2 * math.pi)) * 8) % 8
    end

    -- Player Class (0-12)
    local playerClass = 0
    local _, classFile = UnitClass("player")
    if classFile then
        if classFile == "WARRIOR" then playerClass = 1
        elseif classFile == "PALADIN" then playerClass = 2
        elseif classFile == "HUNTER" then playerClass = 3
        elseif classFile == "ROGUE" then playerClass = 4
        elseif classFile == "PRIEST" then playerClass = 5
        elseif classFile == "DEATHKNIGHT" then playerClass = 6
        elseif classFile == "SHAMAN" then playerClass = 7
        elseif classFile == "MAGE" then playerClass = 8
        elseif classFile == "WARLOCK" then playerClass = 9
        elseif classFile == "MONK" then playerClass = 10
        elseif classFile == "DRUID" then playerClass = 11
        elseif classFile == "DEMONHUNTER" then playerClass = 12
        end
    end

    -- Target Class (0-12)
    local targetClass = 0
    if UnitExists("target") then
        local _, targetClassFile = UnitClass("target")
        if targetClassFile then
            if targetClassFile == "WARRIOR" then targetClass = 1
            elseif targetClassFile == "PALADIN" then targetClass = 2
            elseif targetClassFile == "HUNTER" then targetClass = 3
            elseif targetClassFile == "ROGUE" then targetClass = 4
            elseif targetClassFile == "PRIEST" then targetClass = 5
            elseif targetClassFile == "DEATHKNIGHT" then targetClass = 6
            elseif targetClassFile == "SHAMAN" then targetClass = 7
            elseif targetClassFile == "MAGE" then targetClass = 8
            elseif targetClassFile == "WARLOCK" then targetClass = 9
            elseif targetClassFile == "MONK" then targetClass = 10
            elseif targetClassFile == "DRUID" then targetClass = 11
            elseif targetClassFile == "DEMONHUNTER" then targetClass = 12
            end
        end
    end

    -- Player Buffs (0-7)
    local playerBuffCount = 0
    for i = 1, 40 do
        if select(1, UnitBuff("player", i)) then
            playerBuffCount = playerBuffCount + 1
        end
        if playerBuffCount >= 7 then break end
    end

    -- Target Debuffs (0-7)
    local targetDebuffCount = 0
    if UnitExists("target") then
        for i = 1, 40 do
            if select(1, UnitDebuff("target", i)) then
                targetDebuffCount = targetDebuffCount + 1
            end
            if targetDebuffCount >= 7 then break end
        end
    end

    -- Player is Casting
    local isPlayerCasting = UnitCastingInfo("player") and 1 or 0

    -- Player in CC
    local inCC = 0
    if select(1, UnitCastingInfo("player")) == nil then
        for i = 1, 40 do
            local _, _, _, _, auraType = select(1, UnitDebuff("player", i)), select(5, UnitDebuff("player", i))
            if auraType == "Stun" or auraType == "Fear" or auraType == "Charm" or auraType == "Root" then
                inCC = 1
                break
            end
        end
    end

    -- Player map position (0-99)
    local posX, posY = 0, 0
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
        local mapId = C_Map.GetBestMapForUnit("player")
        if mapId then
            local position = C_Map.GetPlayerMapPosition(mapId, "player")
            if position then
                posX = math.floor(position.x * 100)
                posY = math.floor(position.y * 100)
                if posX < 0 then posX = 0 elseif posX > 99 then posX = 99 end
                if posY < 0 then posY = 0 elseif posY > 99 then posY = 99 end
            end
        end
    end

    -- Compact JSON array (fixed length 75 chars)
    local jsonValues = {
        SCHEMA_VERSION,
        hp, thp, resource, distance,
        inCombat, hasTarget,
        playerLevel, targetLevel,
        facing, playerClass, targetClass,
        playerBuffCount, targetDebuffCount,
        isPlayerCasting, inCC,
        posX, posY,
    }
    local json = "[" .. table.concat(jsonValues, ",") .. "]"
    if #json < 75 then
        json = json .. string.rep(" ", 75 - #json)
    end
    lastJson = json

    -- Convert JSON bytes to bits (MSB-first)
    for i = 1, #json do
        local byte = string.byte(json, i)
        for _, b in ipairs(valueToBits(byte, 8)) do bits[#bits + 1] = b end
    end

    return bits
end

-- =========================
-- FRAME ENCODING
-- =========================
-- Uses 3 bits per box (8 colors). Total bits = BOX_COUNT * 3.
local function encodeFrame(payloadBits)
    local bits = {}

    local totalBits = BOX_COUNT * 3
    for i = 1, totalBits do
        bits[i] = payloadBits[i] or 0
    end

    return bits
end

-- =========================
-- UI SETUP & RENDERING
-- =========================
-- Creates the visual display grid anchored to screen top-left.
-- Each box will be updated in the OnUpdate loop with payload data.
local root = CreateFrame("Frame", "WowSidekickFrame", UIParent)
root:SetScale(1)
root:SetIgnoreParentScale(true)
root:SetClampedToScreen(true)
root:SetMovable(false)
root:EnableMouse(false)

-- Calculate frame size based on grid layout
root:SetSize(
    PixelToUI(COLS * BOX_SIZE + (COLS - 1) * BOX_GAP_X + BORDER_THICKNESS * 2),
    PixelToUI(ROWS * BOX_SIZE + (ROWS - 1) * BOX_GAP_Y + BORDER_THICKNESS * 2)
)

-- Pure green border around the grid
local topBorder = root:CreateTexture(nil, "ARTWORK")
topBorder:SetColorTexture(unpack(BORDER_COLOR))
topBorder:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
topBorder:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
topBorder:SetHeight(PixelToUI(BORDER_THICKNESS))

local bottomBorder = root:CreateTexture(nil, "ARTWORK")
bottomBorder:SetColorTexture(unpack(BORDER_COLOR))
bottomBorder:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
bottomBorder:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
bottomBorder:SetHeight(PixelToUI(BORDER_THICKNESS))

local leftBorder = root:CreateTexture(nil, "ARTWORK")
leftBorder:SetColorTexture(unpack(BORDER_COLOR))
leftBorder:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
leftBorder:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
leftBorder:SetWidth(PixelToUI(BORDER_THICKNESS))

local rightBorder = root:CreateTexture(nil, "ARTWORK")
rightBorder:SetColorTexture(unpack(BORDER_COLOR))
rightBorder:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
rightBorder:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
rightBorder:SetWidth(PixelToUI(BORDER_THICKNESS))

-- Debug JSON display
local debugFrame = CreateFrame("Frame", "WoWSidekickDebugFrame", UIParent)
debugFrame:SetSize(PixelToUI(420), PixelToUI(80))
debugFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", PixelToUI(10), PixelToUI(-10))
debugFrame:SetFrameStrata("DIALOG")
debugFrame:SetIgnoreParentScale(true)
debugFrame:EnableMouse(true)
debugFrame:SetMovable(true)
debugFrame:RegisterForDrag("LeftButton")
debugFrame:SetScript("OnDragStart", debugFrame.StartMoving)
debugFrame:SetScript("OnDragStop", debugFrame.StopMovingOrSizing)
debugFrame:Hide()

local debugBg = debugFrame:CreateTexture(nil, "BACKGROUND")
debugBg:SetAllPoints()
debugBg:SetColorTexture(0, 0, 0, 0.6)

local debugEditBox = CreateFrame("EditBox", nil, debugFrame, "InputBoxTemplate")
debugEditBox:SetPoint("TOPLEFT", PixelToUI(8), PixelToUI(-8))
debugEditBox:SetPoint("BOTTOMRIGHT", PixelToUI(-8), PixelToUI(8))
debugEditBox:SetAutoFocus(false)
debugEditBox:SetMultiLine(true)
debugEditBox:SetMaxLetters(1024)
debugEditBox:SetJustifyH("LEFT")
debugEditBox:SetJustifyV("TOP")
debugEditBox:EnableMouse(true)
debugEditBox:SetText("")
debugEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)


-- Anchor the display to screen top-left
local function applyScale()
    root:SetScale(1)
    debugFrame:SetScale(1)

    root:SetSize(
        PixelToUI(COLS * BOX_SIZE + (COLS - 1) * BOX_GAP_X + BORDER_THICKNESS * 2),
        PixelToUI(ROWS * BOX_SIZE + (ROWS - 1) * BOX_GAP_Y + BORDER_THICKNESS * 2)
    )

    topBorder:SetHeight(PixelToUI(BORDER_THICKNESS))
    bottomBorder:SetHeight(PixelToUI(BORDER_THICKNESS))
    leftBorder:SetWidth(PixelToUI(BORDER_THICKNESS))
    rightBorder:SetWidth(PixelToUI(BORDER_THICKNESS))

    debugFrame:SetSize(PixelToUI(420), PixelToUI(80))
    debugEditBox:SetPoint("TOPLEFT", PixelToUI(8), PixelToUI(-8))
    debugEditBox:SetPoint("BOTTOMRIGHT", PixelToUI(-8), PixelToUI(8))

    for i = 1, BOX_COUNT do
        local box = boxes[i]
        if box then
            box:SetSize(PixelToUI(BOX_SIZE), PixelToUI(BOX_SIZE))

            local row = math.floor((i - 1) / COLS)
            local col = (i - 1) % COLS
            box:SetPoint(
                "TOPLEFT",
                PixelToUI(BORDER_THICKNESS + col * (BOX_SIZE + BOX_GAP_X)),
                -PixelToUI(BORDER_THICKNESS + row * (BOX_SIZE + BOX_GAP_Y))
            )
        end
    end
end

local function applyAnchor()
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", UIParent, "TOPLEFT", PixelToUI(OFFSET_X), PixelToUI(OFFSET_Y))
end

-- Handle startup tasks (anchor and autoloot)
local function onEvent(_, event)
    if event == "PLAYER_LOGIN" then
        applyScale()
        applyAnchor()
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        applyScale()
        applyAnchor()
    end
end

root:RegisterEvent("PLAYER_LOGIN")
root:RegisterEvent("UI_SCALE_CHANGED")
root:RegisterEvent("DISPLAY_SIZE_CHANGED")
root:SetScript("OnEvent", onEvent)
applyScale()
applyAnchor()

-- Options panel for autoloot toggle
local function createOptionsPanel()
    local panel = CreateFrame("Frame", "WoWSidekickOptionsPanel")
    panel.name = "WoW Sidekick"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("WoW Sidekick")

    local autolootCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    autolootCheckbox:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    autolootCheckbox.Text:SetText("Enable auto-loot")

    autolootCheckbox:SetScript("OnShow", function(self)
        self:SetChecked(GetCVar("autoLootDefault") == "1")
    end)

    autolootCheckbox:SetScript("OnClick", function(self)
        SetCVar("autoLootDefault", self:GetChecked() and "1" or "0")
    end)

    local debugCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    debugCheckbox:SetPoint("TOPLEFT", autolootCheckbox, "BOTTOMLEFT", 0, -8)
    debugCheckbox.Text:SetText("Show JSON debug window")

    debugCheckbox:SetScript("OnShow", function(self)
        self:SetChecked(WoWSidekickDB.debugJSON == true)
    end)

    debugCheckbox:SetScript("OnClick", function(self)
        WoWSidekickDB.debugJSON = self:GetChecked() and true or false
        debugFrame:SetShown(WoWSidekickDB.debugJSON)
    end)

    local fpsLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fpsLabel:SetPoint("TOPLEFT", debugCheckbox, "BOTTOMLEFT", 0, -18)
    fpsLabel:SetText("Update Rate (FPS)")

    local fpsDropdown = CreateFrame("Frame", "WoWSidekickFPSDropdown", panel, "UIDropDownMenuTemplate")
    fpsDropdown:SetPoint("TOPLEFT", fpsLabel, "BOTTOMLEFT", -16, -6)

    local fpsOptions = {5, 10, 20, 30}

    local function setFPS(value)
        WoWSidekickDB.fps = value
        FPS = value
        FRAME_TIME = 1 / FPS
        UIDropDownMenu_SetText(fpsDropdown, tostring(value))
    end

    UIDropDownMenu_Initialize(fpsDropdown, function()
        for _, v in ipairs(fpsOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = tostring(v)
            info.value = v
            info.func = function()
                setFPS(v)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    fpsDropdown:SetScript("OnShow", function()
        local current = WoWSidekickDB.fps or DEFAULT_FPS
        setFPS(current)
    end)

    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    elseif Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    end
end

createOptionsPanel()

-- Slash command to toggle autoloot: /sidekickloot [on|off]
SLASH_SIDEKICKLOOT1 = "/sidekickloot"
SLASH_SIDEKICKLOOT2 = "/skloot"
SlashCmdList["SIDEKICKLOOT"] = function(msg)
    local v = string.lower(msg or "")
    if v == "off" or v == "0" then
        SetCVar("autoLootDefault", "0")
        print("Sidekick auto-loot: OFF")
    else
        SetCVar("autoLootDefault", "1")
        print("Sidekick auto-loot: ON")
    end
end

-- Create the box grid
for i = 1, BOX_COUNT do
    local box = CreateFrame("Frame", nil, root)
    box:SetSize(PixelToUI(BOX_SIZE), PixelToUI(BOX_SIZE))

    -- Calculate row and column position
    local row = math.floor((i - 1) / COLS)
    local col = (i - 1) % COLS

    -- Position box relative to parent frame
    box:SetPoint(
        "TOPLEFT",
        PixelToUI(BORDER_THICKNESS + col * (BOX_SIZE + BOX_GAP_X)),
        -PixelToUI(BORDER_THICKNESS + row * (BOX_SIZE + BOX_GAP_Y))
    )

    -- Create texture for this box (black by default)
    local tex = box:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(0, 0, 0)

    box.tex = tex
    boxes[i] = box
end

-- =========================
-- MAIN UPDATE LOOP
-- =========================
-- Runs at 20 Hz to encode and render data frames.
-- Each frame:
--   1. Collects game state (buildPayload)
--   2. Encodes frame with sync bit (encodeFrame)
--   3. Renders frame to lightboxes
root:SetScript("OnUpdate", function(_, elapsed)
    -- Frame rate limiting
    frameTimer = frameTimer + elapsed
    if frameTimer < FRAME_TIME then return end
    frameTimer = frameTimer - FRAME_TIME

    -- Build and encode data frame
    local payload = buildPayload()
    local bits = encodeFrame(payload)

    -- Update debug window
    if WoWSidekickDB.debugJSON then
        debugFrame:Show()
        if not debugEditBox:HasFocus() then
            debugEditBox:SetText(lastJson)
        end
    else
        debugFrame:Hide()
    end

    -- Render frame to boxes using 3 bits per box (8 colors)
    for i = 1, BOX_COUNT do
        local base = (i - 1) * 3
        local b1 = bits[base + 1] or 0
        local b2 = bits[base + 2] or 0
        local b3 = bits[base + 3] or 0
        local colorIndex = b1 * 4 + b2 * 2 + b3
        local color = COLOR_PALETTE[colorIndex + 1] or COLOR_PALETTE[1]
        boxes[i].tex:SetColorTexture(color[1], color[2], color[3])
    end
end)
