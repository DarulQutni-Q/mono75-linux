# VortexSeries Mono 75 USB HID Protocol & Reverse-Engineering Specification

## 1. Hardware Overview & Identification

The **VortexSeries Mono 75** is a 75% compact mechanical keyboard equipped with 83 mechanical switches and a clickable rotary encoder (knob). The keyboard controller is manufactured by **China Resource Semico Co., Ltd.**, a common OEM silicon provider for gaming peripherals.

### Hardware Identification
| Parameter | Value | Notes |
|:---|:---|:---|
| **Device Name** | VortexSeries Mono 75 | Branded mechanical keyboard |
| **OEM Product** | SEMICO USB Gaming Keyboard | Firmware device string |
| **Vendor ID (VID)** | `0x1A2C` | China Resource Semico Co., Ltd. |
| **Product ID (PID)** | `0x6380` | Mono 75 / K102 Controller |
| **USB Class** | `0x03` (HID) | Human Interface Device |
| **Layout Codename** | `KB-K102` | From official driver `config.xml` |
| **Keyboard Type** | `101` | 75% ANSI layout (83 keys + knob) |
| **Official App Version** | `1.0.3.5` (`DeviceDriver.exe` / `XYUI.dll`) | Windows vendor software |
| **Firmware Upstream** | `keyboard-680/680H/firmware/` | Hosted on Tencent Cloud COS |

---

## 2. USB HID Endpoints & Report Descriptors

The keyboard presents **two USB HID interfaces** to the host operating system:

```
                      [VortexSeries Mono 75 (1A2C:6380)]
                                      │
           ┌──────────────────────────┴──────────────────────────┐
           ▼                                                     ▼
     Interface 0                                           Interface 1
  (/dev/hidraw0, input0)                                (/dev/hidraw1, input1)
           │                                                     │
 ┌─────────┴─────────┐                  ┌────────────────────────┴────────────────────────┐
 │ Standard Boot KB  │                  │ Composite HID Endpoint                          │
 │ - 8-byte 6KRO     │                  │  ├─ Report ID 0x01: Consumer Control (Knob)     │
 │ - 1-byte LED OUT  │                  │  ├─ Report ID 0x02: System Control (Sleep/Wake) │
 └───────────────────┘                  │  ├─ Report ID 0x03: Vendor Input               │
                                        │  ├─ Report ID 0x04..0x06: NKRO Bitmaps         │
                                        │  └─ Report ID 0x07: Vendor Config (64 bytes)    │
                                        └─────────────────────────────────────────────────┘
```

### 2.1 Interface 0 (`input0` / `/dev/hidraw0`): Standard Boot Keyboard
Interface 0 provides backward compatibility with BIOS/UEFI boot loaders:
- **Usage Page**: `0x0001` (Generic Desktop)
- **Usage**: `0x0006` (Keyboard)
- **Reports**: Standard 8-byte 6KRO input reports (1 modifier byte, 1 reserved byte, 6 simultaneous keycodes) and 1-byte LED output report (Num Lock, Caps Lock, Scroll Lock).

### 2.2 Interface 1 (`input1` / `/dev/hidraw1`): Composite Vendor, Media & NKRO
Interface 1 multiplexes multimedia controls, full N-Key Rollover, and the vendor configuration channel using Report IDs:

| Report ID | Usage Page | Usage | Description |
|:---:|:---:|:---:|:---|
| `0x01` | `0x000C` (Consumer) | `0x0001` (Consumer Control) | 16-bit multimedia & knob events (Vol+, Vol-, Mute) |
| `0x02` | `0x0001` (Generic Desktop) | `0x0080` (System Control) | 3-bit power management (Sleep, Wake, Power Down) |
| `0x03` | `0xFF00` (Vendor-Defined) | `0x0001` (Vendor Usage 1) | 8-bit vendor diagnostic input |
| `0x04` | `0x0007` (Keyboard) | `0x0000..0x002F` | NKRO Modifier byte (8 bits) + Key usage bitmap 0–47 |
| `0x05` | `0x0007` (Keyboard) | `0x0030..0x0067` | NKRO Key usage bitmap 48–103 |
| `0x06` | `0x0007` (Keyboard) | `0x0068..0x009F` | NKRO Key usage bitmap 104–159 |
| `0x07` | `0xFF01` (Vendor Config) | `0x0001` (Vendor Config) | **Bidirectional Configuration Channel** (63-byte payload) |

