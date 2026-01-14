# WoW Sidekick Optical Protocol (Schema v2 – JSON Array)

This document is the canonical blueprint for the optical stream.

## Physical layout
- Grid: 20 columns × 5 rows = 200 boxes
- Read order: left‑to‑right, top‑to‑bottom
- 8‑color encoding (3 bits per box)
- Total bits per frame: 200 × 3 = 600 bits

## Bit values (3‑bit colors)
Each box represents a 3‑bit value using this palette:

| Value | Color | RGB |
|---:|---|---|
| 0 | Black | (0, 0, 0) |
| 1 | White | (255, 255, 255) |
| 2 | Red | (255, 0, 0) |
| 3 | Green | (0, 255, 0) |
| 4 | Blue | (0, 0, 255) |
| 5 | Cyan | (0, 255, 255) |
| 6 | Magenta | (255, 0, 255) |
| 7 | Yellow | (255, 255, 0) |

## Payload format (Schema v2)
The payload is a **fixed‑length JSON array (75 chars)**, padded with spaces on the right if needed.
Each character is encoded as 8 bits (MSB‑first), producing exactly 600 bits per frame.

### JSON array order
```
[schema, hp, thp, res, dist, inCombat, hasTarget, plvl, tlvl, facing,
 pClass, tClass, pBuffs, tDebuffs, isCasting, inCC, posX, posY]
```

#### Field notes
- `schema`: schema version (current = 2)
- `hp`, `thp`, `res`: 0–127
- `dist`: 0–31 yards
- `inCombat`, `hasTarget`, `isCasting`, `inCC`: 0/1
- `plvl`, `tlvl`: 0–60+ (raw level)
- `facing`: 0–7 compass
- `pClass`, `tClass`: 0–12
- `pBuffs`, `tDebuffs`: 0–7 (count capped)
- `posX`, `posY`: 0–99 (map position percent)

## Decoder notes
- No dedicated sync bit; decode from the fixed grid and frame timing.
- Use `schema` as the version switch.
- JSON is ASCII, MSB‑first per byte.
