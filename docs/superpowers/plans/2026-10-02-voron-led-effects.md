# Voron LED Effects Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redefine the Voron's LED effects in `overrides.cfg` — 50-LED caselight chain, informative state effects (progress bar, bed-temperature gauge), all lights off at print end, no idle relight.

**Architecture:** Overrides-only. Klipper merges duplicate sections (configparser, strict=False) and `overrides.cfg` is included last in `printer.cfg` (line 316, after the klippain lights files at 169–176), so every section defined here wins over klippain's; undeclared options (e.g. `run_on_error: true`) are retained from the merged section.

**Tech Stack:** Klipper + klippain (`ce8626c`) + julianschill/klipper-led_effect plugin. Config-only change — no code, no local test runner; hardware verification happens on the printer.

**Spec:** `docs/superpowers/specs/2026-10-02-voron-led-effects-design.md`

---

### Task 1: Apply both overrides.cfg edits (effects block + idle_timeout)

**Files:**
- Modify: `klipper/voron/overrides.cfg` (LED block at lines 173–209, `[idle_timeout]` gcode last line)

Note: the spec requires the effect deletion and the `SET_LED_EFFECT EFFECT=caselight_idle` removal to land together — both edits go into a single commit.

- [x] **Step 1: Replace the LED block (lines 173–209) with the new effect definitions**

Edit `klipper/voron/overrides.cfg`, old_string (exact, includes the commented block and its trailing line):

```
## On State - Rainbow
## On State - Rainbow (Idle)
[led_effect caselight_idle]
leds:
    neopixel:caselight
autostart:              true
frame_rate:             24
layers:
    breathing  10 1 top (0.3, 0.0, 0.0),(0.0, 0.3, 0.0),(0.0, 0.0, 0.3)

## Printing State - Solid White
[led_effect caselight_printing]
leds:
    neopixel:caselight
autostart:              false
frame_rate:             24
layers:
   static 0 0 top (0.30, 0.30, 0.30)

## Busy/Heating State - Red Comet
[led_effect caselight_busy]
leds:
    neopixel:caselight
autostart:              false
frame_rate:             24
layers:
    comet 1 1 top (0.5, 0.0, 0.0),(0.3, 0.0, 0.0)

 ## Printing State - Progress Bar
# [led_effect cl_printing]
# leds:
    # neopixel:caselight
# autostart:              false
# frame_rate:             24
# layers:
    # progress  -1  0 add         ( 1, 1, 1),( 0, 0.1, 0.6)
    # static     0  0 top         ( 1, 1, 1)
```

new_string:

```
# Caselight: 2x25 LED strips in series = 50 LEDs (klippain assumes 31)
[neopixel caselight]
chain_count: 50

## Idle State - Rainbow breathing
[led_effect cl_standby]
leds:
    neopixel:caselight
autostart: false
frame_rate: 24
layers:
    breathing 10 1 top (0.30, 0.0, 0.0),(0.0, 0.30, 0.0),(0.0, 0.0, 0.30)

## Busy State - Red comet
[led_effect cl_busy]
leds:
    neopixel:caselight
autostart: false
frame_rate: 24
layers:
    comet 1 1 top (0.5, 0.0, 0.0),(0.3, 0.0, 0.0)

## Heating State - Bed temperature gauge (0-110 C) + dim red base
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
## Printing State - Dim base + progress bar
[led_effect cl_printing]
leds:
    neopixel:caselight
autostart: false
frame_rate: 24
layers:
    progress -1 0 add (1.0, 1.0, 1.0),(0.0, 0.1, 0.4)
    static 0 0 top (0.05, 0.05, 0.07)

## Done Printing State - Everything off
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

## Off State - ALL LEDs off (klippain's cl_off only turns off LED #1)
[led_effect cl_off]
leds:
    neopixel:caselight
autostart: false
frame_rate: 24
layers:
    static 0 0 top (0.0, 0.0, 0.0)

## Critical error - both strips (klippain defines it twice; this wins)
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

- [x] **Step 2: Delete the `SET_LED_EFFECT` line from `[idle_timeout]`**

Edit `klipper/voron/overrides.cfg`, old_string:

```
        #TURN_OFF_HEATERS
        #M84
    {% endif %}
   SET_LED_EFFECT EFFECT=caselight_idle
```

new_string:

```
        #TURN_OFF_HEATERS
        #M84
    {% endif %}
```

- [x] **Step 3: Static check — section names are unique inside overrides.cfg**

Run: `grep -n "^\[neopixel\|^\[led_effect" klipper/voron/overrides.cfg`
Expected: each section name appears exactly once; the list is `neopixel caselight`, `cl_standby`, `cl_busy`, `cl_heating`, `cl_printing`, `cl_done_printing`, `sb_logo_done_printing`, `sb_nozzle_done_printing`, `cl_off`, `critical_error`.

- [x] **Step 4: Static check — no dangling references**

Run: `grep -rn --exclude='*.bak' "caselight_idle\|caselight_printing\|caselight_busy" klipper/`
Expected: no results (skip `overrides.cfg.bak`, which still contains the old names). If any real file matches, the edits are incomplete.

- [x] **Step 5: Commit both edits together**

```bash
git add klipper/voron/overrides.cfg
git commit -m "voron: redesign caselight effects (50 LEDs, gauge, progress bar, off at print end, no idle relight)"
```

### Task 2: Final consistency check + printer verification

**Files:**
- Read: `klipper/voron/overrides.cfg` (LED block + idle_timeout)

- [x] **Step 1: Diff the new block against the spec's concrete config**

Run: extract the block from overrides.cfg and diff against `docs/superpowers/specs/2026-10-02-voron-led-effects-design.md` config block.
Expected: identical except for the added `## ... State ...` section comments and the `(klippain assumes 31)` suffix on the `# Caselight: 2x25...` header line. Do not "fix" those as drift.

- [x] **Step 2: Sanity review checklist**

Confirm each of these by reading the final file:
1. `chain_count: 50` under `[neopixel caselight]`.
2. `cl_off` has no index on `neopixel:caselight` (whole strip).
3. `critical_error` lists both `neopixel:caselight` and `neopixel:status_leds`; no `run_on_error` line (retained from klippain merge).
4. `cl_printing` lists `progress` first, `static` last.
5. `cl_heating` uses `temperaturegauge` (no underscore) and `heater: heater_bed`.
6. `[idle_timeout]` gcode no longer contains `SET_LED_EFFECT`.

- [ ] **Step 3: Commit any drift fixes; then hardware verification (user, on the printer)**

After syncing this repo to the printer and restarting Klipper:
1. `RESTART` completes with no config errors.
2. `STATUS_LEDS COLOR=off` → all 50 caselight LEDs dark.
3. `STATUS_LEDS COLOR=on` → whole strip white.
4. During bed heating → gauge fills toward 110 °C over a dim red base.
5. During a print → dim white base + white/blue progress bar filling the strip.
6. End print → all LEDs off; `SET_IDLE_TIMEOUT TIMEOUT=10` and wait → still off.
7. Filter runs 10 min post-print, then stops (unchanged behavior).

- [ ] **Step 4: Push (user decides)**

Ask the user whether to push to `origin/main` (the printer sync path is outside this repo's control).