### 2.3 Report ID 0x07 Specification (Vendor Configuration)
The vendor configuration interface is defined in the HID Report Descriptor as:
```
06 01 FF        Usage Page (Vendor-Defined 0xFF01)
09 01           Usage (0x01)
A1 01           Collection (Application)
85 07             Report ID (0x07)
09 03             Usage (0x03)
15 00             Logical Minimum (0)
26 FF 00          Logical Maximum (255)
75 08             Report Size (8 bits)
95 3F             Report Count (63 bytes)
B1 02             Feature (Data, Variable, Absolute)
09 04             Usage (0x04)
15 00             Logical Minimum (0)
26 FF 00          Logical Maximum (255)
75 08             Report Size (8 bits)
95 3F             Report Count (63 bytes)
91 02             Output (Data, Variable, Absolute)
C0              End Collection
```

- **Wire Packet Size**: Exactly **64 bytes** (`1 byte Report ID` + `63 bytes Data Payload`).
- **Transfer Mechanism**: Supported via HID **Set_Report / Get_Report** (Feature Report) or raw writes to `/dev/hidraw1`.

### 2.4 Linux Device Discovery
To unambiguously locate the configuration interface regardless of USB port enumeration order, inspect `/sys/class/hidraw/hidraw*/device/report_descriptor` and verify the presence of bytes `06 01 FF` (`Usage Page 0xFF01`):
```python
def find_hidraw():
    for p in Path("/sys/class/hidraw").iterdir():
        uevent = (p / "device/uevent").read_text()
        if "1A2C" in uevent.upper() and "6380" in uevent.upper():
            desc = (p / "device/report_descriptor").read_bytes()
            if b"\x06\x01\xff" in desc:
                return f"/dev/{p.name}"
    return None
```

---

## 3. Command Opcodes & Packet Specifications

All configuration packets sent to Report ID `0x07` follow this 64-byte structure:

```
Byte 0      Byte 1      Byte 2        Byte 3        Byte 4 .. 63
┌───────────┬───────────┬─────────────┬─────────────┬───────────────────────────┐
│ Report ID │ Command   │ Arg 0 /     │ Arg 1 /     │ Remaining Parameters /    │
│  (0x07)   │  Opcode   │ Sub-command │ Length      │ Zero Padding (0x00)       │
└───────────┴───────────┴─────────────┴─────────────┴───────────────────────────┘
```

### 3.1 Command Opcode Summary Table
| Opcode | Name | Direction | Description |
|:---:|:---|:---:|:---|
| `0x01` | `CMD_INFO` | IN/OUT | Query firmware version, MCU status, and device metadata |
| `0x12` | `CMD_KEYMAP` | OUT | Remap physical keys to custom HID usage codes per layer |
| `0x23` | `CMD_PROFILE` | OUT | Profile / macro data block transfer |
| `0x76` | `CMD_LIGHT_FRAME` | OUT | Write backlight layer frame and brightness state |
| `0x99` | `CMD_RGB_DATA` | OUT | Stream per-key RGB LED color chunks (intermediate packets) |
| `0xAB` | `CMD_COMMIT` | OUT | Commit staged changes from MCU RAM to internal Flash/EEPROM |
| `0xF0` | `CMD_RESET` | OUT | Factory reset keyboard settings to firmware defaults |
| `0xFE` | `CMD_LIGHT_MODE` | OUT | Set preset lighting mode, speed, brightness, and primary RGB |
| `0xFF` | `CMD_PER_KEY_RGB` | OUT | Final per-key RGB LED color chunk & latch custom RGB mode |

---

### 3.2 Command Packet Deep Dives

#### 3.2.1 `CMD_INFO` (0x01) - Device & Firmware Query
- **Purpose**: Retrieves the active firmware version and MCU configuration status.
- **Request Packet (Host -> Device)**:
  ```
  Byte 0       : 0x07 (Report ID)
  Byte 1       : 0x01 (CMD_INFO)
  Byte 2 .. 63 : 0x00 (Padding)
  ```
