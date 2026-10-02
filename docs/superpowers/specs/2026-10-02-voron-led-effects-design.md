# Voron LED Effects — Design Spec

Date: 2026-10-02
Printer: Voron (klippain `ce8626c` + julianschill/klipper-led_effect plugin)

## Context

The printer has two neopixel groups:

- **Caselight**: 2×25 LED strips in series = **50 physical LEDs** (klippain assumes 31)
- **Toolhead (StealthBurner)**: 3 LEDs — 1 logo (face) + 2 nozzle (bottom), matching klippain's mapping (logo=1, nozzle=2,3 in 1-based plugin syntax)

Effects are driven by klippain state macros calling `STATUS_LEDS COLOR=...`, which (with effects enabled) fires `SET_LED_EFFECT` for `cl_*` (caselight) and `sb_logo_*`/`sb_nozzle_*` (toolhead) effects.

## Findings (from config review)

1. `chain_count: 31` on the caselight — the last 19 physical LEDs never receive data. Root cause of "not all LEDs are used".
2. `cl_off` (klippain, still on `main`) targets `neopixel:caselight (1)` — plugin indices are **1-based**, so only the first LED turns off; 30 stay lit.
3. `caselight_idle`, `caselight_printing`, `caselight_busy` in overrides.cfg are dead: state macros call `cl_*` names, not these. Only `caselight_idle` is wired (via the custom `[idle_timeout]`).
4. `[led_effect critical_error]` is defined in both included effects files. Klipper merges duplicate sections silently (last include wins) — effectively toolhead-only.
5. The custom `[idle_timeout]` only sets the caselight effect, leaving toolhead LEDs in their previous state.

## Requirements

- All 50 caselight LEDs used (chain_count fixed).
- Effects informative: progress bar during printing, bed-temperature gauge during heating, clear per-state colors.
- At end of print: **all LEDs off** and stay off until next interaction (idle_timeout must not relight).
- Filter: unchanged — the existing 10-min post-print timer (`variable_filter_default_time_on_end_print: 600`) already covers this. No threshold logic.
- Keep klippain untouched; all changes via `overrides.cfg` (included last, so redefinitions win via config merge).

## Design

Approach: **overrides-only** (klippain files intact).

### Caselight states (redefined `cl_*` sections)

