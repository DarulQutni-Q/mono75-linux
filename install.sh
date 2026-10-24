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

# --- 5. Install Python CLI Tool ---
echo "==> Installing native Python CLI tool..."
if [ -f "./mono75_linux.py" ]; then
    cp "./mono75_linux.py" "$DATA_DIR/mono75_linux.py"
else
    $DL "https://raw.githubusercontent.com/$REPO/main/mono75_linux.py" -o "$DATA_DIR/mono75_linux.py"
fi
chmod +x "$DATA_DIR/mono75_linux.py"

# Create symlink for mono75-cli
ln -sfn "$DATA_DIR/mono75_linux.py" "$INSTALL_DIR/mono75-cli"

# --- 6. Install Runner Script ---
echo "==> Installing runner binary to $INSTALL_DIR/mono75..."
cat > "$INSTALL_DIR/mono75" << 'EOF'
#!/usr/bin/env bash
# ==============================================================================
# VortexSeries MONO 75 Keyboard Manager & Driver Runner
# Reverse-Engineered from Official OEM Windows Application (DeviceDriver.exe v1.0.3.5)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_CANDIDATES=(
    "$SCRIPT_DIR/mono75_linux.py"
    "$SCRIPT_DIR/../mono75_linux.py"
    "${XDG_DATA_HOME:-$HOME/.local/share}/mono75/mono75_linux.py"
)

CLI_PATH=""
for cand in "${CLI_CANDIDATES[@]}"; do
    if [ -f "$cand" ]; then
        CLI_PATH="$cand"
        break
    fi
done

is_cli=0
if [ $# -gt 0 ]; then
    case "$1" in
        info|light|list-modes|per-key|keymap|raw|--device)
            is_cli=1
            ;;
        --cli|-c)
            is_cli=1
            shift
            ;;
        --gui|-g)
            is_cli=0
            shift
            ;;
        -h|--help)
            echo "======================================================================"
            echo "  VortexSeries MONO 75 Keyboard Configuration Manager"
            echo "  Reverse-Engineered for Linux (VID 0x1A2C / PID 0x6380)"
            echo "======================================================================"
            echo "Usage:"
            echo "  mono75                 Launch the official vendor GUI application (via Wine)"
            echo "  mono75 --gui           Explicitly launch the official GUI"
            echo "  mono75 <cmd> [args]    Run native Python CLI directly (zero Wine needed)"
            echo ""
            echo "Available CLI Commands:"
            echo "  info                   Query firmware version and device status"
            echo "  list-modes             List all 21 lighting preset numbers and names"
            echo "  light [options]        Set global lighting mode, brightness, speed, color"
            echo "  per-key [options]      Set per-key RGB colors (color hex or CSV map)"
            echo "  keymap [options]       List or remap keys across base (0) and Fn (1) layers"
            echo "  raw <hex> [--recv]     Send raw 64-byte HID packet for debugging"
            echo ""
            echo "CLI Examples:"
            echo "  mono75 info"
            echo "  mono75 list-modes"
            echo "  mono75 light --mode 4 --speed 3 --brightness 4"
            echo "  mono75 light --mode 1 --brightness 4 --color 00ffd5"
            echo "  mono75 per-key --color ff007f"
            echo "  mono75 keymap --layer 0 --remap Caps 0xE0"
            echo "======================================================================"
            exit 0
            ;;
        *)
            is_cli=1
            ;;
    esac
fi

if [ "$is_cli" -eq 1 ]; then
    if [ -z "$CLI_PATH" ]; then
        echo "Error: mono75_linux.py CLI utility not found." >&2
        exit 1
    fi
    exec python3 "$CLI_PATH" "$@"
fi

export WINEPREFIX="${WINEPREFIX:-${XDG_DATA_HOME:-$HOME/.local/share}/mono75/wineprefix}"
export WINEDEBUG="-all"
export WINEDLLOVERRIDES="mscoree,mshtml="

APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mono75/app"
WINE_APP="${WINEPREFIX}/drive_c/mono75app"

if ! command -v wine >/dev/null 2>&1; then
    echo "======================================================================"
    echo "  VortexSeries MONO 75 Keyboard Manager"
    echo "======================================================================"
    echo "Notice: 'wine' was not found in your PATH."
    echo "The official vendor GUI requires Wine to run on Linux."
    echo ""
    echo "To install Wine on your distribution:"
    echo "  Arch / CachyOS : sudo pacman -S wine"
    echo "  Ubuntu / Debian: sudo apt install wine"
    echo "  Fedora         : sudo dnf install wine"
    echo ""
    echo "Alternatively, use the native 100% Linux CLI utility (zero Wine needed):"
    echo "  mono75 info"
    echo "  mono75 list-modes"
    echo "  mono75 light --mode 4 --speed 3 --brightness 4"
    echo "  mono75 per-key --color ff007f"
    echo "  mono75 keymap --layer 0 --remap Caps 0xE0"
    echo "======================================================================"
    exit 1
fi

if [ ! -d "$WINE_APP" ]; then
    if [ -d "$APP_DIR" ]; then
        mkdir -p "${WINEPREFIX}/drive_c"
        ln -sfn "$APP_DIR" "$WINE_APP"
    else
        echo "Error: MONO 75 application directory not found at $APP_DIR" >&2
        echo "Please run install.sh or reinstall the package." >&2
        exit 1
    fi
fi

cd "$WINE_APP"
exec wine "C:\\mono75app\\DeviceDriver.exe" "$@"
EOF
chmod +x "$INSTALL_DIR/mono75"

# --- 7. Install Icons ---
echo "==> Installing icons..."
if [ -f "./assets/vortex-mono75.png" ]; then
    cp "./assets/vortex-mono75.png" "$DATA_DIR/icon.png"
    cp "./assets/vortex-mono75.png" "$ICON_DIR/mono75.png"
elif [ -f "$ICON_DIR/mono75.png" ]; then
    cp "$ICON_DIR/mono75.png" "$DATA_DIR/icon.png"
else
    $DL "https://raw.githubusercontent.com/$REPO/main/assets/vortex-mono75.png" -o "$DATA_DIR/icon.png" 2>/dev/null || true
    [ -f "$DATA_DIR/icon.png" ] && cp "$DATA_DIR/icon.png" "$ICON_DIR/mono75.png"
fi

# Populate standard hicolor sizes
if [ -d "./assets/icons" ]; then
    cp -r ./assets/icons/* "$ICON_DIR/hicolor/" 2>/dev/null || true
fi

for s in 16 24 32 48 64 96 128 256 512; do
    HICOLOR_TARGET="$ICON_DIR/hicolor/${s}x${s}/apps"
    mkdir -p "$HICOLOR_TARGET"
    if [ ! -f "$HICOLOR_TARGET/mono75.png" ] && [ -f "$DATA_DIR/icon.png" ]; then
        cp "$DATA_DIR/icon.png" "$HICOLOR_TARGET/mono75.png"
    fi
done

# --- 8. Install Desktop Entry ---
echo "==> Installing desktop entry to $DESKTOP_DIR/mono75.desktop..."
cat > "$DESKTOP_DIR/mono75.desktop" << EOF
[Desktop Entry]
Name=MONO 75
GenericName=Keyboard Configurator
Comment=Official configuration software for VortexSeries MONO 75 mechanical keyboard (Reverse-Engineered for Linux)
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