- **Response Packet (Device -> Host)**:
  ```
  Byte 0       : 0x07 (Report ID echo)
  Byte 1       : 0x01 (CMD_INFO echo)
  Byte 2 .. 5  : Firmware version string (ASCII, e.g. "1.00") or BCD version bytes
  Byte 6 .. 7  : Active profile index / hardware status flags
  Byte 8 .. 63 : Extended vendor status data
  ```

#### 3.2.2 `CMD_LIGHT_MODE` (0xFE) - Preset Lighting Animation
- **Purpose**: Activates one of the 21 built-in lighting animations and sets animation attributes.
- **Packet Structure**:
  ```
  Byte 0       : 0x07 (Report ID)
  Byte 1       : 0xFE (CMD_LIGHT_MODE)
  Byte 2       : Mode Index (1 to 21)
  Byte 3       : Brightness (0 to 4: 0 = Off, 4 = Maximum)
  Byte 4       : Animation Speed (0 to 4: 0 = Slowest, 4 = Fastest)
  Byte 5       : Primary Red (0x00 to 0xFF)
  Byte 6       : Primary Green (0x00 to 0xFF)
  Byte 7       : Primary Blue (0x00 to 0xFF)
  Byte 8 .. 63 : 0x00 (Padding)
  ```
- **Commit**: Must be followed by `CMD_COMMIT` (0xAB) after a ~50ms delay.

#### 3.2.3 `CMD_KEYMAP` (0x12) - Key Remapping
- **Purpose**: Remaps a physical key switch on a specific layer to an arbitrary HID Usage code.
- **Packet Structure**:
  ```
  Byte 0       : 0x07 (Report ID)
  Byte 1       : 0x12 (CMD_KEYMAP)
  Byte 2       : Layer Index (0x00 = Base Layer, 0x01 = Fn Layer)
  Byte 3       : Source HID Code (Physical key default usage, e.g. 0x39 for CapsLock)
  Byte 4       : Target Usage Code (Target HID usage low byte, e.g. 0xE0 for L_Ctrl)
  Byte 5       : Target Usage Page:
                   0x07 = Standard Keyboard/Keypad
                   0x0C = Consumer / Multimedia
                   0x00 = Key Disabled
  Byte 6 .. 63 : 0x00 (Padding)
  ```
- **Commit**: Persist to flash with `CMD_COMMIT` (0xAB).

#### 3.2.4 `CMD_LIGHT_FRAME` (0x76) - Backlight Frame Parameters
- **Purpose**: Controls global lighting layer state and master brightness level.
- **Packet Structure**:
  ```
  Byte 0       : 0x07 (Report ID)
  Byte 1       : 0x76 (CMD_LIGHT_FRAME)
  Byte 2       : Layer Index (0x00)
  Byte 3       : Reserved (0x00)
  Byte 4       : Brightness (0x00 to 0x04)
  Byte 5 .. 63 : 0x00 (Padding)
  ```

#### 3.2.5 `CMD_RGB_DATA` (0x99) & `CMD_PER_KEY_RGB` (0xFF) - Per-Key Custom RGB Streaming
- **Purpose**: Transmits per-key 24-bit RGB values to the keyboard LED matrix.
- **Protocol Flow**:
  1. The keyboard matrix contains up to 84 indexed LED positions (maximum `light_index` = 101 due to sparse matrix addressing).
  2. The RGB payload is divided into chunks of **20 keys (60 bytes)** per packet.
  3. Intermediate packets use opcode `0x99` (`CMD_RGB_DATA`).
  4. The final packet uses opcode `0xFF` (`CMD_PER_KEY_RGB`).
- **Packet Structure**:
  ```
  Byte 0       : 0x07 (Report ID)
  Byte 1       : 0x99 (Intermediate chunk) OR 0xFF (Final chunk)
  Byte 2       : Chunk Index (0-based: 0, 1, 2, 3, ...)
  Byte 3       : Key Count in Chunk (e.g. 20 for full chunks, 4 for final chunk)
  Byte 4 .. 63 : RGB Triplets: [R0, G0, B0, R1, G1, B1, ..., Rn-1, Gn-1, Bn-1]
  ```
