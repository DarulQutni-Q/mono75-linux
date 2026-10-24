#!/usr/bin/env python3
"""
mono75_linux.py — Linux control utility for the VortexSeries Mono 75 keyboard.

Protocol reverse-engineered from DeviceDriver.exe (Inno Setup v6.3.0 installer,
binary at wine_prefix/drive_c/mono75app/DeviceDriver.exe).

Hardware:
  VID  0x1A2C  (China Resource Semico / SEMICO USB Gaming Keyboard)
  PID  0x6380
  Interface: USB HID input1  → /dev/hidraw1  (usually)
  Usage Page: 0xFF01 (Vendor-Defined)
  Report ID:  0x07
  Packet:     64 bytes = ReportID(0x07) + 63 bytes data
  Transport:  HID Feature Reports (get/set) and HID Output Reports

Quick start:
  pip install hid          # python-hidapi wrapper
  # Or use raw /dev/hidrawN if hidapi unavailable
  sudo python3 mono75_linux.py info
  sudo python3 mono75_linux.py light --mode 3 --brightness 4 --speed 2 --color ff0000
  sudo python3 mono75_linux.py keymap --layer 0 --list

udev rule (no sudo needed after install):
  sudo cp 99-mono75.rules /etc/udev/rules.d/
  sudo udevadm control --reload && sudo udevadm trigger
"""

import argparse
import sys
import os
import time
import struct
from pathlib import Path

# ── Device constants ──────────────────────────────────────────────────────────

VID = 0x1A2C
PID = 0x6380
REPORT_ID       = 0x07
PACKET_SIZE     = 64   # 1 byte Report ID + 63 bytes data
DATA_SIZE       = 63   # usable payload after Report ID

# ── Command opcodes (byte[1] of the 63-byte payload) ─────────────────────────
# Reversed from DeviceDriver.exe .text section; c7 45 ac <07> <CMD> patterns.

CMD_INFO        = 0x01   # Query firmware version / device info
CMD_KEYMAP      = 0x12   # Keymap / layer data transfer
CMD_LIGHT_FRAME = 0x76   # Write backlight frame (brightness + global layer)
CMD_RGB_DATA    = 0x99   # Per-key RGB colour chunk (multi-packet)
CMD_LIGHT_MODE  = 0xFE   # Set active lighting mode + attributes
CMD_PER_KEY_RGB = 0xFF   # Per-key custom colour data (alternate chunk)
CMD_COMMIT      = 0xAB   # Apply / commit settings to firmware

# ── Lighting modes (from KB-K102.xml light element) ──────────────────────────

LIGHT_MODES = {
    1:  "Static",
    2:  "Off",
    3:  "Breathing",
    4:  "Wave",
    5:  "Reactive",
    6:  "Ripple",
    7:  "Color Cycle",
    8:  "Rain",
    9:  "Random",
    10: "Star",
    11: "Fire",
    12: "Snake",
    13: "Brick",
    14: "Custom Layer",
    15: "Color Wheel",
    16: "Neon",
    17: "Aurora",
    18: "Raindrop",
    19: "Explosion",
    20: "Heartbeat",
    21: "Custom Per-Key",
}

# ── Key layout (from KB-K102.xml — HID usage codes → key name) ───────────────
# key_index is the firmware LED index used in per-key colour packets.

