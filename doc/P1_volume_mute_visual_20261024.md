# P1 volume bar update

## Status

TD 6.2.168116 completed synthesis, place-and-route and bit generation. The
user reported that the r7 bit passed board testing on 2026-10-24.

| Item | Result |
| --- | --- |
| Bitstream | `D:\fpga_bit\P1_volume_only_20261024\P1_volume_only_r7_20261024.bit` |
| SHA256 | `A4634BC63E9B34687F271ED1666D3D7D0893D20A5843CD000ABA92FB6F97E7E5` |
| Setup | SWNS +0.106 ns, STNS 0 |
| Hold | HWNS +0.003 ns, HTNS 0 |
| PHY-5079 | 0 |
| Build errors | 0 |

## Interaction

- Short KEY3 press keeps the existing 1x, center 2x and 0.5x zoom cycle.
- Hold KEY3 for 1.2 seconds to move one step through 100%, 75%, 50%, 25%,
  mute and 100%.
- The volume bar is shown on the right for about two seconds after a change.
- The bottom segment lights first. The number of green segments grows upward
  with the volume.
- Mute has no screen icon. The volume bar disappears; audio is silent.

## Resource impact

| Resource | main baseline | visual update | Delta |
| --- | ---: | ---: | ---: |
| Synthesis LUT / 19600 | 10821 (55.21%) | 11074 (56.50%) | +253 |
| Routed LUT / 19600 | 11055 (56.40%) | 11322 (57.77%) | +267 |
| 9Kb BRAM / 64 | 54 | 54 | 0 |
| 32Kb BRAM / 16 | 12 | 12 | 0 |
| DSP / 29 | 4 | 4 | 0 |

`audio_osd` uses 83 LUT and no BRAM. The bar is a combinational overlay in the
existing video pixel path. The overall LUT percentage includes the already
integrated FAT32, zoom, OSD and audio functions and is not caused by P1 alone.

## Board checklist

| # | Action | Expected |
| --- | --- | --- |
| 1 | Short-press KEY3 three times | 1x, 2x and 0.5x cycle; no volume change |
| 2 | Long-press KEY3 | One volume step per hold |
| 3 | Check 25% | Only the bottom green segment lights |
| 4 | Check 50%, 75%, 100% | Two, three and four segments light from the bottom |
| 5 | Check mute | Passed: no icon, the bar disappears and audio is silent |
| 6 | Check image, waveform and caption | No pixel shift, tearing or layer overlap |

Two `PHY-7002` SDRAM placement critical warnings remain. The same two warnings
exist in the current main baseline construction.