- **Activation Sequence**:
  1. Stream all chunks (`0x99` ... `0x99` -> `0xFF`).
  2. Send `CMD_LIGHT_FRAME` (`0x76`) with brightness level.
  3. Send `CMD_COMMIT` (`0xAB`) to latch and display colors.

#### 3.2.6 `CMD_COMMIT` (0xAB) - Flash Persistence
- **Purpose**: Flushes configuration buffers from volatile MCU RAM into onboard Flash memory.
- **Packet Structure**:
  ```
  Byte 0       : 0x07 (Report ID)
  Byte 1       : 0xAB (CMD_COMMIT)
  Byte 2 .. 63 : 0x00 (Padding)
  ```

---

## 4. Lighting Modes Reference (Modes 1 to 21)

Extracted from `KB-K102.xml` and English localization resource `1033.lan`:

| Mode | Official English Name (`1033.lan`) | Nama singkat | XML Mode ID | XML Attribute | Animation Description | Supported Params |
|:---:|:---|:---|:---:|:---:|:---|:---|
| **1** | **Steady** | Static | 1 | 1 | Solid color across all keys | Brightness, RGB |
| **2** | **Light Off** | Off | 2 | 257 | Turns all key LEDs completely off | None |
| **3** | **Breathing** | Breathing | 3 | 3 | Pulsing brightness fade in and out | Brightness, Speed, RGB |
| **4** | **Windmill** | Wave | 4 | 3 | Rotating rainbow wave pattern across keys | Brightness, Speed |
| **5** | **Neon_stream** | Reactive | 5 | 3 | Keys illuminate upon press and fade | Brightness, Speed, RGB |
| **6** | **Streamer** | Ripple | 6 | 3 | Circular color ripples expanding from pressed key | Brightness, Speed |
| **7** | **Flowing light and color** | Color Cycle | 7 | 3 | Smoothly cycles through spectrum | Brightness, Speed |
| **8** | **Dripping ripples** | Rain | 8 | 3 | Vertical rain animation across columns | Brightness, Speed |
| **9** | **Brilliant point** | Random | 9 | 3 | Random keys twinkle independently | Brightness, Speed |
| **10** | **Flash away** | Star | 10 | 3 | Fast streak/shooting star animations | Brightness, Speed |
| **11** | **Shadow_disappear** | Fire | 11 | 3 | Ambient flame flicker along base | Brightness, Speed |
| **12** | **Ripples shining** | Snake | 12 | 3 | Serpentine line snaking through rows | Brightness, Speed |
| **13** | **Rich and honored** | Brick | 13 | 3 | Stepped block-by-block fill animation | Brightness, Speed |
| **14** | **Marquee effect** | Custom Layer | 14 | 3 | Perimeter chase effect | Brightness, Speed |
| **15** | **Rotating storm** | Color Wheel | 15 | 3 | Vortex rotation centered on matrix | Brightness, Speed |
| **16** | **Serpentine horse race** | Neon | 16 | 3 | Fast multi-color trace racer | Brightness, Speed |
| **17** | **Stars twinkle** | Aurora | 17 | 3 | Northern lights shimmer wave | Brightness, Speed |
| **18** | **Retro_snake** | Raindrop | 18 | 3 | Pixelated drops falling sporadically | Brightness, Speed |
| **19** | **Diagonal transformation** | Explosion | 19 | 3 | Diagonal sweep / burst across keyboard | Brightness, Speed |
| **20** | **Sine wave** | Heartbeat | 20 | 3 | Double sine-wave oscillation | Brightness, Speed |
| **21** | **Custom mode / Music** | Custom Per-Key | 21 | 512 | Custom per-key RGB matrix map | Per-key RGB stream |

