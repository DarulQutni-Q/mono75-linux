# VortexSeries MONO 75 Linux Driver & Configurator

<div align="center">

![MONO 75 Banner](assets/vortex-mono75.png)

### Driver & Tool Konfigurasi Keyboard VortexSeries MONO 75 untuk Linux
**Hasil Reverse Engineering dari Aplikasi Resmi Vendor (`MONO 75 setup.exe` / `DeviceDriver.exe` v1.0.3.5)**

[![Platform: Linux](https://img.shields.io/badge/platform-Linux%20(Wayland%20%2F%20X11)-blue.svg)](#)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](#)
[![Reverse Engineered](https://img.shields.io/badge/reverse--engineered-Official%20OEM%20App-orange.svg)](#)
[![Hardware: 1A2C:6380](https://img.shields.io/badge/hardware-1a2c%3A6380-purple.svg)](#)
[![Dual Mode: Official GUI + Native CLI](https://img.shields.io/badge/interface-Official%20GUI%20%2B%20Native%20CLI-teal.svg)](#)

</div>

---

## 📢 Tentang Proyek Ini

Repository ini menyediakan dukungan driver dan utilitas konfigurasi lengkap untuk keyboard mekanikal **VortexSeries MONO 75** di Linux. Seluruh protokol USB HID dan struktur data firmware diekstrak secara mandiri melalui proses **Reverse Engineering langsung dari installer resmi Windows (`MONO 75 setup.exe` / `DeviceDriver.exe` v1.0.3.5 by China Resource Semico Co., Ltd. / KB-K102)**.

Proyek ini menghadirkan **arsitektur Dual-Mode**:
1. **Official Vendor GUI Application (Mode GUI):**
   - Menjalankan antarmuka grafis resmi vendor 1:1 di Linux melalui layer Wine portabel mandiri.
   - 100% tampilan visual asli, editor makro visual, konfigurasi knob volume rotary encoder, dan manajemen profil kustom.
2. **100% Native Python CLI Utility (`mono75` / `mono75_linux.py`):**
   - Driver murni Linux tanpa Wine atau dependensi berat.
   - Berkomunikasi langsung ke `/dev/hidraw*` atau via `python-hidapi`.
   - Sangat cocok untuk pengguna terminal, server headless, skrip otomatisasi, daemon ambient lighting, atau keybind window manager (Niri, Hyprland, Sway, i3).

---

## 🚀 Quick Install (One-Line Installer)

Cukup jalankan satu baris perintah berikut di terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/DarulQutni-Q/mono75-linux/main/install.sh | bash
```

### Yang dilakukan oleh installer otomatis:
1. Memeriksa dependensi sistem (`python3` untuk CLI, `wine` untuk GUI resmi).
2. Memasang paket aplikasi resmi vendor ke `~/.local/share/mono75/app/`.
3. Memasang runner launcher cerdas ke `~/.local/bin/mono75` (otomatis mendeteksi pemanggilan GUI vs CLI).
4. Memasang utilitas CLI mandiri ke `~/.local/bin/mono75-cli`.
5. Memasang icon resolusi tinggi (16x16 hingga 512x512) ke `~/.local/share/icons/hicolor/`.
6. Mendaftarkan desktop entry ke `~/.local/share/applications/mono75.desktop` (langsung muncul di launcher aplikasi sistem).
7. Memasang aturan `udev` ke `/etc/udev/rules.d/99-mono75.rules` agar perangkat dapat diakses tanpa `sudo`.
8. Me-refresh cache database desktop dan icon sistem.

Setelah instalasi selesai, Anda dapat langsung meluncurkan GUI dari launcher aplikasi (cari **"MONO 75"**) atau via terminal:
```bash
# Meluncurkan GUI resmi
mono75

# Atau menggunakan utilitas CLI native
mono75 info
mono75 list-modes
```

---

## 📊 Perbandingan Fitur

| Fitur | Aplikasi Resmi Windows | Native Python CLI (`mono75 <cmd>`) | Runner Terintegrasi (`mono75`) |
|---|---|---|---|
| **Kebutuhan Wine** | Wajib (di Linux) | **0% Wine (Murni Native Linux)** | Opsional (hanya jika membuka GUI) |
| **Antarmuka Grafis (GUI)** | Resmi Vendor (XYUI/MFC) | N/A (Headless) | **100% Resmi Vendor** |
| **Status & Info Perangkat** | Visual | Terminal JSON/Text | **Didukung Penuh** |
| **21 Mode Efek RGB** | Ya (Preset 1–21) | **Ya (Preset 1–21 + speed/brightness/color)** | **Didukung Penuh** |
| **Per-Key Custom RGB** | Visual Palette Grid | **Hex Bulk, Single Key, atau CSV Table** | **Didukung Penuh** |
| **Key Remapping & Layers** | Visual Layout Map | **Layer 0 (Base) & Layer 1 (Fn)** | **Didukung Penuh** |
| **Knob Rotary Encoder** | Visual Setup | Standard Consumer HID | **Didukung Penuh** |
| **Visual Macro Sequencer** | Ya | Via GUI Resmi | **Didukung Penuh** |
| **Akses Non-Root (udev)** | N/A | **0666 uaccess (Tanpa sudo)** | **0666 uaccess (Tanpa sudo)** |
| **Low-Level Raw Packet Debug**| Tidak Ada | **Ya (`mono75 raw <hex> --recv`)** | **Didukung Penuh** |

---

## 🎮 Kompatibilitas Hardware

<div align="center">

![Keyboard Layout](assets/keyboard_layout.png)

</div>

| Parameter | Spesifikasi | Keterangan |
|---|---|---|
| **Nama Perangkat** | VortexSeries MONO 75 | 75% Mechanical Keyboard (83 Keys + Rotary Knob) |
| **Vendor ID (VID)** | `0x1A2C` | China Resource Semico Co., Ltd. |
| **Product ID (PID)** | `0x6380` | SEMICO USB Gaming Keyboard / KB-K102 |
| **USB Class** | `0x03` (HID) | Human Interface Device (Composite) |
| **Interface 0** | `/dev/hidraw0` | Standard Boot Keyboard (BIOS/UEFI 6KRO) |
| **Interface 1** | `/dev/hidraw1` | Composite Media, NKRO & Vendor Config Channel |
| **Report ID Vendor** | `0x07` | 64-Byte Bidirectional Channel (Usage Page `0xFF01`) |

---

## 💻 Panduan CLI Native Linux (`mono75`)

Utilitas CLI native memungkinkan Anda mengontrol keyboard secara instan dari terminal atau mengintegrasikannya ke skrip shell, polybar, waybar, atau shortcut compositor (Niri, Hyprland, Sway).

### 1. Cek Informasi Perangkat & Firmware
```bash
mono75 info
```
*Contoh output:*
```
Device: /dev/hidraw1 (VID=0x1A2C PID=0x6380)
Firmware: v1.02 | Layout: KB-K102 (75% ANSI) | Status: Connected
```

### 2. Melihat Daftar 21 Mode Animasi RGB
```bash
mono75 list-modes
```
*Daftar mode yang didukung:*
```
   1  Static           8  Rain            15  Color Wheel
   2  Off              9  Random          16  Neon
   3  Breathing       10  Star            17  Aurora
   4  Wave            11  Fire            18  Raindrop
   5  Reactive        12  Snake           19  Explosion
   6  Ripple          13  Brick           20  Heartbeat
   7  Color Cycle     14  Custom Layer    21  Custom Per-Key
```

### 3. Mengatur Mode Pencahayaan & Warna
```bash
# Set mode 4 (Wave), kecepatan 3, kecerahan maksimal (4)
mono75 light --mode 4 --speed 3 --brightness 4

# Set mode 1 (Static) dengan warna custom cyan hex
mono75 light --mode 1 --brightness 4 --color 00ffd5

# Set mode 3 (Breathing) dengan warna amber
mono75 light --mode 3 --speed 2 --color ff9900

# Mematikan lampu RGB
mono75 light --mode 2
```

### 4. Custom Per-Key RGB Lighting
```bash
# Mewarnai seluruh tombol dengan satu warna solid
mono75 per-key --color ff007f

# Mewarnai tombol tertentu berdasarkan file CSV (format: KEY_NAME,RRGGBB)
cat << 'EOF' > wasd_preset.csv
W,ff0000
A,ff0000
S,ff0000
D,ff0000
Esc,00ffff
Space,00ff00
Enter,ffaa00
EOF

mono75 per-key --csv wasd_preset.csv
```

### 5. Remapping Tombol & Layer
```bash
# Menampilkan seluruh tombol dan kode HID Usage
mono75 keymap --list

# Remap CapsLock ke Left Control pada Base Layer (Layer 0)
mono75 keymap --layer 0 --remap Caps 0xE0

# Remap tombol Del ke Home
mono75 keymap --layer 0 --remap Del 0x4A
```

### 6. Low-Level Raw HID Packet (Debugging)
```bash
# Mengirim 64-byte raw packet dan membaca respons dari keyboard:
mono75 raw 07010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000 --recv
```

---

## 🛠️ Instalasi Manual dari Sumber (Git Clone)

Jika Anda ingin menginstall secara manual dari repository:

```bash
# 1. Clone repository
git clone https://github.com/DarulQutni-Q/mono75-linux.git
cd mono75-linux

# 2. Pasang aturan udev (akses non-root)
sudo cp 99-mono75.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger

# 3. Jalankan installer lokal
./install.sh
```

---

## 📖 Spesifikasi Protokol USB HID

Dokumentasi teknis lengkap mengenai hasil reverse engineering protokol komunikasi USB HID (struktur packet 64-byte, opcode `0x01` Info, `0x12` Keymap, `0x76` Frame, `0x99` RGB Chunk, `0xFE` Light Mode, `0xAB` Commit, dan checksum layout) dapat dibaca di:
👉 **[PROTOCOL.md](PROTOCOL.md)**

---

## ⚖️ Penafian (Disclaimer)

Proyek ini adalah hasil reverse engineering independen oleh komunitas open source untuk mendukung sistem operasi Linux dan tidak berafiliasi secara resmi dengan Vortex Gaming / VortexSeries maupun China Resource Semico Co., Ltd. Seluruh merk dagang, logo, dan nama produk adalah hak milik dari pemilik resminya masing-masing.

---

<div align="center">

Dibuat dengan ❤️ untuk komunitas Linux & Keyboard Enthusiast Indonesia.

</div>
