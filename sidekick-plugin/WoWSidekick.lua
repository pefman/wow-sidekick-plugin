-- =========================================================
-- WoW Sidekick - Optical Data Output Protocol
-- =========================================================
-- Transmits game state data via visual lightbox encoding.
-- External tools can capture the screen and decode the pixel
-- patterns to receive real-time combat and character information.
--
-- Protocol: 40 boxes in a 20x2 grid
-- - Box 1: Sync bit (always white/1)
-- - Boxes 2-40: 39 bits of player/target data
-- Update Rate: 20 Hz (50ms frames)
-- =========================================================

-- =========================
-- CONFIGURATION
-- =========================
-- Display settings
local FPS = 20                    -- Frames per second (update rate)
local FRAME_TIME = 1 / FPS        -- Time between frame updates (50ms)
local BOX_SIZE = 5                -- Pixel size of each box
local BOX_GAP_X = 0               -- Horizontal gap between boxes
local BOX_GAP_Y = 0               -- Vertical gap between boxes
local OFFSET_X = 0                -- X offset from top-left (pixels)
local OFFSET_Y = 0                -- Y offset from top-left (pixels)

-- Grid layout
local COLS = 20                   -- Number of columns
local ROWS = 3                    -- Number of rows
local BOX_COUNT = COLS * ROWS     -- Total boxes: 60

-- =========================
-- STATE
-- =========================
local frameTimer = 0              -- Timer for frame rate limiting
local boxes = {}                  -- Array of texture frames

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

