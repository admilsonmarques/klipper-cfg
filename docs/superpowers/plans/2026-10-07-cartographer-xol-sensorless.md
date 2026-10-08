# Cartographer v4 + Xol Carriage + Sensorless Homing Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Voron TAP with a Cartographer v4 CAN probe (A4T toolhead on Xol carriage) and enable sensorless homing on X/Y (TMC2209 on Manta M8P v2), tuned safely from maximum sensitivity.

**Architecture:** Klippain-native integration — swap the probe include to `cartographer_touch.cfg`, add `[mcu cartographer]` to mcu.cfg, override offsets + DIAG pins in overrides.cfg (included last, so redefinitions win via config merge). No custom macros. Repo is deployed to the Pi via git (`~/klipper-cfg`, moonraker-managed; origin `admilsonmarques/klipper-cfg`).

**Tech Stack:** Klipper + klippain (updated on Pi), `cartographer3d-plugin` (installed into `~/klippy-env`), `cartographer_firmware` repo (flash helper + firmware images), CANbus 500k, TMC2209 sensorless homing.

**Spec:** `docs/superpowers/specs/2026-10-07-cartographer-xol-sensorless-design.md`

**Pi paths:** klipper at `~/klipper`, venv at `~/klippy-env`, config at `~/printer_data/config`, repo at `~/klipper-cfg`.

---

### Task 1: Pi software — install Cartographer plugin + repos + moonraker entries

**Files:**
- Modify: `klipper/voron/moonraker.conf` (add update_manager entries at the end)

- [ ] **Step 1.1: Pre-flight — confirm the Klippain clone has Cartographer support + the deployment mapping**

```bash
ls ~/printer_data/config/config/hardware/probes/cartographer_touch.cfg
ls -la ~/printer_data/config/printer.cfg
```

Expected: the cartographer include file exists (the whole plan hinges on it); the `ls -la` shows whether printer.cfg is a symlink into `~/klipper-cfg` or a plain copy — Steps 4.11 and 6.3 assume `git pull` and SAVE_CONFIG land in the same file, so confirm this now and note which case applies. If the include file is missing, `cd` to the klippain clone and `git pull` (user already updated it).

- [ ] **Step 1.2: Install the plugin into klippy-env**

On the Pi (SSH):

```bash
curl -s -L https://raw.githubusercontent.com/Cartographer3D/cartographer3d-plugin/refs/heads/main/scripts/install.sh | bash -s -- --klipper ~/klipper --klippy-env ~/klippy-env
```

Expected: script completes without errors; `~/klippy-env/bin/pip show cartographer3d-plugin` prints a version (1.9.x+).

- [ ] **Step 1.3: Clone the firmware + katapult repos (flash tools)**

```bash
cd ~ && git clone https://github.com/Cartographer3D/cartographer_firmware.git
cd ~ && git clone https://github.com/Arksine/katapult
```

Expected: `~/cartographer_firmware/fw_update.sh` and `~/katapult/scripts/flashtool.py` exist.

- [ ] **Step 1.4: Add moonraker update_manager entries**

Edit `klipper/voron/moonraker.conf` — append at the end:

```
[update_manager cartographer_plugin]
type: python
channel: stable
project_name: cartographer3d-plugin
virtualenv: ~/klippy-env
managed_services: klipper

[update_manager Cartographer Firmware]
type: git_repo
path: ~/cartographer_firmware
origin: https://github.com/Cartographer3D/cartographer_firmware.git
primary_branch: main
managed_services: klipper
```

(Note: the key is `project_name:` — moonraker has no `package:` option; with the wrong key the updater row never appears.)

- [ ] **Step 1.5: Commit + deploy**

```bash
git add klipper/voron/moonraker.conf
git commit -m "voron: add cartographer plugin/firmware moonraker update managers"
git push
```

On the Pi: `cd ~/klipper-cfg && git pull && sudo systemctl restart moonraker`
Expected: moonraker restarts clean (Mainsail Machine tab shows the two new entries).

---

### Task 2: Bench flash — V4 to CAN 500K firmware 6.1.0

No bus connection yet. Probe in hand, USB cable to the Pi. **Do not use `fw_update.sh` here** — it detects the probe only from config (`[mcu cartographer]`), which doesn't exist until Task 4, and would skip flashing. Flash by explicit path instead.

- [ ] **Step 2.1: Get the device UUID from the API**

```bash
DEVICE_NAME=$(basename "$(ls /dev/serial/by-id/usb-Cartographer_stm32g431xx_* | head -n1)")
curl -s "https://api.cartographer3d.com/q/device_name/$DEVICE_NAME" | jq -r '.device_uuid'
```

