# WoW Sidekick

**Optical data output for World of Warcraft**

A novel addon that transmits real-time game state through visual lightbox encoding. External tools can capture screen output and decode the pixel patterns to receive live combat and character information.

## Overview

WoW Sidekick renders a 200‑box grid (20×5) in the top‑left corner and encodes game state into **8 colors** (3 bits per box). Each frame is a fixed‑length **75‑char JSON array** (600 bits total). External tools can capture the grid and decode the JSON without WoW API access.

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

The canonical schema is documented in [PROTOCOL.md](PROTOCOL.md). The current protocol is:

- **Grid**: 20 columns × 5 rows (200 boxes)
- **Encoding**: 8 colors → 3 bits per box
- **Payload**: 75‑char JSON array (600 bits per frame)
- **Schema version**: 2

## Configuration

Use the in‑game options panel (Interface → AddOns → WoW Sidekick):

- **Enable auto‑loot**
- **Update rate (FPS)**: 5/10/20/30
- **Show JSON debug window** (selectable text)

Visual layout settings (box size, offsets, etc.) are still editable in [sidekick-plugin/WoWSidekick.lua](sidekick-plugin/WoWSidekick.lua).

## Extending the Protocol

Update the JSON array order in `buildPayload()` and the schema notes in [PROTOCOL.md](PROTOCOL.md). Keep the JSON length at 75 chars (pad with spaces on the right) so the payload remains 600 bits.

## External Decoding

1. Capture the grid (20×5 boxes).
2. Map each box color to a 3‑bit value using the palette in [PROTOCOL.md](PROTOCOL.md).
3. Concatenate 600 bits (MSB‑first within each 3‑bit value).
4. Convert to 75 ASCII bytes and parse the JSON array.

## Performance

- **CPU Impact**: Minimal on modern systems
- **Default Update Rate**: 10 FPS (configurable)
- **Visual Footprint**: 20×5 grid (box size configurable)

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
- Confirm 8‑color palette mapping and 20×5 grid order
- Verify MSB‑first bit order
- The JSON payload is exactly 75 bytes (right‑padded with spaces)

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
