# VortexSeries MONO 75 Linux Driver & Configurator



### Driver & Tool Konfigurasi Keyboard VortexSeries MONO 75 untuk Linux
**Hasil Reverse Engineering dari Aplikasi Resmi Vendor (`MONO 75 setup.exe` / `DeviceDriver.exe` v1.0.3.5)**



---

##  Tentang Proyek Ini

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

##  Quick Install (One-Line Installer)

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

##  Kompatibilitas Hardware


![Keyboard Layout](assets/keyboard_layout.png)


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

##  Instalasi Manual dari Sumber (Git Clone)

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

##  Spesifikasi Protokol USB HID

Dokumentasi teknis lengkap mengenai hasil reverse engineering protokol komunikasi USB HID (struktur packet 64-byte, opcode `0x01` Info, `0x12` Keymap, `0x76` Frame, `0x99` RGB Chunk, `0xFE` Light Mode, `0xAB` Commit, dan checksum layout) dapat dibaca di:
👉 **[PROTOCOL.md](PROTOCOL.md)**

---

##  Penafian (Disclaimer)

Proyek ini adalah hasil reverse engineering independen oleh komunitas open source untuk mendukung sistem operasi Linux dan tidak berafiliasi secara resmi dengan Vortex Gaming / VortexSeries maupun China Resource Semico Co., Ltd. Seluruh merk dagang, logo, dan nama produk adalah hak milik dari pemilik resminya masing-masing.

---