KEY_TABLE = [
    # (key_name, hid_usage_code, key_index, light_index)
    ("Esc",       0x29, 0,   0),
    ("F1",        0x3A, 12,  12),
    ("F2",        0x3B, 18,  18),
    ("F3",        0x3C, 24,  24),
    ("F4",        0x3D, 30,  30),
    ("F5",        0x3E, 36,  36),
    ("F6",        0x3F, 42,  42),
    ("F7",        0x40, 48,  48),
    ("F8",        0x41, 54,  54),
    ("F9",        0x42, 60,  60),
    ("F10",       0x43, 66,  66),
    ("F11",       0x44, 72,  72),
    ("F12",       0x45, 78,  78),
    ("Del",       0x4C, 92,  92),
    ("Ins",       0x49, 91,  91),
    ("`~",        0x35, 1,   1),
    ("1!",        0x1E, 7,   7),
    ("2@",        0x1F, 13,  13),
    ("3#",        0x20, 19,  19),
    ("4$",        0x21, 25,  25),
    ("5%",        0x22, 31,  31),
    ("6^",        0x23, 37,  37),
    ("7&",        0x24, 43,  43),
    ("8*",        0x25, 49,  49),
    ("9(",        0x26, 55,  55),
    ("0)",        0x27, 61,  61),
    ("-_",        0x2D, 67,  67),
    ("=+",        0x2E, 73,  73),
    ("Backspace", 0x2A, 79,  79),
    ("Home",      0x4A, 91,  91),
    ("Tab",       0x2B, 2,   2),
    ("Q",         0x14, 8,   8),
    ("W",         0x1A, 14,  14),
    ("E",         0x08, 20,  20),
    ("R",         0x15, 26,  26),
    ("T",         0x17, 32,  32),
    ("Y",         0x1C, 38,  38),
    ("U",         0x18, 44,  44),
    ("I",         0x0C, 50,  50),
    ("O",         0x12, 56,  56),
    ("P",         0x13, 62,  62),
    ("[{",        0x2F, 68,  68),
    ("]}",        0x30, 74,  74),
    ("\\|",       0x31, 80,  80),
    ("PgUp",      0x4B, 97,  97),
    ("Caps",      0x39, 3,   3),
    ("A",         0x04, 9,   9),
    ("S",         0x16, 15,  15),
    ("D",         0x07, 21,  21),
    ("F",         0x09, 27,  27),
    ("G",         0x0A, 33,  33),
    ("H",         0x0B, 39,  39),
    ("J",         0x0D, 45,  45),
    ("K",         0x0E, 51,  51),
    ("L",         0x0F, 57,  57),
    (";:",        0x33, 63,  63),
    ("'\"",       0x34, 69,  69),
    ("Enter",     0x28, 81,  81),
    ("PgDn",      0x4E, 92,  92),
    ("L_Shift",   0xE1, 4,   4),
    ("Z",         0x1D, 10,  10),
    ("X",         0x1B, 16,  16),
    ("C",         0x06, 22,  22),
    ("V",         0x19, 28,  28),
    ("B",         0x05, 34,  34),
    ("N",         0x11, 40,  40),
    ("M",         0x10, 46,  46),
    (",<",        0x36, 52,  52),
    (".>",        0x37, 58,  58),
    ("/?",        0x38, 64,  64),
    ("R_Shift",   0xE5, 82,  82),
    ("Up",        0x52, 94,  94),
    ("End",       0x4D, 92,  92),
    ("L_Ctrl",    0xE0, 5,   5),
    ("Win",       0xE3, 11,  11),
    ("Alt",       0xE2, 17,  17),
    ("Space",     0x2C, 35,  35),
    ("R_Alt",     0xE6, 53,  53),
    ("Fn",        0xFF, 59,  59),
    ("R_Ctrl",    0xE4, 83,  83),
    ("Left",      0x50, 89,  89),
    ("Down",      0x51, 95,  95),
    ("Right",     0x4F, 101, 101),
]

NUM_KEYS = len(KEY_TABLE)


# ── Low-level HID transport ───────────────────────────────────────────────────

def _find_hidraw() -> str | None:
    """Return the hidraw path for the vendor interface (input1, Usage Page 0xFF01)."""
    for idx in range(8):
        path = f"/sys/class/hidraw/hidraw{idx}/device/uevent"
        try:
            ue = Path(path).read_text()
        except FileNotFoundError:
            continue
        if f"{VID:04X}:{PID:04X}".lower() not in ue.lower():
            # Try uppercase
            if f"v0000{VID:04X}p0000{PID:04X}".lower() not in ue.lower():
                continue
        # Prefer the interface that has Usage Page 0xFF01 (the vendor config interface)
        # This is always input1 → hidraw1 on this device, but verify via report descriptor.
        desc_path = f"/sys/class/hidraw/hidraw{idx}/device/report_descriptor"
        try:
            desc = Path(desc_path).read_bytes()
            # Look for Usage Page 0xFF01: bytes 06 01 FF
            if b'\x06\x01\xff' in desc:
                return f"/dev/hidraw{idx}"
        except Exception:
            continue
    return None