Expected: a UUID like `4c9911db8a41` (12 hex chars). Write it down — it goes into `mcu.cfg` (Task 4) and the CAN flash (Task 3). If `jq` is missing on the Pi, the raw JSON also contains the UUID — read `device_uuid` from the output by eye (or `grep -o '"device_uuid"[^,]*'`).

- [ ] **Step 2.2: Enter the bootloader and flash the katapult-deployer (500K)**

```bash
cd ~/klipper/scripts
~/klippy-env/bin/python -c "import flash_usb as u; u.enter_bootloader('/dev/serial/by-id/$DEVICE_NAME')"
KATAPULT_DEVICE=""
for i in {1..15}; do
    KATAPULT_DEVICE=$(ls /dev/serial/by-id/ 2>/dev/null | grep -i katapult | head -n1)
    [[ -n "$KATAPULT_DEVICE" ]] && break
    sleep 2
done
echo "Katapult device: $KATAPULT_DEVICE"   # if empty after ~30s: power-cycle the probe and retry from enter_bootloader
cd ~/cartographer_firmware/firmware/v4/katapult-deployer/
~/klippy-env/bin/python ~/katapult/scripts/flashtool.py -f katapult_deployer_v4_CAN_500K.bin -d "/dev/serial/by-id/$KATAPULT_DEVICE"
```

Expected: flashtool reports success. The probe is now a Katapult CAN bootloader node at **500K** — ready to be wired to the bus. Unplug USB.

- [ ] **Step 2.3: Fallback (only if the probe never appears on USB)**

If `/dev/serial/by-id/usb-Cartographer_*` does not exist (factory-CAN firmware without USB serial): use the DFU method. The V4 has **no boot button** — bridge the **BT0 and 3V3 holes** with tweezers while plugging in USB, then confirm DFU mode:

```bash
lsusb | grep 0483:df11   # expected: the STM32 in DFU mode
cd ~/cartographer_firmware/firmware/v4/combined-firmware/6.1.0/
sudo dfu-util -R -a 0 -s 0x08000000:leave -D Katapult_plus_CartographerV4_6.1.0_CAN_500K.bin -d 0483:df11
```

Expected: dfu-util success (the `:leave` reboots the probe); the probe now has both katapult and app at 500K — skip the CAN flash in Task 3, get the UUID from `canbus_query.py can0` after wiring.

---

### Task 3: Hardware — carriage, module, jumpers, wiring

No config changes in this task. Physical work; no commit expected (unless a note file is wanted).

- [ ] **Step 3.1: Probe module — verify UHF vs standard**

Per the A4T README, A4T on Xol carriage uses the **standard** length module (`Carto_v4_Module.stl`) even with UHF hotends; the user printed `Carto_v4_Module_UHF.stl`. Decision criterion: with the module mounted and the toolhead assembled, the Cartographer coil must sit **2.6–3.0 mm above the nozzle tip**. If the UHF module gives that gap, keep it; otherwise print `Carto_v4_Module.stl` (ABS, Nevermore filter on) and use it.

- [ ] **Step 3.2: Install Xol carriage + A4T toolhead; remove TAP**

