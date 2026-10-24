#!/usr/bin/env bash
# ==============================================================================
# VortexSeries MONO 75 Keyboard Driver & Configurator - Linux Installer
# Reverse-Engineered from Official OEM Windows Application (DeviceDriver.exe v1.0.3.5)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/DarulQutni-Q/mono75-linux/main/install.sh | bash
# ==============================================================================
set -euo pipefail

REPO="DarulQutni-Q/mono75-linux"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mono75"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
WINE_DIR="$DATA_DIR/wineprefix"

echo "======================================================================"
echo "  VortexSeries MONO 75 Keyboard Linux Driver & Utility Installer"
echo "  Reverse-Engineered from Official Vendor App (DeviceDriver.exe v1.0.3.5)"
echo "======================================================================"

# --- 1. Downloader Check ---
if command -v curl >/dev/null 2>&1; then
    DL="curl -fsSL"
elif command -v wget >/dev/null 2>&1; then
    DL="wget -qO-"
else
    echo "Error: curl or wget is required." >&2
    exit 1
fi

# --- 2. Environment & Dependencies Check ---
echo "==> Checking dependencies..."
if ! command -v python3 >/dev/null 2>&1; then
    echo "    [!] Error: python3 is required for native CLI control." >&2
    exit 1
else
    echo "    Found Python runtime: $(python3 --version 2>&1)"
fi

if command -v wine >/dev/null 2>&1; then
    echo "    Found Wine: $(wine --version 2>&1) (Official GUI available)"
else
    echo "    [Notice] 'wine' is not installed."
    echo "    Native Python CLI works 100% out-of-the-box without Wine."
    echo "    To also use the official Windows GUI app on Linux, install Wine:"
    if command -v pacman >/dev/null 2>&1; then
        echo "      Arch / CachyOS : sudo pacman -S wine"
    elif command -v apt-get >/dev/null 2>&1; then
        echo "      Ubuntu / Debian: sudo apt install wine"
    elif command -v dnf >/dev/null 2>&1; then
        echo "      Fedora         : sudo dnf install wine"
    fi
fi

# --- 3. Directory Setup ---
mkdir -p "$INSTALL_DIR" "$DATA_DIR/app" "$DESKTOP_DIR" "$ICON_DIR"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Paket aplikasi vendor. Kalau sudah ada, pakai yang sudah ada.
# Kalau unduhan gagal, installer berhenti dengan error, bukan mengklaim sukses.
if [ -f "$DATA_DIR/app/DeviceDriver.exe" ]; then
    echo "Paket aplikasi sudah ada di $DATA_DIR/app, dipakai ulang."
elif [ -f "./mono75_work/wine_prefix/drive_c/mono75app/DeviceDriver.exe" ]; then
    cp -r "./mono75_work/wine_prefix/drive_c/mono75app/." "$DATA_DIR/app/"
elif [ -f "./mono75-app.tar.zst" ]; then
    tar -xf "./mono75-app.tar.zst" -C "$DATA_DIR/app"
elif [ -f "./mono75-app.tar.gz" ]; then
    tar -xzf "./mono75-app.tar.gz" -C "$DATA_DIR/app"
elif command -v zstd >/dev/null 2>&1 && $DL "https://github.com/$REPO/releases/download/v1.0.0/mono75-app.tar.zst" -o "$TMP/mono75-app.tar.zst" 2>/dev/null; then
    tar -xf "$TMP/mono75-app.tar.zst" -C "$DATA_DIR/app"
elif $DL "https://github.com/$REPO/releases/download/v1.0.0/mono75-app.tar.gz" -o "$TMP/mono75-app.tar.gz" 2>/dev/null; then
    tar -xzf "$TMP/mono75-app.tar.gz" -C "$DATA_DIR/app"
else
    echo "Error: paket aplikasi vendor tidak bisa diunduh dari rilis v1.0.0 dan tidak ditemukan secara lokal." >&2
    echo "Periksa koneksi dan ketersediaan aset rilis, lalu jalankan installer lagi." >&2
    exit 1
fi

# Tarball rilis mengekstrak ke app/mono75app/, bukan langsung ke app/.
# Normalisasi ke app/ supaya launcher dan path Wine cocok. Tanpa ini,
# installer lama gagal diam-diam: file ada, tapi di subfolder yang salah.
if [ -f "$DATA_DIR/app/mono75app/DeviceDriver.exe" ] && [ ! -f "$DATA_DIR/app/DeviceDriver.exe" ]; then
    cp -r "$DATA_DIR/app/mono75app/." "$DATA_DIR/app/"
    rm -rf "$DATA_DIR/app/mono75app"
fi

if [ ! -f "$DATA_DIR/app/DeviceDriver.exe" ]; then
    echo "Error: DeviceDriver.exe tidak ditemukan di $DATA_DIR/app setelah instalasi paket." >&2
    exit 1
fi

mkdir -p "$WINE_DIR/drive_c"
ln -sfn "$DATA_DIR/app" "$WINE_DIR/drive_c/mono75app"
echo "1.0.0" > "$DATA_DIR/version"

# Launcher. Satu sumber: bin/mono75 di repo. Kalau installer dijalankan
# lewat curl, file lokal tidak ada, jadi unduh file yang sama dari repo.
echo "Memasang launcher ke $INSTALL_DIR/mono75"
if [ -f "./bin/mono75" ]; then
    cp "./bin/mono75" "$INSTALL_DIR/mono75"
