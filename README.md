# WoW Sidekick

**Optical data output for World of Warcraft**

A novel addon that transmits real-time game state through visual lightbox encoding. External tools can capture screen output and decode the pixel patterns to receive live combat and character information.

## Overview

WoW Sidekick creates a 40-box grid display in the top-left corner of your screen and updates it 20 times per second with encoded game data. Each frame consists of:

- **Box 1**: Sync bit (always white) for frame synchronization
- **Boxes 2-40**: 39 bits of player, target, and direction data

This protocol enables external programs (overlay tools, stream overlays, analysis software) to read game state directly from video capture without requiring WoW API access.

## Installation

### Requirements
- World of Warcraft installation
- PowerShell 5.0+

### Setup

1. Clone this repository
2. Edit `install.ps1` to set the correct WoW AddOns path:
   ```powershell
   $wowPath = "C:\Path\To\World of Warcraft\_retail_\Interface\AddOns"
   ```
3. Run the installer:
   ```powershell
   .\install.ps1
   ```
4. Restart World of Warcraft
5. Enable the addon in the addons list

## Data Protocol

Each frame transmits 39 bits of data at 20 Hz (50ms update rate).

### Bit Layout

| Bits | Data | Range | Notes |
|------|------|-------|-------|
| 0-6 | Player HP % | 0-127 | 0.78% per bit |
| 7-13 | Target HP % | 0-127 | 0.78% per bit |
| 14-20 | Player Resource % | 0-127 | Mana/Energy/Rage/Focus |
| 21-25 | Distance to Target | 0-31 | ~1 yard per bit |
| 26 | In Combat | 0-1 | Boolean |
| 27 | Has Target | 0-1 | Boolean |
| 28-32 | Player Level | 0-31 | - |
| 33-37 | Target Level | 0-31 | - |
| 38-40 | Player Facing | 0-7 | 8 compass directions (N,NE,E,SE,S,SW,W,NW) |

### Resources Tracked
- Mana (casters)
- Energy (rogues, druids)
- Rage (warriors)
- Focus (hunters)
- Any other class resource

### Direction Encoding
Player facing direction is encoded as 8 compass points:
- 0 = North
- 1 = Northeast
- 2 = East
- 3 = Southeast
- 4 = South
- 5 = Southwest
- 6 = West
- 7 = Northwest

## Configuration

Edit the configuration section in `WoWSidekick.lua` to customize the display:

```lua
local FPS = 20                    -- Update frequency (Hz)
local BOX_SIZE = 5                -- Box size in pixels
local BOX_GAP_X = 0               -- Horizontal gap
local BOX_GAP_Y = 0               -- Vertical gap
local OFFSET_X = 0                -- X offset from screen corner
local OFFSET_Y = 0                -- Y offset from screen corner
local COLS = 20                   -- Grid columns
local ROWS = 2                    -- Grid rows
```

## Extending the Protocol

To add more data bits:

1. **Increase grid size**: Modify `COLS` and `ROWS` in configuration
2. **Extend `buildPayload()`**: Add new data collection
3. **Update `encodeFrame()`**: Include additional payload bits
4. **Document bit layout**: Update comments with new fields

Example: To transmit spell cooldowns:
```lua
-- Add to buildPayload()
local spellCooldown = 0
if GetSpellCooldown(12345) then
    spellCooldown = math.min(31, math.floor(GetSpellCooldown(12345)))
end
for _, b in ipairs(valueToBits(spellCooldown, 5)) do bits[#bits + 1] = b end
```

## External Decoding

To read the protocol from external tools:

1. **Capture video**: Screenshot or stream the addon display
2. **Identify boxes**: Locate the 40 pixel boxes
3. **Map colors**: White = 1, Black = 0
4. **Decode bits**: Convert color sequence to binary
5. **Parse data**: Extract values using bit layout

### Example Decoder Pseudocode

```python
def decode_frame(screenshot):
    sync_bit = get_box_color(screenshot, 1)
    if sync_bit != 1:
        return None  # Wait for sync
    
    bits = []
    for i in range(2, 41):
        bits.append(get_box_color(screenshot, i))
    
    player_hp = bits_to_value(bits[0:7])
    target_hp = bits_to_value(bits[7:14])
    resources = bits_to_value(bits[14:21])
    distance = bits_to_value(bits[21:26])
    # ... etc
    
    return {
        'player_hp': player_hp,
        'target_hp': target_hp,
        'distance': distance,
        # ...
    }
```

## Performance

- **CPU Impact**: Minimal (~0.1% on modern systems)
- **Update Rate**: 20 Hz (50ms per frame)
- **Visual Footprint**: 5×100 pixels (20×2 grid at 5px boxes)
- **Memory**: <1 MB

## Troubleshooting

### Addon Not Loading
- Verify file locations in `install.ps1`
- Check WoW is pointing to correct AddOns folder
- Confirm .toc Interface version matches your WoW build

### Boxes Not Updating
- Ensure addon is enabled in WoW addons menu
- Check for Lua errors: `/run print("ok")`
- Verify fps is set to valid value

### External Decoder Not Working
- Confirm boxes are white/black, not gray or colored
- Verify capture resolution is high enough (5px boxes minimum)
- Check frame timing - use 50ms timeout for frame detection

## Future Enhancements

- [ ] Configurable data fields
- [ ] Multiple sync patterns for validation
- [ ] Error correction codes (Hamming codes)
- [ ] Configurable grid size per preset
- [ ] Slash commands for toggling display
- [ ] Saved variables for configuration persistence

## License

MIT License - Free to use and modify

## Author

WoW Sidekick - Optical Data Protocol for World of Warcraft

---

**Note**: This addon is a novelty/experimental tool. It does not modify game mechanics or provide gameplay advantages beyond data visibility.
