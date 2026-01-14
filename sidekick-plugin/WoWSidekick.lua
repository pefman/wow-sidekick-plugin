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
local ROWS = 2                    -- Number of rows
local BOX_COUNT = COLS * ROWS     -- Total boxes: 40

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
-- Encodes game state into 39 data bits.
-- Grid: 40 boxes (20x2) = 1 sync bit + 39 payload bits
--
-- Bit Layout (39 bits total):
--  [0-6]    : Player HP % (0-127)
--  [7-13]   : Target HP % (0-127)
--  [14-20]  : Player Resource % (0-127)
--  [21-25]  : Distance to Target (0-31 yards)
--  [26]     : In Combat (bool)
--  [27]     : Has Target (bool)
--  [28-32]  : Player Level (0-31)
--  [33-37]  : Target Level (0-31)
--  [38-40]  : Player Facing Direction (0-7 compass)
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
    -- 0=N, 1=NE, 2=E, 3=SE, 4=S, 5=SW, 6=W, 7=NW
    local facing = 0
    local playerFacing = GetPlayerFacing()
    if playerFacing then
        facing = math.floor((playerFacing / (2 * math.pi)) * 8) % 8
    end
    for _, b in ipairs(valueToBits(facing, 3)) do bits[#bits + 1] = b end

    return bits
end

-- =========================
-- FRAME ENCODING
-- =========================
-- Frames the payload data with sync bit for reliable decoding.
-- 
-- Frame Structure (40 bits):
-- Box 1     : Sync bit (always 1 = white)
-- Boxes 2-40: 39 data bits from payload
--
-- The sync bit allows external decoders to synchronize and
-- detect frame boundaries in the optical stream.
local function encodeFrame(payloadBits)
    local bits = {}

    -- Sync bit (always white = 1) for frame synchronization
    bits[1] = 1

    -- Payload data (39 bits, using ALL available space)
    for i = 1, 39 do
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