else
    $DL "https://raw.githubusercontent.com/$REPO/main/bin/mono75" -o "$INSTALL_DIR/mono75"
fi
chmod +x "$INSTALL_DIR/mono75"

# Hapus sisa CLI lama, supaya tidak ada perintah setengah yang menyesatkan.
rm -f "$INSTALL_DIR/mono75-cli" "$DATA_DIR/mono75_linux.py"


# Hapus sisa CLI lama, supaya tidak ada perintah setengah yang menyesatkan.
rm -f "$INSTALL_DIR/mono75-cli" "$DATA_DIR/mono75_linux.py"


# Ikon. Satu file 512x512 saja, bukan satu gambar yang disalin ke banyak ukuran.
echo "Memasang ikon ke $ICON_DIR/hicolor/512x512/apps/mono75.png"
mkdir -p "$ICON_DIR/hicolor/512x512/apps"
if [ -f "./assets/icon.png" ]; then
    cp "./assets/icon.png" "$ICON_DIR/hicolor/512x512/apps/mono75.png"
else
    $DL "https://raw.githubusercontent.com/$REPO/main/assets/icon.png" -o "$ICON_DIR/hicolor/512x512/apps/mono75.png"
fi
rm -f "$ICON_DIR/mono75.png"


# Desktop entry, dibuat installer supaya Exec selalu menunjuk launcher yang baru dipasang.
echo "Memasang desktop entry ke $DESKTOP_DIR/mono75.desktop"
cat > "$DESKTOP_DIR/mono75.desktop" <<EOF
[Desktop Entry]
Name=MONO 75
GenericName=Keyboard Configurator
Comment=Vendor configuration software for VortexSeries MONO 75 mechanical keyboard, run through Wine
Exec=$INSTALL_DIR/mono75
Icon=mono75
Terminal=false
Type=Application
Categories=Settings;HardwareSettings;Utility;
StartupWMClass=devicedriver.exe
Keywords=vortex;vortexseries;mono75;keyboard;rgb;macro;hid;semico;
EOF
chmod 644 "$DESKTOP_DIR/mono75.desktop"


# --- 9. Install Udev Rules ---
echo "==> Configuring udev permissions (non-root access)..."
UDEV_RULE_FILE="/etc/udev/rules.d/99-mono75.rules"
UDEV_CONTENT='# VortexSeries Mono 75 Mechanical Keyboard (China Resource Semico Co., Ltd)
# USB VID: 0x1A2C, PID: 0x6380
# Allow non-root users access to the keyboard hidraw and USB nodes without sudo
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1a2c", ATTRS{idProduct}=="6380", MODE="0666", GROUP="users", TAG+="uaccess"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1a2c", ATTRS{idProduct}=="6380", MODE="0666", GROUP="users", TAG+="uaccess"
ATTRS{idVendor}=="1a2c", ATTRS{idProduct}=="6380", MODE="0666", GROUP="users", TAG+="uaccess"
KERNEL=="hidraw*", ATTRS{idVendor}=="1a2c", ATTRS{idProduct}=="6380", MODE="0666", GROUP="users", TAG+="uaccess"
'

if [ -w /etc/udev/rules.d ]; then
    echo "$UDEV_CONTENT" > "$UDEV_RULE_FILE"
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
    echo "    udev rules installed directly to $UDEV_RULE_FILE"
else
    echo "$UDEV_CONTENT" > "$TMP/99-mono75.rules"
    if command -v sudo >/dev/null 2>&1; then
        echo "    Installing udev rule via sudo..."
        sudo cp "$TMP/99-mono75.rules" "$UDEV_RULE_FILE"
        sudo udevadm control --reload-rules 2>/dev/null || true
        sudo udevadm trigger 2>/dev/null || true
        echo "    udev rules installed successfully."
    else
        echo "    [!] Warning: Could not write to /etc/udev/rules.d/ without sudo."
        echo "    Please run manually: sudo cp $TMP/99-mono75.rules $UDEV_RULE_FILE"
    fi
fi

# --- 10. Refresh Desktop Database & Icon Cache ---
echo "==> Refreshing system caches..."
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$ICON_DIR/hicolor" 2>/dev/null || true
fi

# --- 11. Summary & Finish ---
echo ""
echo "======================================================================"
echo "  Installation Successful!"
echo "======================================================================"
echo "  Application : MONO 75 (VortexSeries MONO 75 Keyboard Manager)"
echo "  Binary Path : $INSTALL_DIR/mono75"
echo "  CLI Tool    : $INSTALL_DIR/mono75-cli"
echo "  Desktop File: $DESKTOP_DIR/mono75.desktop"
echo "  Hardware    : USB VID 0x1A2C / PID 0x6380"
echo ""
echo "  Launch options:"
echo "    - From app launcher : search 'MONO 75'"
echo "    - Terminal (GUI)    : mono75"
echo "    - Terminal (CLI)    : mono75 info"
echo "                          mono75 list-modes"
echo "                          mono75 light --mode 4 --speed 3 --brightness 4"
echo "                          mono75 per-key --color ff007f"
echo "                          mono75 keymap --layer 0 --remap Caps 0xE0"
echo "======================================================================"
