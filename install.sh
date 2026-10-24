#!/usr/bin/env bash
# Installer aplikasi vendor MONO 75 untuk Linux.
# Yang dipasang: paket aplikasi vendor, launcher bin/mono75, satu ikon,
# satu desktop entry, dan aturan udev dari 99-mono75.rules.
# Repo ini tidak lagi berisi CLI, jadi installer tidak memasang mono75-cli
# dan tidak memasang mono75_linux.py. Kalau file lama itu masih ada dari
# instalasi sebelumnya, installer menghapusnya.
#
# Penggunaan:
#   curl -fsSL https://raw.githubusercontent.com/DarulQutni-Q/mono75-linux/main/install.sh | bash
#   atau dari hasil clone:
#   ./install.sh
set -euo pipefail

REPO="DarulQutni-Q/mono75-linux"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mono75"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
WINE_DIR="$DATA_DIR/wineprefix"

if command -v curl >/dev/null 2>&1; then
    DL="curl -fsSL"
elif command -v wget >/dev/null 2>&1; then
    DL="wget -qO-"
else
    echo "Error: curl atau wget dibutuhkan." >&2
    exit 1
fi

if command -v wine >/dev/null 2>&1; then
    echo "Wine ditemukan: $(wine --version 2>&1)"
else
    echo "Peringatan: wine tidak ditemukan. Launcher tetap dipasang, tapi GUI tidak akan jalan sampai Wine dipasang."
    echo "  Arch / CachyOS: sudo pacman -S wine"
    echo "  Ubuntu / Debian: sudo apt install wine"
    echo "  Fedora: sudo dnf install wine"
fi

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

# Aturan udev. Satu sumber: 99-mono75.rules di repo.
echo "Memasang aturan udev ke /etc/udev/rules.d/99-mono75.rules"
UDEV_RULE_FILE="/etc/udev/rules.d/99-mono75.rules"
if [ -f "./99-mono75.rules" ]; then
    cp "./99-mono75.rules" "$TMP/99-mono75.rules"
else
    $DL "https://raw.githubusercontent.com/$REPO/main/99-mono75.rules" -o "$TMP/99-mono75.rules"
fi
if [ -w /etc/udev/rules.d ]; then
    cp "$TMP/99-mono75.rules" "$UDEV_RULE_FILE"
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
elif command -v sudo >/dev/null 2>&1; then
    sudo cp "$TMP/99-mono75.rules" "$UDEV_RULE_FILE"
    sudo udevadm control --reload-rules 2>/dev/null || true
    sudo udevadm trigger 2>/dev/null || true
else
    echo "Peringatan: tidak bisa menulis ke /etc/udev/rules.d/ tanpa sudo."
    echo "Jalankan manual: sudo cp $TMP/99-mono75.rules $UDEV_RULE_FILE"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$ICON_DIR/hicolor" 2>/dev/null || true
fi

echo ""
echo "Selesai."
echo "  Launcher: $INSTALL_DIR/mono75"
echo "  Aplikasi: $DATA_DIR/app"
echo "  Desktop: $DESKTOP_DIR/mono75.desktop"
case ":$PATH:" in
    *":$INSTALL_DIR:"*)
        echo "  Jalankan: mono75"
        ;;
    *)
        echo "  Perhatian: $INSTALL_DIR tidak ada di PATH shell ini."
        echo "  Sampai PATH diperbaiki, jalankan dengan path lengkap: $INSTALL_DIR/mono75"
        ;;
esac
