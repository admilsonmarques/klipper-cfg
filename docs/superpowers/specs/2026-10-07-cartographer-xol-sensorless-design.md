# Cartographer v4 + Xol Carriage + Sensorless Homing — Design Spec

Date: 2026-10-07
Printer: Voron 2.4 350mm (A4T toolhead, Rapido UHF hotend, EBB toolhead board, Manta M8P v2, CANbus 500k)
Klippain: updated on the Pi (supports `cartographer_touch.cfg`)

## Context

The printer currently runs the A4T toolhead (Rapido UHF) with Voron TAP as probe (virtual Z endstop, calibrated `z_offset: -0.852`). The user is upgrading:

1. **Carriage**: switch to the Armchair Xol carriage (A4T toolhead mounts on it — A4T cowlings have "[xol-carriage]" variants).
2. **Probe**: Cartographer v4 **CAN** replacing TAP entirely (TAP mechanism removed).
3. **Homing**: X and Y move to sensorless homing (the Xol carriage does not actuate the physical endstop switches).

Config is Klippain-based; user files live in `klipper/voron/` (printer.cfg, mcu.cfg, overrides.cfg, variables.cfg, …). Klippain lives on the Pi as a separate git repo; `printer.cfg` includes reference `config/…` paths into it.

## Findings (from research)

1. **Klippain main now has native Cartographer support** — `config/hardware/probes/cartographer_touch.cfg` (the installed copy predates it; user already updated Klippain on the Pi).
   - Profile sets `probe_type_enabled: "cartographer_touch"`, `probe_contact_z_home_mode: "none"` (G28 Z uses scan-mode virtual endstop), `probe_contact_z_home_startprint_mode: "hook"` (START_PRINT runs `contact_z_home` → `_PROBE_HOOK_CONTACT_Z_HOME` → `CARTOGRAPHER_TOUCH_HOME` after QGL, before bed mesh). Contact temperature guard active.
   - Ship default `[cartographer] y_offset: 15` is a placeholder; real value must be set by user.