### Parameter Value Ranges
- **Brightness**: Integer `0` to `4` (`0` = Off, `1` = 25%, `2` = 50%, `3` = 75%, `4` = 100%).
- **Speed**: Integer `0` to `4` (`0` = Slowest, `2` = Normal/Default, `4` = Fastest).
- **RGB Color**: 3 bytes `[R, G, B]`, each `0` to `255` (`0x00` to `0xFF`).

---

## 5. Physical Key Layout & Mapping Table (`KB-K102.xml`)

The Mono 75 matrix layout defines **83 active physical keys** arranged across 6 physical rows and a 20-column electrical matrix:

| Key Name | Default HID Usage | Key Index (`key_index`) | LED Matrix Index (`light_index`) | Electrical Matrix (`row#col`) | Legend Description |
|:---|:---:|:---:|:---:|:---:|:---|
| **Esc** | `0x29` (41) | 0 | 0 | `0#0` | Escape |
| **F1** | `0x3A` (58) | 12 | 12 | `0#2` | Function 1 |
| **F2** | `0x3B` (59) | 18 | 18 | `0#3` | Function 2 |
| **F3** | `0x3C` (60) | 24 | 24 | `0#4` | Function 3 |
| **F4** | `0x3D` (61) | 30 | 30 | `0#5` | Function 4 |
| **F5** | `0x3E` (62) | 36 | 36 | `0#6` | Function 5 |
| **F6** | `0x3F` (63) | 42 | 42 | `0#7` | Function 6 |
| **F7** | `0x40` (64) | 48 | 48 | `0#8` | Function 7 |
| **F8** | `0x41` (65) | 54 | 54 | `0#9` | Function 8 |
| **F9** | `0x42` (66) | 60 | 60 | `0#10` | Function 9 |
| **F10** | `0x43` (67) | 66 | 66 | `0#11` | Function 10 |
| **F11** | `0x44` (68) | 72 | 72 | `0#12` | Function 11 |
| **F12** | `0x45` (69) | 78 | 78 | `0#13` | Function 12 |
| **Del** | `0x4C` (76) | 92 | 92 | `2#14` | Delete |
| **Ins** | `0x49` (73) | 91 | 91 | `1#14` | Insert |
| **\`~** | `0x35` (53) | 1 | 1 | `1#0` | Grave Accent / Tilde |
| **1!** | `0x1E` (30) | 7 | 7 | `1#1` | Number 1 / Exclamation |
| **2@** | `0x1F` (31) | 13 | 13 | `1#2` | Number 2 / At |
| **3#** | `0x20` (32) | 19 | 19 | `1#3` | Number 3 / Hash |
| **4$** | `0x21` (33) | 25 | 25 | `1#4` | Number 4 / Dollar |
| **5%** | `0x22` (34) | 31 | 31 | `1#5` | Number 5 / Percent |
| **6^** | `0x23` (35) | 37 | 37 | `1#6` | Number 6 / Caret |
| **7&** | `0x24` (36) | 43 | 43 | `1#7` | Number 7 / Ampersand |
| **8\*** | `0x25` (37) | 49 | 49 | `1#8` | Number 8 / Asterisk |
| **9(** | `0x26` (38) | 55 | 55 | `1#9` | Number 9 / Left Paren |
| **0)** | `0x27` (39) | 61 | 61 | `1#10` | Number 0 / Right Paren |
| **-_** | `0x2D` (45) | 67 | 67 | `1#11` | Hyphen / Underscore |
| **=+** | `0x2E` (46) | 73 | 73 | `1#12` | Equals / Plus |
| **Backspace** | `0x2A` (42) | 79 | 79 | `1#13` | Backspace |
| **Home** | `0x4A` (74) | 91 | 91 | `1#15` | Home |
| **Tab** | `0x2B` (43) | 2 | 2 | `2#0` | Tab |
| **Q** | `0x14` (20) | 8 | 8 | `2#1` | Letter Q |
| **W** | `0x1A` (26) | 14 | 14 | `2#2` | Letter W |
| **E** | `0x08` (8) | 20 | 20 | `2#3` | Letter E |
| **R** | `0x15` (21) | 26 | 26 | `2#4` | Letter R |
| **T** | `0x17` (23) | 32 | 32 | `2#5` | Letter T |
| **Y** | `0x1C` (28) | 38 | 38 | `2#6` | Letter Y |
| **U** | `0x18` (24) | 44 | 44 | `2#7` | Letter U |
| **I** | `0x0C` (12) | 50 | 50 | `2#8` | Letter I |
| **O** | `0x12` (18) | 56 | 56 | `2#9` | Letter O |
| **P** | `0x13` (19) | 62 | 62 | `2#10` | Letter P |
| **[{** | `0x2F` (47) | 68 | 68 | `2#11` | Left Bracket / Brace |
| **]}** | `0x30` (48) | 74 | 74 | `2#12` | Right Bracket / Brace |
| **\\\|** | `0x31` (49) | 80 | 80 | `2#13` | Backslash / Pipe |
| **PgUp** | `0x4B` (75) | 97 | 97 | `1#16` | Page Up |
| **Caps** | `0x39` (57) | 3 | 3 | `3#0` | Caps Lock |
| **A** | `0x04` (4) | 9 | 9 | `3#1` | Letter A |
| **S** | `0x16` (22) | 15 | 15 | `3#2` | Letter S |
| **D** | `0x07` (7) | 21 | 21 | `3#3` | Letter D |
| **F** | `0x09` (9) | 27 | 27 | `3#4` | Letter F |
| **G** | `0x0A` (10) | 33 | 33 | `3#5` | Letter G |
| **H** | `0x0B` (11) | 39 | 39 | `3#6` | Letter H |
| **J** | `0x0D` (13) | 45 | 45 | `3#7` | Letter J |
| **K** | `0x0E` (14) | 51 | 51 | `3#8` | Letter K |
| **L** | `0x0F` (15) | 57 | 57 | `3#0` | Letter L |
| **;:** | `0x33` (51) | 63 | 63 | `3#10` | Semicolon / Colon |
| **'\"** | `0x34` (52) | 69 | 69 | `3#11` | Apostrophe / Quote |
| **Enter** | `0x28` (40) | 81 | 81 | `3#12` | Enter / Return |
| **PgDn** | `0x4E` (78) | 92 | 92 | `2#16` | Page Down |
| **L_Shift** | `0xE1` (225) | 4 | 4 | `4#0` | Left Shift |
| **Z** | `0x1D` (29) | 10 | 10 | `4#2` | Letter Z |
| **X** | `0x1B` (27) | 16 | 16 | `4#3` | Letter X |
| **C** | `0x06` (6) | 22 | 22 | `4#4` | Letter C |
| **V** | `0x19` (25) | 28 | 28 | `4#5` | Letter V |
| **B** | `0x05` (5) | 34 | 34 | `4#6` | Letter B |
| **N** | `0x11` (17) | 40 | 40 | `4#7` | Letter N |
| **M** | `0x10` (16) | 46 | 46 | `4#8` | Letter M |
| **,<** | `0x36` (54) | 52 | 52 | `4#9` | Comma / Less Than |
| **.>** | `0x37` (55) | 58 | 58 | `4#10` | Period / Greater Than |
| **/?** | `0x38` (56) | 64 | 64 | `4#11` | Slash / Question Mark |
| **R_Shift** | `0xE5` (229) | 82 | 82 | `4#13` | Right Shift |
| **Up** | `0x52` (82) | 94 | 94 | `4#14` | Arrow Up |
| **End** | `0x4D` (77) | 92 | 92 | `2#15` | End |
| **L_Ctrl** | `0xE0` (224) | 5 | 5 | `5#0` | Left Control |
| **Win** | `0xE3` (227) | 11 | 11 | `5#2` | Left GUI (Windows) |
| **Alt** | `0xE2` (226) | 17 | 17 | `5#3` | Left Alt |
| **Space** | `0x2C` (44) | 35 | 35 | `5#5` | Spacebar |
| **R_Alt** | `0xE6` (230) | 53 | 53 | `5#8` | Right Alt |
| **Fn** | `0xFF` (255) | 59 | 59 | `5#1` | Function Modifier |
| **R_Ctrl** | `0xE4` (228) | 83 | 83 | `5#12` | Right Control |
| **Left** | `0x50` (80) | 89 | 89 | `5#13` | Arrow Left |
| **Down** | `0x51` (81) | 95 | 95 | `5#14` | Arrow Down |
| **Right** | `0x4F` (79) | 101 | 101 | `5#15` | Arrow Right |