| State | Effect |
|---|---|
| idle (`cl_standby`) | RGB breathing (user's existing style) |
| busy (`cl_busy`) | Red comet across the strip |
| heating (`cl_heating`) | Bed temperature gauge (0→110 °C, orange→red) + dim red breathing base |
| printing (`cl_printing`) | Dim white base (see the part) + white/blue progress bar filling the strip |
| done (`cl_done_printing`) | Static black — **off** |
| off (`cl_off`) | Static black on **all** LEDs (fixes klippain bug) |
| critical error | Red strobe on **both** strips (fixes duplicate-section merge) |

Sub-states (`cl_homing`, `cl_leveling`, `cl_meshing`, `cl_calibrating_z`, `cl_cleaning`) stay klippain stock.

### Toolhead

- Stock `sb_*` effects kept, except `sb_logo_done_printing` and `sb_nozzle_done_printing` redefined to static black so the whole machine goes dark at print end.

### idle_timeout

- Remove the `SET_LED_EFFECT EFFECT=caselight_idle` line. Keep the M118/M117 warnings.

### Cleanup of dead effects

- Delete `caselight_idle`, `caselight_printing`, `caselight_busy` and the commented `cl_printing` progress-bar block from overrides.cfg. `caselight_idle` has `autostart: true` and would otherwise auto-start at boot and have its frames summed with the active effect until klippain's `STATUS_LEDS` replaces it. Deleting the effect makes the removal of the `SET_LED_EFFECT EFFECT=caselight_idle` line in `[idle_timeout]` mandatory — both edits must land together.

### Filter

- No changes. 10-min post-print run is already implemented by klippain (`end_print`/`cancel_print` → `_STOP_FILTER_DELAYED`).

## Concrete config (overrides.cfg)

```ini
# Caselight: 2x25 LED strips in series = 50 LEDs
[neopixel caselight]
chain_count: 50

[led_effect cl_standby]
leds:
    neopixel:caselight
autostart: false
frame_rate: 24
layers:
    breathing 10 1 top (0.30, 0.0, 0.0),(0.0, 0.30, 0.0),(0.0, 0.0, 0.30)

[led_effect cl_busy]
leds:
    neopixel:caselight
autostart: false
frame_rate: 24
layers:
    comet 1 1 top (0.5, 0.0, 0.0),(0.3, 0.0, 0.0)

[led_effect cl_heating]
leds:
    neopixel:caselight
autostart: false
frame_rate: 24
heater: heater_bed
layers:
    temperaturegauge 0 110 add (1.0, 0.25, 0.0),(0.9, 0.05, 0.0)
    breathing 4 0.3 add (0.35, 0.0, 0.0)

# Layer order matters: the first line is the topmost layer. The static
# base must be listed last, otherwise it wipes the progress bar.
[led_effect cl_printing]
leds:
    neopixel:caselight
autostart: false
frame_rate: 24
layers:
    progress -1 0 add (1.0, 1.0, 1.0),(0.0, 0.1, 0.4)
    static 0 0 top (0.05, 0.05, 0.07)

[led_effect cl_done_printing]
leds:
    neopixel:caselight
autostart: false
frame_rate: 24
layers:
    static 0 0 top (0.0, 0.0, 0.0)

[led_effect sb_logo_done_printing]
leds:
    neopixel:status_leds (1)
autostart: false
frame_rate: 24
layers:
    static 0 0 top (0.0, 0.0, 0.0)

[led_effect sb_nozzle_done_printing]
leds:
    neopixel:status_leds (2,3)
autostart: false
frame_rate: 24
layers:
    static 0 0 top (0.0, 0.0, 0.0)

[led_effect cl_off]
leds:
    neopixel:caselight
autostart: false
frame_rate: 24
layers:
    static 0 0 top (0.0, 0.0, 0.0)

[led_effect critical_error]
leds:
    neopixel:caselight
    neopixel:status_leds
autostart: false
frame_rate: 24
layers:
    strobe 1 1.5 add (1.0, 1.0, 1.0)
    breathing 2 0 difference (0.95, 0.0, 0.0)
    static 1 0 top (1.0, 0.0, 0.0)
```

`[idle_timeout]`: delete the `SET_LED_EFFECT EFFECT=caselight_idle` line (keep warnings).

## Out of scope

- Toolhead `sb_*` effects beyond `done_printing`
- Chamber temperature sensor / filter threshold logic
- Filter behavior changes
- KlipperScreen integration changes

## Verification

1. Klipper restart loads cleanly (no config errors).
2. `SET_LED_EFFECT EFFECT=cl_printing` + simulate progress: bar spans the full 50-LED strip.
3. `STATUS_LEDS COLOR=off`: all 50 LEDs dark.
4. End a print: all LEDs off; set `SET_IDLE_TIMEOUT TIMEOUT=10` to verify they stay off after the timeout fires (instead of waiting 1 h).
5. Filter still runs 10 min post-print (`variable_filter_default_time_on_end_print: 600`).
6. Heating: gauge fills toward 110 °C as bed heats.
7. No second effect is left enabled on the caselight (the plugin sums overlapping effects — a leftover autostart effect would show light even when "off").

## Gotchas

- Plugin LED indices are 1-based in config (`(1)` = first physical LED).
- Klipper merges duplicate sections; `overrides.cfg` is included last, so its options win. Options not redeclared (e.g. `run_on_error: true` on `critical_error`) are retained from klippain's definition.
- Layer keywords are derived from the class name with no underscores: it is `temperaturegauge`, not `temperature_gauge` — a wrong keyword aborts Klipper startup.
- Layers are applied bottom-up: the **first** line in `layers:` is the topmost. A `top`-blend static base must be the **last** line or it wipes the layers above it.
- `progress` layer reads `display_status.progress` — works with Mainsail/Fluidd uploads.