class Mono75:
    """Low-level Mono 75 HID transport."""

    def __init__(self, device_path: str | None = None):
        if device_path is None:
            device_path = _find_hidraw()
        if device_path is None:
            raise RuntimeError(
                f"Mono 75 (VID={VID:#06x} PID={PID:#06x}) not found.\n"
                "  • Is the keyboard plugged in?\n"
                "  • Install udev rule: sudo cp 99-mono75.rules /etc/udev/rules.d/ && sudo udevadm control --reload && sudo udevadm trigger\n"
                "  • Or run as root."
            )
        self.path = device_path
        try:
            self._fd = open(device_path, "r+b", buffering=0)
        except PermissionError:
            raise PermissionError(
                f"Permission denied on {device_path}.\n"
                "  Install the udev rule or run with sudo."
            )

    def close(self):
        self._fd.close()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    def _make_packet(self, cmd: int, data: bytes = b"") -> bytes:
        """Build a 64-byte HID packet: [ReportID=0x07] [cmd] [data padded to 63 bytes]."""
        payload = bytes([cmd]) + data
        payload = payload[:DATA_SIZE]           # truncate if too long
        payload = payload.ljust(DATA_SIZE, b'\x00')  # zero-pad to 63 bytes
        return bytes([REPORT_ID]) + payload     # 64 bytes total

    def send_feature(self, cmd: int, data: bytes = b"") -> None:
        """Send a HID Feature Report (SET_REPORT) to the keyboard."""
        pkt = self._make_packet(cmd, data)
        assert len(pkt) == PACKET_SIZE
        self._fd.write(pkt)

    def recv_feature(self, cmd: int, data: bytes = b"") -> bytes:
        """Send a Feature Report then read the 64-byte response."""
        self.send_feature(cmd, data)
        time.sleep(0.02)
        try:
            resp = self._fd.read(PACKET_SIZE)
            return resp
        except Exception:
            return b'\x00' * PACKET_SIZE

    def send_output(self, cmd: int, data: bytes = b"") -> None:
        """Send a HID Output Report (interrupt/bulk OUT) to the keyboard."""
        pkt = self._make_packet(cmd, data)
        self._fd.write(pkt)

    # ── High-level commands ────────────────────────────────────────────────

    def get_info(self) -> dict:
        """Query firmware version / device info (CMD 0x01)."""
        resp = self.recv_feature(CMD_INFO)
        # Response layout (best-effort — no official spec):
        # [0] = Report ID echo (0x07)
        # [1] = CMD echo (0x01)
        # [2..5] = firmware version bytes (BCD or ASCII)
        # [6..] = additional device info
        return {
            "report_id": resp[0],
            "cmd_echo": resp[1],
            "firmware_raw": resp[2:8].hex(),
            "firmware_str": resp[2:6].decode("ascii", errors="replace").strip('\x00'),
            "payload_hex": resp.hex(),
        }

    def set_light_mode(
        self,
        mode: int,
        brightness: int = 4,
        speed: int = 2,
        r: int = 255,
        g: int = 0,
        b: int = 0,
    ) -> None:
        """
        Set global lighting mode (CMD 0xFE).

        mode:       1–21 (see LIGHT_MODES dict)
        brightness: 0–4  (0=off, 4=max, from XML brightness_max=4)
        speed:      0–4  (from XML speed_max=4)
        r,g,b:      0–255 primary colour (for static/breathing modes)

        Packet layout (reversed from 0x108a2 / 0x10838 context):
          [0] Report ID  = 0x07
          [1] CMD        = 0xFE
          [2] mode       (firmware mode index 1-21)
          [3] brightness (0-4)
          [4] speed      (0-4)
          [5] R
          [6] G
          [7] B
        """
        if mode not in LIGHT_MODES:
            raise ValueError(f"Mode {mode} not in 1–21. Use --list-modes.")
        data = bytes([mode, brightness & 0x0F, speed & 0x0F, r, g, b])
        self.send_feature(CMD_LIGHT_MODE, data)
        # Commit
        time.sleep(0.05)
        self.send_feature(CMD_COMMIT)

    def set_static_light(self, r: int, g: int, b: int, brightness: int = 4) -> None:
        """Shorthand: static colour on all keys."""
        self.set_light_mode(1, brightness=brightness, r=r, g=g, b=b)

    def set_per_key_colors(self, colors: list[tuple[int, int, int]]) -> None:
        """
        Write per-key RGB colours (CMD 0x99 / 0xFF multi-packet protocol).

        colors: list of (r,g,b) tuples, one per key, indexed by KEY_TABLE order.
                Fewer than NUM_KEYS entries → remaining keys default to black.

        Packet format (reversed from 0x107e0 region):
          [0] Report ID = 0x07
          [1] CMD       = 0x99 (or 0xFF for last chunk)
          [2] chunk_idx (0-based packet number)
          [3] key_count_in_chunk
          [4..63] R0,G0,B0, R1,G1,B1, ... (3 bytes per key, up to 20 keys per packet)

        Each packet carries up to 20 keys × 3 bytes = 60 bytes of colour data.
        The keyboard has 84 LED-indexed keys; pad to NUM_KEYS if fewer supplied.
        """
        # Build flat key→(r,g,b) array by light_index
        max_idx = max(k[3] for k in KEY_TABLE) + 1
        led_colors = [(0, 0, 0)] * max_idx
        for i, (r, g, b) in enumerate(colors[:len(KEY_TABLE)]):
            _, _, _, light_idx = KEY_TABLE[i]
            led_colors[light_idx] = (r & 0xFF, g & 0xFF, b & 0xFF)

        # Flatten to bytes
        flat = bytearray()
        for r, g, b in led_colors:
            flat += bytes([r, g, b])

        # Split into chunks of 20 keys (60 bytes) per packet
        KEYS_PER_PKT = 20
        BYTES_PER_PKT = KEYS_PER_PKT * 3  # 60 bytes

        chunk_idx = 0
        offset = 0
        while offset < len(flat):
            chunk = flat[offset:offset + BYTES_PER_PKT]
            is_last = (offset + BYTES_PER_PKT) >= len(flat)
            cmd = CMD_PER_KEY_RGB if is_last else CMD_RGB_DATA
            key_count = len(chunk) // 3
            data = bytes([chunk_idx, key_count]) + bytes(chunk)
            self.send_feature(cmd, data)
            time.sleep(0.01)
            chunk_idx += 1
            offset += BYTES_PER_PKT

        # Activate custom per-key mode (mode 21 = mode index 100 in XML)
        self.send_feature(CMD_LIGHT_FRAME, bytes([0x00, 0x00, 0x04]))  # brightness=4
        time.sleep(0.05)
        self.send_feature(CMD_COMMIT)

    def set_light_frame(self, brightness: int = 4, layer: int = 0) -> None:
        """
        Write global light frame parameters (CMD 0x76).

        Packet layout (reversed from 0x105f2):
          [0] Report ID  = 0x07
          [1] CMD        = 0x76
          [2] layer      (active layer 0-based)
          [3] reserved   = 0x00
          [4] brightness (0x00-0x04)
        """
        data = bytes([layer & 0x0F, 0x00, brightness & 0x0F])
        self.send_feature(CMD_LIGHT_FRAME, data)

    def send_keymap(
        self,
        layer: int,
        key_code: int,
        mapped_usage_page: int,
        mapped_usage: int,
    ) -> None:
        """
        Remap a single key (CMD 0x12).

        Packet layout (reversed from 0x19990 context):
          [0] Report ID       = 0x07
          [1] CMD             = 0x12
          [2] layer           (0 = base, 1 = Fn layer)
          [3] source_hid_code (keyboard HID usage from KEY_TABLE)
          [4] target_usage    (low byte of target HID usage)
          [5] target_up       (target Usage Page: 0x07=keyboard, 0x0C=consumer, 0x00=disable)
        """
        data = bytes([
            layer & 0x0F,
            key_code & 0xFF,
            mapped_usage & 0xFF,
            mapped_usage_page & 0xFF,
        ])
        self.send_feature(CMD_KEYMAP, data)
        time.sleep(0.02)
        self.send_feature(CMD_COMMIT)

    def send_raw(self, hex_str: str) -> None:
        """Send a raw hex packet (debug). Must be exactly 64 bytes (128 hex chars)."""
        raw = bytes.fromhex(hex_str.replace(" ", ""))
        if len(raw) != PACKET_SIZE:
            raise ValueError(f"Raw packet must be {PACKET_SIZE} bytes, got {len(raw)}.")
        self._fd.write(raw)


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse_color(s: str) -> tuple[int, int, int]:
    s = s.lstrip("#")
    if len(s) == 6:
        return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)
    if len(s) == 3:
        return int(s[0]*2, 16), int(s[1]*2, 16), int(s[2]*2, 16)
    raise ValueError(f"Invalid colour: {s!r}. Use RRGGBB hex (e.g. ff0000).")