### Sparse LED Matrix Addressing
Notice that `light_index` reaches `101` even though there are only 83 physical switches. This is because the controller maps LEDs directly to matrix intersection points:
- LED Index = `(Row * 20) + Column` or equivalent physical routing.
- When transmitting per-key RGB frames (`CMD_RGB_DATA`), unpopulated LED indices in the sparse array (up to index 101) must still be allocated in the byte stream (zero-filled) so that subsequent LED indices remain aligned.

---

## 6. Rotary Encoder (Knob) Specifications

The top-right corner of the Mono 75 features a clickable rotary encoder knob:

### 6.1 Hardware Architecture
- **Sensor Type**: Incremental 2-phase quadrature rotary encoder with integrated momentary push-button switch.
- **Detents / Resolution**: 24 detents per full 360-degree rotation.
- **Electrical Connection**: Directly wired to MCU timer/interrupt GPIOs with hardware debouncing.

### 6.2 HID Reporting
Knob events do not generate standard keyboard matrix scan codes. Instead, they are reported across **Interface 1 (`input1`)** under **Report ID `0x01` (Consumer Control)**:

| Knob Action | Usage Page | Usage ID | HID Consumer Function |
|:---|:---:|:---:|:---|
| **Clockwise Rotation (CW)** | `0x000C` | `0x00E9` | `Volume Increment` (Volume Up) |
| **Counter-Clockwise (CCW)** | `0x000C` | `0x00EA` | `Volume Decrement` (Volume Down) |
| **Center Push (Click)** | `0x000C` | `0x00E2` | `Mute` (Toggle Audio Mute) |