-- =========================
-- PAYLOAD BUILDER
-- =========================
-- Encodes comprehensive game state into 59 data bits.
-- Grid: 60 boxes (20x3) = 1 sync bit + 59 payload bits
--
-- Bit Layout (59 bits total):
--  [0-6]    : Player HP % (0-127)
--  [7-13]   : Target HP % (0-127)
--  [14-20]  : Player Resource % (0-127)
--  [21-25]  : Distance to Target (0-31 yards)
--  [26]     : In Combat (bool)
--  [27]     : Has Target (bool)
--  [28-32]  : Player Level (0-31)
--  [33-37]  : Target Level (0-31)
--  [38-40]  : Player Facing Direction (0-7 compass)
--  [41-44]  : Player Class (0-12)
--  [45-48]  : Target Class (0-12)
--  [49-52]  : Player Buffs (0-15)
--  [53-56]  : Target Debuffs (0-15)
--  [57]     : Player is Casting (bool)
--  [58]     : Player in CC/Stunned (bool)
--  [59]     : Player Stealth (bool)
--  [60]     : Player PvP Flagged (bool)
local function buildPayload()
    local bits = {}

    -- [0-6] Player HP % (7 bits)
    local hp = 0
    if UnitHealthMax("player") > 0 then
        hp = math.floor(UnitHealth("player") / UnitHealthMax("player") * 127)
    end
    for _, b in ipairs(valueToBits(hp, 7)) do bits[#bits + 1] = b end

    -- [7-13] Target HP % (7 bits)
    local thp = 0
    if UnitExists("target") and UnitHealthMax("target") > 0 then
        thp = math.floor(UnitHealth("target") / UnitHealthMax("target") * 127)
    end
    for _, b in ipairs(valueToBits(thp, 7)) do bits[#bits + 1] = b end

    -- [14-20] Player Resource % (7 bits) - mana/energy/rage/focus
    local resource = 0
    if UnitPowerMax("player") > 0 then
        resource = math.floor(UnitPower("player") / UnitPowerMax("player") * 127)
    end
    for _, b in ipairs(valueToBits(resource, 7)) do bits[#bits + 1] = b end

    -- [21-25] Distance to Target (5 bits: 0-31 yards)
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
    for _, b in ipairs(valueToBits(distance, 5)) do bits[#bits + 1] = b end

    -- [26] In Combat (1 bit)
    bits[#bits + 1] = UnitAffectingCombat("player") and 1 or 0

    -- [27] Has Target (1 bit)
    bits[#bits + 1] = UnitExists("target") and 1 or 0

    -- [28-32] Player Level (5 bits)
    local playerLevel = UnitLevel("player") or 0
    for _, b in ipairs(valueToBits(playerLevel, 5)) do bits[#bits + 1] = b end

    -- [33-37] Target Level (5 bits)
    local targetLevel = 0
    if UnitExists("target") then
        targetLevel = UnitLevel("target") or 0
    end
    for _, b in ipairs(valueToBits(targetLevel, 5)) do bits[#bits + 1] = b end

    -- [38-40] Player Facing Direction (3 bits: 0-7 compass directions)
    local facing = 0
    local playerFacing = GetPlayerFacing()
    if playerFacing then
        facing = math.floor((playerFacing / (2 * math.pi)) * 8) % 8
    end
    for _, b in ipairs(valueToBits(facing, 3)) do bits[#bits + 1] = b end

    -- [41-44] Player Class (4 bits: 0-12)
    -- 0=unknown, 1=warrior, 2=paladin, 3=hunter, 4=rogue, 5=priest, 6=deathknight, 
    -- 7=shaman, 8=mage, 9=warlock, 10=monk, 11=druid, 12=demonhunter
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
    for _, b in ipairs(valueToBits(playerClass, 4)) do bits[#bits + 1] = b end

    -- [45-48] Target Class (4 bits: same mapping)
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
    for _, b in ipairs(valueToBits(targetClass, 4)) do bits[#bits + 1] = b end

    -- [49-52] Player Buffs (4 bits: 0-15)
    local playerBuffCount = 0
    for i = 1, 40 do
        if select(1, UnitBuff("player", i)) then
            playerBuffCount = playerBuffCount + 1
        end
        if playerBuffCount >= 15 then break end
    end
    for _, b in ipairs(valueToBits(playerBuffCount, 4)) do bits[#bits + 1] = b end

    -- [53-56] Target Debuffs (4 bits: 0-15)
    local targetDebuffCount = 0
    if UnitExists("target") then
        for i = 1, 40 do
            if select(1, UnitDebuff("target", i)) then
                targetDebuffCount = targetDebuffCount + 1
            end
            if targetDebuffCount >= 15 then break end
        end
    end
    for _, b in ipairs(valueToBits(targetDebuffCount, 4)) do bits[#bits + 1] = b end

    -- [57] Player is Casting (1 bit)
    local isPlayerCasting = 0
    if UnitCastingInfo("player") then
        isPlayerCasting = 1
    end
    bits[#bits + 1] = isPlayerCasting

    -- [58] Player in CC (1 bit) - check for common crowd control effects
    local inCC = 0
    if select(1, UnitCastingInfo("player")) == nil then
        -- Check for stun/fear/charm/root auras
        for i = 1, 40 do
            local auraName, _, _, _, auraType = select(1, UnitDebuff("player", i)), select(5, UnitDebuff("player", i))
            if auraType == "Stun" or auraType == "Fear" or auraType == "Charm" or auraType == "Root" then
                inCC = 1
                break
            end
        end
    end
    bits[#bits + 1] = inCC

    -- [59] Player Stealth (1 bit)
    local inStealth = 0
    for i = 1, 40 do
        local auraName = select(1, UnitBuff("player", i))
        if auraName then
            -- Check for common stealth auras
            if string.find(auraName or "", "Stealth") or string.find(auraName or "", "Shadow Meld") then
                inStealth = 1
                break
            end
        end
    end
    bits[#bits + 1] = inStealth

    -- [60] Player PvP Flagged (1 bit)
    local pvpFlag = 0
    if UnitIsPVP("player") then
        pvpFlag = 1
    end
    bits[#bits + 1] = pvpFlag

    return bits
end

-- =========================
-- FRAME ENCODING
-- =========================
-- Frames the payload data with sync bit for reliable decoding.
-- 
-- Frame Structure (60 bits):
-- Box 1     : Sync bit (always 1 = white)
-- Boxes 2-60: 59 data bits from payload
--
-- The sync bit allows external decoders to synchronize and
-- detect frame boundaries in the optical stream.
local function encodeFrame(payloadBits)
    local bits = {}

    -- Sync bit (always white = 1) for frame synchronization
    bits[1] = 1

    -- Payload data (59 bits, using ALL available space)
    for i = 1, 59 do
        bits[i + 1] = payloadBits[i] or 0
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
    COLS * BOX_SIZE + (COLS - 1) * BOX_GAP_X,
    ROWS * BOX_SIZE + (ROWS - 1) * BOX_GAP_Y
)

-- Anchor the display to screen top-left
local function applyAnchor()
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", UIParent, "TOPLEFT", OFFSET_X, OFFSET_Y)
end

root:RegisterEvent("PLAYER_LOGIN")
root:SetScript("OnEvent", applyAnchor)
applyAnchor()

-- Create the box grid
for i = 1, BOX_COUNT do
    local box = CreateFrame("Frame", nil, root)
    box:SetSize(BOX_SIZE, BOX_SIZE)

    -- Calculate row and column position
    local row = math.floor((i - 1) / COLS)
    local col = (i - 1) % COLS

    -- Position box relative to parent frame
    box:SetPoint(
        "TOPLEFT",
        col * (BOX_SIZE + BOX_GAP_X),
        -row * (BOX_SIZE + BOX_GAP_Y)
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

    -- Render frame to boxes (white = 1, black = 0)
    for i = 1, BOX_COUNT do
        if bits[i] == 1 then
            boxes[i].tex:SetColorTexture(1, 1, 1)  -- White
        else
            boxes[i].tex:SetColorTexture(0, 0, 0)  -- Black
        end
    end
end)