def cmd_info(args, kb: Mono75):
    info = kb.get_info()
    print("=== Mono 75 Device Info ===")
    print(f"  HID path       : {kb.path}")
    print(f"  VID / PID      : {VID:#06x} / {PID:#06x}")
    print(f"  Report ID      : {REPORT_ID:#04x}")
    print(f"  Firmware raw   : {info['firmware_raw']}")
    print(f"  Firmware str   : {info['firmware_str']!r}")
    print(f"  Full response  : {info['payload_hex']}")


def cmd_light(args, kb: Mono75):
    mode = args.mode
    brightness = max(0, min(4, args.brightness))
    speed = max(0, min(4, args.speed))
    r, g, b = parse_color(args.color)
    print(f"Setting light mode={mode} ({LIGHT_MODES.get(mode,'?')}), "
          f"brightness={brightness}, speed={speed}, color=#{r:02x}{g:02x}{b:02x}")
    kb.set_light_mode(mode, brightness=brightness, speed=speed, r=r, g=g, b=b)
    print("Done.")


def cmd_list_modes(args, kb: Mono75 | None = None):
    print("Available lighting modes:")
    for num, name in LIGHT_MODES.items():
        print(f"  {num:2d}  {name}")


def cmd_keymap(args, kb: Mono75 | None = None):
    if args.list:
        print(f"{'Key':<12} {'HID':<6} {'key_idx':<10} {'light_idx'}")
        for name, hid, ki, li in KEY_TABLE:
            print(f"  {name:<12} {hid:#06x}  {ki:<10} {li}")
        return
    if kb is None:
        print("Device connection required for remapping.", file=sys.stderr)
        sys.exit(1)
    if args.remap:
        src_name, tgt_hex = args.remap
        src = next((k for k in KEY_TABLE if k[0].lower() == src_name.lower()), None)
        if not src:
            print(f"Key {src_name!r} not found. Use --list.", file=sys.stderr)
            sys.exit(1)
        tgt_usage = int(tgt_hex, 16)
        layer = args.layer
        print(f"Remapping {src[0]} (HID {src[1]:#04x}) on layer {layer} → usage {tgt_usage:#04x}")
        kb.send_keymap(layer, src[1], 0x07, tgt_usage)
        print("Done.")
        return
    print("Use --list or --remap KEY TARGET_HID_USAGE.", file=sys.stderr)


