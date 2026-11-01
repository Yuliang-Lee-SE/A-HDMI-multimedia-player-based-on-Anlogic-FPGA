# Runtime rotation period in the picture menu

## Key mapping

The latest main already uses every long-press gesture:

- physical KEY4: short AUTO/PLAY, long picture menu;
- physical KEY2: short next image, long transition setting;
- physical KEY3: short zoom, long volume.

To avoid another conflict, rotation period is the fourth item in the existing
picture menu:

- long KEY4: enter/leave the menu;
- short KEY4: select BRIGHT, CONTRAST, SHARP or ROTATE;
- KEY3: increase the selected value;
- KEY2: decrease the selected value.

The selected period is displayed in the menu and retained until reset. It is
not written to Flash.

## Implementation

- Period range: 1 to 30 seconds.
- Timer resolution: 100 ms.
- The timer uses a prescaler plus a small counter; it does not use a runtime
  multiplier.
- The period and a toggle are bundled across the 25 MHz to 100 MHz boundary.
- The player captures the period only on the synchronized toggle edge.

## Build

- SWNS: +0.122 ns
- HWNS: +0.003 ns
- LUT: 13249 / 19600
- BRAM: 54 / 64
- 32Kb BRAM: 12 / 16
- DSP: 12 / 29
- Same-seed unmodified main baseline: LUT 13299, BRAM 54, DSP 12

## Frame FIFO stability

The frame read FIFO previously used 256-word bursts from a 512-word FIFO.
Under SDRAM write/refresh contention this could leave only about 10 us of
prefetch margin. The stable build uses 128-word bursts, maintaining a deeper
minimum fill level, and blanks FIFO data when the read FIFO is empty instead of
displaying stale pixels.