2. **Cartographer v4 plugin** (`Cartographer3D/cartographer3d-plugin`) registers the `probe` printer object (`register_as_probe: True`, `add_object("probe", …)`); it never reads a `[probe]` config section. Any leftover `[probe]` section breaks startup: with the include order here (`[cartographer]` loads first) Klipper's config validation aborts with `Option '<key>' is not valid in section 'probe'` (unused-section check); the reversed order would raise `Printer object 'probe' already created`. **Both** `[probe]` sections must be removed: the TAP one in overrides.cfg (with its `z_offset: -0.852`) **and** the one in mcu.cfg (EBB remap block, `pin: ^toolhead:PROBE_INPUT`).
3. **CAN bitrate**: bus is 500k (`system-cfg/can0`); Cartographer V4 ships at 1M. Must flash V4 with **CAN 500K** firmware before connecting to the bus (mixed bitrates kill the bus). The V4 exposes a working USB port; `cartographer_firmware/fw_update.sh` detects the device, and the Cartographer API returns the device UUID. Firmware 500K V4 images exist (combined Katapult+CAN and app-only).
4. **Probe module length**: Armchair A4T README states *"A4T uses standard length probe modules for Xol-Carriage (even with UHF hotends in A4T)"*. The user printed `Carto_v4_Module_UHF.stl`; the standard `Carto_v4_Module.stl` is the documented choice. Physical acceptance criterion either way: coil **2.6–3.0 mm above the nozzle tip** (Cartographer docs). User will verify which module to use.
5. **X/Y offset**: community values for Xol carriage + Cartographer vary (Klippain default 15; ~21.1 for Xol2/A4T in one reference config; 26.0 in another). Plan: start `x_offset: 0, y_offset: 21.1` and **verify physically** after install.
6. **Sensorless homing (Manta M8P v2, TMC2209)**:
   - DIAG jumpers exist per motor slot; M1 DIAG → PF4 (`MCU_M1_STOP`), M2 DIAG → PF3 (`MCU_M2_STOP`). Jumpers must be installed for X (M1) and Y (M2).
   - Klippain's `sensorless_TMC2209.cfg` uses `diag_pin: ^X_STOP` / `^Y_STOP`, but the user's aliases are crossed (`X_STOP=MCU_M2_STOP`, `Y_STOP=MCU_M1_STOP`) — the template pins would read the wrong driver's DIAG. Must override with explicit MCU pins.
   - TMC2209 `driver_SGTHRS`: 0–255, **255 = most sensitive** (matches the user's "start very sensitive" requirement; the template ships 255).
   - Klippain homing_override reduces run_current to `sensorless_current_factor` (75%) during sensorless homing — gentler stall contact.
   - Klippain TMC2209 axis templates already set `stealthchop_threshold: 0` (required for stallGuard).
   - Klippain `mcu.cfg` currently overrides `[stepper_x] endstop_pin: ^toolhead:X_STOP` (the file's own comment: "Uncomment … if not using sensorless homing"). Since mcu.cfg is included **after** the sensorless file, it would override `tmc2209_stepper_x:virtual_endstop` and break X homing. Must be removed/commented.
   - Klipper's sensorless prerequisite `homing_retract_dist: 0` is already satisfied by Klippain (axis default-speed templates, and `cartographer_touch.cfg` for Z) — no extra change needed.

## Requirements

- Cartographer v4 CAN works as the only probe: scan homing (G28 Z), touch home before prints, QGL, bed mesh.
- Sensorless homing on X and Y, tuned safely (start at maximum sensitivity; no toolhead crashes).
- Existing calibrations not tied to TAP stay valid (PID, input shaper, PA, mesh settings).
- All changes in the user's repo files only; klippain itself untouched.
- Config committed to git before hardware work starts (rollback point).

## Design

### Approach

Klippain-native integration: swap the probe include, add `[mcu cartographer]`, override offsets and diag pins in `overrides.cfg`. No custom macros.

### Hardware

1. **Probe module**: user verifies printed `Carto_v4_Module_UHF.stl` vs reprint `Carto_v4_Module.stl` (standard, per A4T docs). Criterion: coil 2.6–3.0 mm above nozzle tip. If reprinting: ABS, Nevermore filter on.
2. **Carriage**: install Xol carriage + A4T toolhead; remove the TAP mechanism. Watch the A4T README warnings (slimmer idlers / XY-joint clearance for build-plate area).
3. **DIAG jumpers**: install on Manta M8P v2 slots M1 (X) and M2 (Y). Without them the stall is never detected.
4. **Cartographer wiring**: CAN H/L spliced into the toolhead CAN line (Y-split at the EBB end) + 24V/GND from the EBB; route through the carriage cable channel.
5. **Firmware**: flash V4 with CAN 500K via USB **before** connecting it to the bus. Pin the version: the newest V4 image with a 500K variant is **6.1.0** (the 6.2.0 set is 1M/USB only); `fw_update.sh` filters `firmware_list.csv` by probe/link/speed and resolves to 6.1.0 — do not manually pick "latest". Get the UUID (Cartographer API or `canbus_query.py can0` after flash).

### Config changes (repo)

1. **`klipper/voron/printer.cfg`**
   - Line 102: `[include config/hardware/probes/voron_tap.cfg]` → `[include config/hardware/probes/cartographer_touch.cfg]`
   - Line 251: uncomment `[include config/software/sensorless_homing/sensorless_TMC2209.cfg]`
2. **`klipper/voron/mcu.cfg`**
   - Remove/comment the `[stepper_x] endstop_pin: ^toolhead:X_STOP` block (lines 163–166) — must not override the sensorless virtual endstop.
   - Remove/comment the `[probe]` block (lines 154–156, EBB remap: `pin: ^toolhead:PROBE_INPUT`) — leftover `[probe]` conflicts with the plugin's registered `probe` object.
   - Add `[mcu cartographer]` section with `canbus_uuid: <uuid>`.
3. **`klipper/voron/overrides.cfg`**
   - Remove the `[probe]` section (TAP pin + `z_offset: -0.852`) — conflicts with the plugin's registered `probe` object.
   - Add `[cartographer]` override: `x_offset: 0`, `y_offset: 21.1` (initial estimate; verify physically, adjust).
   - Add `[tmc2209 stepper_x] diag_pin: ^MCU_M1_STOP` and `[tmc2209 stepper_y] diag_pin: ^MCU_M2_STOP` (crossed-alias correction).
   - After tuning: add final `driver_SGTHRS` values for X and Y.

### Software on the Pi

- ✅ Klipper + Klippain updated (user already done).
- Install the plugin: `curl -s -L https://raw.githubusercontent.com/Cartographer3D/cartographer3d-plugin/refs/heads/main/scripts/install.sh | bash -s -- --klipper ~/klipper --klippy-env ~/klippy-env`.
- Add moonraker `update_manager` entries for the plugin and `cartographer_firmware` repo.

### Calibration & test sequence

Order matters: `CARTOGRAPHER_SCAN_CALIBRATE` / `CARTOGRAPHER_TOUCH_CALIBRATE` hard-fail unless X/Y are homed ("Must home x and y before calibration"), and X/Y can only be homed through the sensorless path. Sequence: motion-free checks → sensorless tuning → cartographer calibration → validation.

**A. Motion-free bring-up** (no homing needed):
1. Power on; `CARTOGRAPHER_QUERY` responds; streamed distance changes when the head is moved by hand (motors off).
2. Physical checks: coil height 2.6–3.0 mm above nozzle tip; static XY offset measurement (coil center to nozzle, calipers) — refine later with the marked-point method once homing works.

**B. Sensorless tuning** (riskiest part — done with maximum sensitivity first):
1. **Before any G28**: establish Z clearance by hand (the head starts at an unknown Z; Klippain z-hops only 5 mm and forces a full G28 when X/Y are unhomed). Keep the print bed away / nozzle visibly clear of the plate.
2. With `driver_SGTHRS: 255`, arm the M112 protocol and run `G28`. **The first sensorless X/Y home IS the 255 test** — expect an early stop (false trigger). If the axis does not stop → `M112` immediately; fix jumpers/diag wiring. Wait ~2 s between attempts (stall flag clearing).
3. Lower SGTHRS in steps until X travels fully to the physical limit → `max_sensitivity`.
4. Keep lowering until a single clean stop, no banging → `min_sensitivity`.
5. Final: `min + (max - min)/3`, rounded. Repeat for Y. Put final values in `overrides.cfg`.
6. Note: Z-scan homing itself requires X/Y homed and the head over the bed — it cannot "lift the head" from an unhomed state.

**C. Cartographer calibration** (X/Y now homed):
1. `CARTOGRAPHER_SCAN_CALIBRATE` (scan model; note: `CARTOGRAPHER_CALIBRATE` is a deprecated stub in the current plugin and prints a rename warning without calibrating) → `SAVE_CONFIG`.
2. `CARTOGRAPHER_TOUCH_CALIBRATE` (nozzle touch at center) → `SAVE_CONFIG`.
3. Verify XY offset with the marked-point method; adjust `x_offset`/`y_offset` in overrides.cfg if needed.

**D. Validation**:
1. Full G28 (X, Y sensorless; Z scan), QGL, bed mesh (9×9, saved config unchanged).
2. First-layer print (ABS, current parameters) + babystep → adjust z_offset (touch model) if needed.
3. Full test print; verify Klippain's adaptive bed mesh (its own `adaptive_bed_mesh.cfg`, included by `bed_mesh_350mm.cfg` — there is no KAMP install in this repo) still behaves.

### Risks

- **Wrong diag pin / missing jumpers** → no stall detection → crash. Mitigated by SGTHRS=255 start + immediate-M112 protocol.
- **y_offset uncertainty** (15 vs 21.1 vs 26 across sources) → mandatory physical verification before dense meshing.
- **Module length mismatch** (UHF vs standard) → coil outside 2.6–3.0 mm band degrades accuracy; user verifies at install.
- **Klippain update side effects** → repo commit before changes; klippain is a git clone (revertable).

### Out of scope (future options)

- Cartographer's built-in accelerometer for input shaper (current toolhead ADXL345 stays).
- Denser scan meshes (Cartographer can scan fast; current 9×9 kept initially).
- `[temperature_sensor cartographer_mcu]` monitoring.

## Sources

- Klippain: [cartographer_touch.cfg](https://github.com/Frix-x/klippain/blob/main/config/hardware/probes/cartographer_touch.cfg), [virtual_z_probes.md](https://github.com/Frix-x/klippain/blob/main/docs/features/virtual_z_probes.md), [sensorless_TMC2209.cfg](https://github.com/Frix-x/klippain/blob/main/config/software/sensorless_homing/sensorless_TMC2209.cfg)
- Armchair: [Xol-Toolhead](https://github.com/Armchair-Heavy-Industries/Xol-Toolhead), [A4T README](https://github.com/Armchair-Heavy-Industries/A4T)
- Cartographer: [plugin](https://github.com/Cartographer3D/cartographer3d-plugin), [firmware](https://github.com/Cartographer3D/cartographer_firmware), [Klipper setup docs](https://docs.cartographer3d.com/cartographer-probe/installation-and-setup/software-configuration/klipper-setup.md), [probe installation](https://docs.cartographer3d.com/cartographer-probe/installation-and-setup/probe-installation.md)
- Klipper: [sensorless homing procedure](https://www.klipper3d.org/TMC_Drivers.html#sensorless-homing)
- Manta M8P v2 DIAG pins: [BTT issue #117](https://github.com/bigtreetech/Manta-M8P/issues/117), [DeepWiki pin mapping](https://deepwiki.com/bigtreetech/Manta-M8P/8.1-v2.0-complete-pin-mapping)
- Community offsets: [SierraSoftworks voron-config](https://github.com/SierraSoftworks/voron-config)