def cmd_per_key(args, kb: Mono75):
    """Set all keys to one colour, or parse a CSV colour map."""
    if args.color:
        r, g, b = parse_color(args.color)
        colors = [(r, g, b)] * NUM_KEYS
        print(f"Setting all keys to #{r:02x}{g:02x}{b:02x} (per-key mode)")
        kb.set_per_key_colors(colors)
        print("Done.")
        return
    if args.csv:
        # CSV format: key_name,RRGGBB per line
        colors_map = {}
        with open(args.csv) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                parts = line.split(',')
                if len(parts) >= 2:
                    key_name, color_hex = parts[0].strip(), parts[1].strip()
                    colors_map[key_name.lower()] = parse_color(color_hex)
        colors = []
        for name, hid, ki, li in KEY_TABLE:
            colors.append(colors_map.get(name.lower(), (0, 0, 0)))
        print(f"Setting per-key colours from {args.csv}")
        kb.set_per_key_colors(colors)
        print("Done.")
        return
    print("Use --color RRGGBB or --csv FILE.", file=sys.stderr)


def cmd_raw(args, kb: Mono75):
    print(f"Sending raw: {args.hex}")
    kb.send_raw(args.hex)
    if args.recv:
        resp = kb._fd.read(PACKET_SIZE)
        print(f"Response: {resp.hex()}")