### 6.3 Dual-Mode Controller State
The onboard MCU firmware implements a hardware-level dual mode:
- **Normal Mode (Default)**: Rotation controls system audio volume; pressing the knob toggles mute.
- **Lighting Mode Toggle**: Long-pressing the knob for **~3 to 5 seconds** toggles the knob's operational mode inside the MCU firmware:
  - CW: Increases Backlight Brightness (`CMD_LIGHT_FRAME` internal equivalent).
  - CCW: Decreases Backlight Brightness.
  - Push: Cycles through Preset Lighting Modes 1–21.
- **Remapping Behavior**: Because the rotary encoder is wired directly to MCU quadrature decoder registers, it cannot be arbitrarily remapped using the matrix `CMD_KEYMAP` (0x12) command. On Linux, knob actions should be remapped using standard userland input daemon tools (such as `hwdb`, `udev`, `sway/i3/niri` keybindings, or `xbindkeys`) matching Consumer Usages `0xE9`, `0xEA`, and `0xE2`.

---

## 7. Akses perangkat di Linux (udev)

Bagian ini dulu berisi panduan CLI Python. CLI itu sudah dihapus dari
repo ini, jadi panduannya juga dihapus. Yang tersisa di sini hanya
penjelasan akses perangkat, karena itu masih relevan untuk GUI vendor
yang mengakses keyboard lewat HID.

Secara default, node hidraw biasanya hanya bisa dibaca dan ditulis
root. Supaya user biasa bisa memakai keyboard tanpa sudo, pasang
aturan di `99-mono75.rules`:

```bash
sudo cp 99-mono75.rules /etc/udev/rules.d/99-mono75.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=hidraw
```

Setelah aturan dipasang, cabut dan colok lagi keyboardnya, atau jalankan
trigger di atas. Aturan itu memberi akses ke node hidraw dan usb untuk
VID 1a2c dan PID 6380.

Catatan kejujuran untuk dokumen ini: opcode, mode lampu, dan layout di
bagian sebelumnya didokumentasikan dari hasil reverse engineering
aplikasi vendor. Dokumen ini bukan klaim bahwa setiap opcode sudah
diuji langsung dengan hardware di semua kondisi, dan tidak ada lagi
alat CLI di repo ini untuk mengirim paket mentah.