Follow the [Xol-Toolhead docs](https://github.com/Armchair-Heavy-Industries/Xol-Toolhead/tree/main/docs) and [A4T README](https://github.com/Armchair-Heavy-Industries/A4T) assembly guides. Remove the TAP mechanism entirely (A4T stays, Rapido UHF stays). Watch the A4T warnings: slim idlers / XY-joint clearance for build-plate area.

- [ ] **Step 3.3: DIAG jumpers on the Manta M8P v2**

Install the DIAG jumpers for slots **M1** (X motor) and **M2** (Y motor). M1 DIAG → PF4 (`MCU_M1_STOP`), M2 DIAG → PF3 (`MCU_M2_STOP`). Without these, stallGuard never fires and homing crashes.

- [ ] **Step 3.4: Wire the Cartographer**

**5V only — never 24V (permanent damage).** Power: 5V + GND from the EBB's **probe port** (freed by the TAP removal). The EBB36/42 v1.2 probe port carries GND, 5V, 24V, PB8, PB9 — **verify the 5V/GND pin positions with a multimeter (or the v1.2-specific pinout diagram) before plugging; V1.0 diagrams differ from V1.1/V1.2**. CAN H/L spliced into the toolhead CAN line (Y-split at the EBB end), twisted pair. Physical X/Y endstop switches stay unplugged-safe (their config pins go away in Task 4). Verify coil height (2.6–3.0 mm) and measure coil-to-nozzle X/Y with calipers (compare against `x_offset: 0, y_offset: 21.1` later).

- [ ] **Step 3.5: Flash the app firmware over CAN (500K)**

The probe is now a Katapult node on the bus (deployer from Step 2.2). Verify it's visible, then flash the 6.1.0 app:

```bash
~/klippy-env/bin/python ~/klipper/scripts/canbus_query.py can0   # shows a katapult node with your UUID
cd ~/cartographer_firmware/firmware/v4/firmware/6.1.0/
~/klippy-env/bin/python ~/katapult/scripts/flashtool.py -i can0 -f CartographerV4_6.1.0_CAN_500K_full_8kib_offset.bin -u <UUID>
```

Expected: flashtool success; `canbus_query.py can0` now shows "Cartographer V4" at 500K. (If Step 2.3's DFU path was used, skip this step.)

---

### Task 4: Config changes — repo

**Files:**
- Modify: `klipper/voron/printer.cfg` (probe include line 102; sensorless include line 251)
- Modify: `klipper/voron/mcu.cfg` (remove `[probe]` block lines 154–156; comment X endstop block lines 163–166; append `[mcu cartographer]`)
- Modify: `klipper/voron/overrides.cfg` (replace `[probe]` block lines 126–137 with `[cartographer]` override; add sensorless section)

One commit per file, atomic.

- [ ] **Step 4.1: printer.cfg — swap the probe include**

old_string:

```
## Voron TAP, also used naturally as a virtual Z endstop
[include config/hardware/probes/voron_tap.cfg]
```

new_string:

```
## Voron TAP, also used naturally as a virtual Z endstop
# [include config/hardware/probes/voron_tap.cfg]

## Cartographer probe also used as virtual Z endstop. Do not forget to install the plugin and add the [mcu cartographer] section to make it work!
[include config/hardware/probes/cartographer_touch.cfg]
```

- [ ] **Step 4.2: printer.cfg — enable sensorless homing include**

old_string:

```
# [include config/software/sensorless_homing/sensorless_TMC2209.cfg]
```

new_string:

```
[include config/software/sensorless_homing/sensorless_TMC2209.cfg]
```

- [ ] **Step 4.3: Commit printer.cfg**

```bash
git add klipper/voron/printer.cfg
git commit -m "voron: switch probe from TAP to cartographer_touch + enable sensorless homing include"
```

- [ ] **Step 4.4: mcu.cfg — remove the EBB [probe] block**

old_string:

```
[probe]
pin: ^toolhead:PROBE_INPUT

[fan]
```

new_string:

```
[fan]
```

(A leftover `[probe]` section makes Klipper refuse to start once the plugin registers the `probe` object.)

- [ ] **Step 4.5: mcu.cfg — comment the X endstop override**

old_string:

```
[stepper_x]
endstop_pin: ^toolhead:X_STOP
```

new_string:

```
# [stepper_x]
# endstop_pin: ^toolhead:X_STOP
```

(mcu.cfg is included after the sensorless file; an active `endstop_pin` here would override `tmc2209_stepper_x:virtual_endstop`.)

- [ ] **Step 4.6: mcu.cfg — add [mcu cartographer]**

Append at the end of the file (replace `<UUID>` with the UUID from Step 2.1):

```
#--------------------------------------------#
#    Cartographer v4 CAN probe MCU ###########
#--------------------------------------------#

[mcu cartographer]
canbus_uuid: <UUID>
```

- [ ] **Step 4.7: Commit mcu.cfg**

```bash
git add klipper/voron/mcu.cfg
git commit -m "voron: add cartographer mcu, remove TAP probe pin and X endstop override"
```

- [ ] **Step 4.8: overrides.cfg — replace the TAP [probe] block with [cartographer] override**

old_string:

```
[probe]
pin: !toolhead:PROBE_INPUT
x_offset: 0
y_offset: 0
# z_offset: 0.4
z_offset: -0.852 # PROBE_CALIBRATE (-0.827) + babystep +0.025 (first-layer test, 2026-09-02). More negative = nozzle higher.
```

new_string:

```
## Cartographer (TAP removed 2026-10, Xol carriage + sensorless homing).
## Old TAP z_offset -0.852 does not apply: z_offset now lives in the touch_model
## sections written by CARTOGRAPHER_TOUCH_CALIBRATE + SAVE_CONFIG.
[cartographer]
x_offset: 0
y_offset: 21.1 # initial estimate for Xol carriage — verify physically (Task 5), then update
```

- [ ] **Step 4.9: overrides.cfg — add sensorless DIAG pin corrections**

Append at the end of the file:

```
#-------------------------#
#   Sensorless homing     #
#-------------------------#

## Manta M8P v2: X motor in slot M1 (DIAG -> PF4 = MCU_M1_STOP), Y in slot M2 (DIAG -> PF3 = MCU_M2_STOP).
## klippain's sensorless_TMC2209.cfg uses the crossed X_STOP/Y_STOP aliases, so pin the correct DIAGs here.
[tmc2209 stepper_x]
diag_pin: ^MCU_M1_STOP

[tmc2209 stepper_y]
diag_pin: ^MCU_M2_STOP

## driver_SGTHRS final values go here after tuning (Task 5):
# [tmc2209 stepper_x]
# driver_SGTHRS: <tuned>
# [tmc2209 stepper_y]
# driver_SGTHRS: <tuned>
```

- [ ] **Step 4.10: Commit overrides.cfg**

```bash
git add klipper/voron/overrides.cfg
git commit -m "voron: cartographer offsets + sensorless diag pins (remove TAP z_offset)"
```

- [ ] **Step 4.11: Deploy to the Pi + restart Klipper**

```bash
git push
```

On the Pi:

```bash
cd ~/klipper-cfg && git pull
sudo systemctl restart klipper
grep -i error ~/printer_data/logs/klippy.log | tail -20
```

Expected: klipper starts; log shows no config errors; `[mcu cartographer]` connects (the probe is now on the bus at 500k). If "Unable to open canbus uuids" appears, check wiring/power and re-run `canbus_query.py can0`.

---

### Task 5: Bring-up + sensorless tuning (riskiest phase)

On the printer. SGTHRS starts at 255 (template default = maximum sensitivity). M112 protocol armed for every homing attempt.

- [ ] **Step 5.1: Motion-free checks**

In Mainsail console:

```
CARTOGRAPHER_QUERY
```

Expected: returns a coil distance/frequency reading. With motors off, move the head by hand — the streamed distance must change. Then check coil height 2.6–3.0 mm above nozzle (physical).

- [ ] **Step 5.2: First homing attempt = the 255 test**

Establish Z clearance by hand first (nozzle visibly clear of the plate; the head starts at unknown Z). Arm M112. Send:

```
G28 X Y
```

Expected: X stops **early** (false trigger, before the physical limit). If an axis does NOT stop → **M112 immediately**, power off, fix DIAG jumpers/wiring (Step 3.3), retry. Wait ~2 s between attempts; between attempts return the carriage near rail center by hand (M84 first — klippain's backoff is only a few mm).

- [ ] **Step 5.3: Tune X — find max_sensitivity**

Lower SGTHRS live and re-home X until it travels fully to the physical limit:

```
SET_TMC_FIELD STEPPER=stepper_x FIELD=SGTHRS VALUE=230
G28 X
```

Repeat with decreasing values (230 → 210 → 190 → …). The highest value that still lets X reach the limit is `max_sensitivity`. (Klippain's `homing_speed: 40`; if homing is unreliable/bangy at 40, lower `homing_speed` for `[stepper_x]`/`[stepper_y]` in overrides.cfg — Klipper suggests ~20 mm/s for these axes.)

- [ ] **Step 5.4: Tune X — find min_sensitivity**

Keep lowering until X still homes with a single clean stop, no banging (contact gets harder as SGTHRS drops). The lowest such value is `min_sensitivity`. Final X value = `min + (max - min)/3`, rounded.

- [ ] **Step 5.5: Repeat for Y**

Same procedure with `stepper_y` and `G28 Y`.

- [ ] **Step 5.6: Persist SGTHRS in overrides.cfg**

Uncomment and fill the two placeholders added in Step 4.9:

```
[tmc2209 stepper_x]
driver_SGTHRS: <final X>

[tmc2209 stepper_y]
driver_SGTHRS: <final Y>
```

- [ ] **Step 5.7: Commit + deploy**

```bash
git add klipper/voron/overrides.cfg
git commit -m "voron: tune sensorless homing SGTHRS (X=<x>, Y=<y>)"
git push
```

On the Pi: `cd ~/klipper-cfg && git pull && sudo systemctl restart klipper`
Then `G28 X Y` again — expected: clean homing on both axes with the persisted values.

---

### Task 6: Cartographer calibration

X/Y homing now works; Z-scan homing still needs the scan model (this task creates it).

- [ ] **Step 6.1: Scan model calibration**

Heat the bed to 100 °C (ABS printing temperature — the model is temperature-specific). With X/Y homed:

```
G28 X Y
CARTOGRAPHER_SCAN_CALIBRATE
```

The macro defaults to `method = manual`: it prompts for a low Z position — jog the nozzle to ~0.1 mm above the bed (paper test), then send `ACCEPT`. (Alternative: `CARTOGRAPHER_SCAN_CALIBRATE METHOD=touch`.) Then:

```
SAVE_CONFIG
```

Expected: the probe scans and calibrates; `SAVE_CONFIG` writes `[cartographer scan_model default]` into printer.cfg. (Do NOT use `CARTOGRAPHER_CALIBRATE` — it is a deprecated stub in the current plugin.)

- [ ] **Step 6.2: Touch calibration**

Bed back to ambient, nozzle clean:

```
CARTOGRAPHER_TOUCH_CALIBRATE
SAVE_CONFIG
```

Expected: nozzle touches the bed center (samples, then saves `[cartographer touch_model default]` with the z_offset).

- [ ] **Step 6.3: Sync the SAVE_CONFIG block back to the repo**

On the Pi, the auto-generated block was written into printer.cfg (through the `~/klipper-cfg` checkout if printer.cfg is a symlink into it — verify with `ls -la ~/printer_data/config/printer.cfg`; if it is a plain copy, copy the new sections manually). Then:

```bash
cd ~/klipper-cfg && git add klipper/voron/printer.cfg && git commit -m "voron: cartographer scan/touch calibration (SAVE_CONFIG)" && git push
```

- [ ] **Step 6.4: XY offset verification (marked-point)**

Mark a point on the bed (tape + dot). Home, then move the nozzle over the mark and note X/Y; offset by `x_offset`/`y_offset` and query the probe distance — minimum distance must align with the mark. If off by more than ~0.5 mm, measure the real offsets and update `[cartographer]` in overrides.cfg (commit + deploy, same flow as Step 4.10/4.11).

---

### Task 7: Validation

- [ ] **Step 7.1: Full homing + QGL + mesh**

```
G28
QUAD_GANTRY_LEVEL
BED_MESH_CALIBRATE
```

Expected: first full `G28` now completes (scan model loaded) — X/Y sensorless, Z scan. QGL converges. Mesh range still sane (bed profile similar in shape to the old one).

- [ ] **Step 7.2: First layer + babystep**

Print a first-layer test (ABS, current slicer parameters). Babystep if needed; if the offset is consistently off, run `CARTOGRAPHER_TOUCH_CALIBRATE` again (Step 6.2) rather than chasing with babystep.

- [ ] **Step 7.3: Full test print**

Standard test print. Verify: START_PRINT sequence (soak → QGL → `contact_z_home` touch → adaptive mesh) runs clean, no skipped steps, first layer even, no homing errors at speed.

- [ ] **Step 7.4: Input shaper re-check**

The toolhead mass changed (TAP removed, Xol carriage) — the existing input-shaper values are stale. Run `SHAPER_CALIBRATE` with the mounted ADXL345 and apply the new values.

- [ ] **Step 7.5: Final commit**

Commit any remaining SAVE_CONFIG changes and the plan's completion:

```bash
git add -A
git commit -m "voron: cartographer + sensorless homing validation passes"
git push
```

Then update `docs/superpowers/plans/2026-10-07-cartographer-xol-sensorless.md` checkboxes to reflect completion.

---

### Troubleshooting quick reference

| Symptom | Cause | Fix |
|---|---|---|
| Axis doesn't stop at 255 | DIAG jumper missing / diag_pin wrong | M112; check M1/M2 jumpers, `^MCU_M1_STOP`/`^MCU_M2_STOP` in overrides |
| "Must home x and y before calibration" | Calibration before X/Y homed | `G28 X Y` first (Task 6) |
| "Scan model not loaded" on G28 Z | Scan model missing | Run Step 6.1 + SAVE_CONFIG before full G28 |
| `Option '<key>' is not valid in section 'probe'` at startup | Leftover `[probe]` section | Remove all `[probe]` blocks (mcu.cfg, overrides.cfg) |
| klipper can't find cartographer MCU | Probe not on bus / wrong bitrate | Verify deployer+app flash were 500K (Steps 2.2/3.5); `canbus_query.py can0` |
| Bangy sensorless homing | homing_speed too high | Lower `homing_speed` for stepper_x/y in overrides.cfg |
| CARTOGRAPHER_CALIBRATE prints rename warning | Old macro name | Use CARTOGRAPHER_SCAN_CALIBRATE |