def main():
    ap = argparse.ArgumentParser(
        description="Linux control utility for VortexSeries Mono 75 keyboard.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--device", metavar="PATH", default=None,
                    help="Override hidraw device path (e.g. /dev/hidraw1)")

    sub = ap.add_subparsers(dest="cmd", metavar="COMMAND")
    sub.required = True

    # info
    p = sub.add_parser("info", help="Query firmware version and device info")

    # light
    p = sub.add_parser("light", help="Set global lighting mode")
    p.add_argument("--mode",       type=int, default=1, metavar="N",
                   help="Lighting mode 1–21 (default: 1=Static)")
    p.add_argument("--brightness", type=int, default=4, metavar="N",
                   help="Brightness 0–4 (default: 4=max)")
    p.add_argument("--speed",      type=int, default=2, metavar="N",
                   help="Effect speed 0–4 (default: 2)")
    p.add_argument("--color",      default="ffffff", metavar="RRGGBB",
                   help="Primary colour in hex (default: ffffff)")

    # list-modes
    p = sub.add_parser("list-modes", help="List available lighting mode numbers and names")

    # per-key
    p = sub.add_parser("per-key", help="Set per-key RGB colours (activates mode 21)")
    p.add_argument("--color", metavar="RRGGBB",
                   help="Paint all keys with this colour")
    p.add_argument("--csv",   metavar="FILE",
                   help="CSV file: key_name,RRGGBB per line")

    # keymap
    p = sub.add_parser("keymap", help="Query or remap keys")
    p.add_argument("--layer",  type=int, default=0, metavar="N",
                   help="Layer 0=base 1=Fn (default: 0)")
    p.add_argument("--list",   action="store_true",
                   help="List all keys with their HID usage codes")
    p.add_argument("--remap",  nargs=2, metavar=("KEY", "USAGE_HEX"),
                   help="Remap KEY to target HID usage (hex, e.g. 'A 0x04')")

    # raw
    p = sub.add_parser("raw", help="Send a raw 64-byte hex packet (debug)")
    p.add_argument("hex", metavar="HEX",
                   help="128 hex characters (64 bytes)")
    p.add_argument("--recv", action="store_true",
                   help="Read and print 64-byte response after send")

    args = ap.parse_args()

    if args.cmd == "list-modes":
        cmd_list_modes(args, None)
        return
    if args.cmd == "keymap" and args.list:
        cmd_keymap(args, None)
        return

    try:
        with Mono75(args.device) as kb:
            dispatch = {
                "info":       cmd_info,
                "light":      cmd_light,
                "list-modes": cmd_list_modes,
                "per-key":    cmd_per_key,
                "keymap":     cmd_keymap,
                "raw":        cmd_raw,
            }
            dispatch[args.cmd](args, kb)
    except (RuntimeError, PermissionError) as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nInterrupted.")
        sys.exit(0)


if __name__ == "__main__":
    main()
