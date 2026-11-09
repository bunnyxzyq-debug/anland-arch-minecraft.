# 1. Remove any copies placed in /sdcard/Download earlier
rm -f /sdcard/Download/install.sh /sdcard/Download/README.md 2>/dev/null || true

# 2. Write the clean master script without termux-setup-storage or /sdcard references
cat << 'MASTER_EOF' > ~/anland-arch-setup.sh
#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "==> [1/7] Verifying ARM64 architecture & installing Termux packages..."
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
  echo "Error: This script requires an ARM64 (aarch64) device/environment."
  exit 1
fi

apt-mark unhold mesa mesa-vulkan-icd-freedreno kwin-anland xwayland 2>/dev/null || true
yes | pkg update -y
yes | pkg upgrade -y
pkg install x11-repo tur-repo -y
pkg install proot-distro pulseaudio pipewire termux-api curl wget git jq unzip tar file \
  plasma-desktop konsole dolphin xwayland layer-shell-qt xorg-xrdb mesa-vulkan-icd-freedreno -y

rm -rf "$PREFIX/var/lib/proot-distro/containers/ubuntu-anland" 2>/dev/null || true

echo "==> [2/7] Installing Anland daemon, patched kwin-anland, LayerShellQt & XWayland..."
mkdir -p ~/anland-tmp && cd ~/anland-tmp

ANLAND_DEB_URL=$(curl -sL https://api.github.com/repos/lfdevs/anland-termux/releases/latest | jq -r '.assets[] | select(.name | test("^anland_.*_aarch64\\.deb$")) | .browser_download_url' | head -n 1)
[ -z "$ANLAND_DEB_URL" ] || [ "$ANLAND_DEB_URL" = "null" ] && ANLAND_DEB_URL="https://github.com/lfdevs/anland-termux/releases/download/5.13.4/anland_5.13.3_aarch64.deb"
wget -q --show-progress --continue --tries=10 -O anland.deb "$ANLAND_DEB_URL"

KWIN_DEB_URL=$(curl -sL https://api.github.com/repos/lfdevs/anland-termux/releases/latest | jq -r '.assets[] | select(.name | test("^kwin-anland_.*_aarch64\\.deb$")) | .browser_download_url' | head -n 1)
[ -z "$KWIN_DEB_URL" ] || [ "$KWIN_DEB_URL" = "null" ] && KWIN_DEB_URL="https://github.com/lfdevs/anland-termux/releases/download/5.13.4/kwin-anland_6.7.5_aarch64.deb"
wget -q --show-progress --continue --tries=10 -O kwin-anland.deb "$KWIN_DEB_URL"

XWAYLAND_DEB_URL=$(curl -sL https://api.github.com/repos/lfdevs/anland-termux/releases/latest | jq -r '.assets[] | select(.name | test("^xwayland_.*_aarch64\\.deb$")) | .browser_download_url' | head -n 1)
if [ -n "$XWAYLAND_DEB_URL" ] && [ "$XWAYLAND_DEB_URL" != "null" ]; then
  wget -q --show-progress --continue --tries=10 -O xwayland.deb "$XWAYLAND_DEB_URL"
fi

LAYER_DEB_URL=$(curl -sL https://api.github.com/repos/lfdevs/termux-packages/releases | jq -r '.[].assets[] | select(.name | test("^layer-shell-qt.*aarch64\\.deb$")) | .browser_download_url' | head -n 1)
if [ -n "$LAYER_DEB_URL" ] && [ "$LAYER_DEB_URL" != "null" ]; then
  wget -q --show-progress --continue --tries=10 -O layer-shell-qt.deb "$LAYER_DEB_URL"
fi

dpkg -i --force-overwrite ./*.deb || pkg install -f -y
cd ~ && rm -rf ~/anland-tmp

curl -sSL "https://github.com/lfdevs/anland-termux/raw/refs/heads/main/scripts/startplasma-anland.sh" -o "$PREFIX/bin/startplasma-anland.sh"
chmod +x "$PREFIX/bin/startplasma-anland.sh"

echo "==> [3/7] Installing Termux Native KGSL-patched Mesa with wget auto-resume & verification..."
mkdir -p ~/anland-mesa-fix && cd ~/anland-mesa-fix
rm -f ./*.deb

TERMUX_MESA_URLS=$(curl -sL https://api.github.com/repos/lfdevs/termux-packages/releases/latest | jq -r '.assets[] | select(.name | test("^(mesa_|mesa-vulkan-icd-freedreno_).*aarch64\\.deb$")) | .browser_download_url')
for url in $TERMUX_MESA_URLS; do
  fname=$(basename "$url")
  wget -q --show-progress --continue --tries=10 --timeout=20 -O "$fname" "$url"
done

if ! file ./mesa_*.deb | grep -q "Debian binary package"; then
  echo "Primary download incomplete, pulling from backup Termux KGSL mirror..."
  rm -f ./*.deb
  BACKUP_URLS=$(curl -sL https://api.github.com/repos/sabamdarif/termux-desktop/releases | jq -r '[.[] | select(.tag_name | test("freedreno-kgsl"))][0].assets[] | select(.name | test("^(mesa_|mesa-vulkan-icd-freedreno_).*aarch64\\.deb$")) | .browser_download_url')
  for url in $BACKUP_URLS; do
    wget -q --show-progress --continue --tries=10 -O "$(basename "$url")" "$url"
  done
fi

dpkg -i --force-overwrite ./mesa_*.deb ./mesa-vulkan-icd-freedreno_*.deb
apt-mark hold mesa mesa-vulkan-icd-freedreno kwin-anland xwayland 2>/dev/null || true
cd ~ && rm -rf ~/anland-mesa-fix

echo "==> [4/7] Installing Danhusaker Arch ARM64 container via proot-distro..."
if [ ! -d "$PREFIX/var/lib/proot-distro/containers/archlinux" ]; then
  proot-distro install danhunsaker/archlinuxarm:latest --name archlinux
fi

echo "==> [5/7] Configuring Arch Linux ARM64, clean mirrors, DisableSandbox, KGSL Mesa & Java 21..."
proot-distro login archlinux --shared-tmp --bind /dev/kgsl-3d0:/dev/kgsl-3d0 -- bash -c '
set -e
uname -m | grep -q "aarch64" || { echo "Container architecture mismatch!"; exit 1; }

sed -i "/tardis.sn.opentelecom.au/d; /mirror.moson.org/d" /etc/pacman.d/mirrorlist
sed -i "1i Server = http://fl.us.mirror.archlinuxarm.org/\$arch/\$repo" /etc/pacman.d/mirrorlist
sed -i "1i Server = http://eu.mirror.archlinuxarm.org/\$arch/\$repo" /etc/pacman.d/mirrorlist

sed -i "s/#DisableSandbox/DisableSandbox/g" /etc/pacman.conf
if ! grep -q "^DisableSandbox" /etc/pacman.conf; then
  echo "DisableSandbox" >> /etc/pacman.conf
fi

rm -f /var/lib/pacman/db.lck /var/cache/pacman/pkg/*.lock
pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu --noconfirm

pacman -S --needed base-devel sudo dbus xorg-xwayland xorg-xrandr xorg-xhost \
  mesa vulkan-freedreno jdk21-openjdk openal glfw prismlauncher curl wget jq tar git --noconfirm

archlinux-java set java-21-openjdk

mkdir -p /tmp/mesa-kgsl && cd /tmp/mesa-kgsl
MESA_URL=$(curl -sL https://api.github.com/repos/lfdevs/mesa-for-android-container/releases/latest | jq -r ".assets[] | select(.name | test(\"archlinux_arm64\\\\.tar$\")) | .browser_download_url" | head -n 1)
if [ -n "$MESA_URL" ] && [ "$MESA_URL" != "null" ]; then
  wget -q --show-progress --continue --tries=10 -O mesa-arch.tar "$MESA_URL"
  tar -xvf mesa-arch.tar
  pacman -U *.pkg.tar.* --noconfirm || true
fi
cd / && rm -rf /tmp/mesa-kgsl

if ! id -u shaurya >/dev/null 2>&1; then
  useradd -m -G wheel -s /bin/bash shaurya
fi
echo "shaurya ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/shaurya
chmod 440 /etc/sudoers.d/shaurya
'

echo "==> [6/7] Installing yay-bin & pre-configuring Prism Launcher (Offline Unlocked) & HMCL..."
proot-distro login archlinux --user shaurya --shared-tmp --bind /dev/kgsl-3d0:/dev/kgsl-3d0 -- bash -c '
set -e
if ! command -v yay >/dev/null 2>&1; then
  rm -rf ~/yay-bin
  git clone https://aur.archlinux.org/yay-bin.git ~/yay-bin
  cd ~/yay-bin
  makepkg -si --noconfirm
  cd ~ && rm -rf ~/yay-bin
fi

mkdir -p ~/.local/share/PrismLauncher
cat << "EOF" > ~/.local/share/PrismLauncher/accounts.json
{
    "accounts": [
        {
            "entitlement": {
                "canPlayMinecraft": true,
                "ownsMinecraft": true
            },
            "msa-client-id": "",
            "type": "MSA"
        },
        {
            "active": true,
            "profile": {
                "capes": [],
                "id": "0c79d88a112537a0a302f01afa6bc94a",
                "name": "Shaurya",
                "skin": {
                    "id": "",
                    "url": "",
                    "variant": ""
                }
            },
            "type": "Offline",
            "ygg": {
                "extra": {
                    "clientToken": "9829e31709f149948e69ea8f89291dd9",
                    "userName": "Shaurya"
                },
                "iat": 1707497919,
                "token": "0"
            }
        }
    ],
    "formatVersion": 3
}
EOF

cat << "EOF" > ~/.local/share/PrismLauncher/prismlauncher.cfg
[General]
ApplicationTheme=dark
CustomGLFWPath=/usr/lib/libglfw.so
CustomOpenALPath=/usr/lib/libopenal.so
IgnoreJavaCompatibility=true
JavaPath=/usr/lib/jvm/java-21-openjdk/bin/java
JvmArgs=-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=130 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=28 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20
MaxMemAlloc=3072
MinMemAlloc=1024
UseNativeGLFW=true
UseNativeOpenAL=true
EOF

sudo sed -i "s|^Exec=.*|Exec=env MESA_LOADER_DRIVER_OVERRIDE=kgsl GALLIUM_DRIVER=freedreno TU_DEBUG=noconform MESA_VK_WSI_PRESENT_MODE=mailbox mesa_glthread=true vblank_mode=0 prismlauncher|g" /usr/share/applications/org.prismlauncher.PrismLauncher.desktop

mkdir -p ~/hmcl
wget -q --show-progress --continue --tries=10 -O ~/hmcl/hmcl.jar https://github.com/HMCL-dev/HMCL/releases/download/v3.16.4/HMCL-3.16.4.jar

cat << "EOF" > ~/hmcl/run-hmcl.sh
#!/bin/bash
sudo chmod 644 /tmp/xauth_* /tmp/run/xauth_* ~/.Xauthority 2>/dev/null || true
XAUTH_FILE=$(ls -t /tmp/run/xauth_* /tmp/xauth_* ~/.Xauthority 2>/dev/null | head -n 1)
[ -n "$XAUTH_FILE" ] && export XAUTHORITY="$XAUTH_FILE"

for d in :0 :1; do
  if [ -e "/tmp/.X11-unix/X${d#:}" ]; then
    export DISPLAY="$d"
    break
  fi
done
export DISPLAY=${DISPLAY:-:0}
xhost +local: >/dev/null 2>&1 || true

export MESA_LOADER_DRIVER_OVERRIDE=kgsl
export GALLIUM_DRIVER=freedreno
export TU_DEBUG=noconform
export MESA_VK_WSI_PRESENT_MODE=mailbox
export mesa_glthread=true
export vblank_mode=0

exec /usr/lib/jvm/java-21-openjdk/bin/java -jar /home/shaurya/hmcl/hmcl.jar
EOF
chmod +x ~/hmcl/hmcl.jar ~/hmcl/run-hmcl.sh

sudo tee /usr/share/applications/hmcl.desktop > /dev/null << "EOF"
[Desktop Entry]
Name=HMCL
Comment=Hello Minecraft! Launcher
Exec=/home/shaurya/hmcl/run-hmcl.sh
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=Game;
EOF
'

echo "==> [7/7] Creating arch shortcut, auto-login, sync-arch-apps & start-anland..."
cat << 'ARCH_EOF' > "$PREFIX/bin/arch"
#!/data/data/com.termux/files/usr/bin/bash
export DISPLAY=${DISPLAY:-:0}
xhost +local: >/dev/null 2>&1 || true

exec proot-distro login archlinux --user shaurya --shared-tmp --bind /dev/kgsl-3d0:/dev/kgsl-3d0 -- env \
  DISPLAY=:0 \
  WAYLAND_DISPLAY=wayland-0 \
  XDG_RUNTIME_DIR=/tmp/run \
  PULSE_SERVER=tcp:127.0.0.1:4713 \
  MESA_LOADER_DRIVER_OVERRIDE=kgsl \
  GALLIUM_DRIVER=freedreno \
  TU_DEBUG=noconform \
  MESA_VK_WSI_PRESENT_MODE=mailbox \
  mesa_glthread=true \
  vblank_mode=0 \
  bash "$@"
ARCH_EOF
chmod +x "$PREFIX/bin/arch"

if ! grep -q "proot-distro login archlinux --user shaurya" ~/.bashrc 2>/dev/null; then
cat << 'BASHRC_EOF' >> ~/.bashrc

# Automatically log into Arch Linux as shaurya when opening Konsole inside KDE
if [[ $- == *i* ]] && [ -z "$TMUX" ] && [ "$TERM" != "dumb" ] && [ -n "$KONSOLE_VERSION" ]; then
  if [ ! -f /etc/arch-release ]; then
    exec "$PREFIX/bin/arch"
  fi
fi
BASHRC_EOF
fi

cat << 'SYNC_EOF' > "$PREFIX/bin/sync-arch-apps"
#!/data/data/com.termux/files/usr/bin/bash
TP="/data/data/com.termux/files/usr"
TH="/data/data/com.termux/files/home"
AR="$TP/var/lib/proot-distro/containers/archlinux/rootfs"
TA="$TP/share/applications"
MA="$TH/.local/share/applications"

mkdir -p "$TA" "$MA" 2>/dev/null || true
rm -f "$TA"/arch-*.desktop "$MA"/arch-*.desktop 2>/dev/null || true

COUNT=0
while IFS= read -r f; do
  [ -e "$f" ] || continue
  b=$(basename "$f")
  case "$b" in *konsole*|*dolphin*|*plasma*|avahi*|bssh*|bvnc*|qv4l2*|qvidcap*|lstopo*|org.freedesktop*|xgps*|cmake*) continue ;; esac
  grep -qi "^NoDisplay=true" "$f" && continue
  ex=$(grep -m1 "^Exec=" "$f" | sed 's/^Exec=//; s/ %[fFuUdDnNickvm]//g')
  [ -z "$ex" ] && continue
  case "$ex" in *code*|*vesktop*|*discord*|*chromium*|*brave*) ex="$ex --no-sandbox" ;; esac
  for dest in "$TA/arch-$b" "$MA/arch-$b"; do
    cp "$f" "$dest" 2>/dev/null || continue
    sed -i '/^TryExec=/d; /^OnlyShowIn=/d; /^NotShowIn=/d; /^DBusActivatable=/d' "$dest" 2>/dev/null || true
    sed -i "s|^Exec=.*|Exec=$TP/bin/proot-distro login archlinux --user shaurya --shared-tmp --bind /dev/kgsl-3d0:/dev/kgsl-3d0 -- env DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/tmp/run PULSE_SERVER=tcp:127.0.0.1:4713 MESA_LOADER_DRIVER_OVERRIDE=kgsl GALLIUM_DRIVER=freedreno TU_DEBUG=noconform MESA_VK_WSI_PRESENT_MODE=mailbox mesa_glthread=true vblank_mode=0 $ex|g" "$dest" 2>/dev/null || true
    sed -i 's|^Name=\(.*\)|Name=\1 (Arch)|g' "$dest" 2>/dev/null || true
  done
  COUNT=$((COUNT + 1))
done < <(find "$AR/usr/share/applications" -name "*.desktop" 2>/dev/null)

kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
echo "Synced: $COUNT Arch apps into Termux Native KDE!"
SYNC_EOF
chmod +x "$PREFIX/bin/sync-arch-apps"
cp "$PREFIX/bin/sync-arch-apps" "$PREFIX/var/lib/proot-distro/containers/archlinux/rootfs/usr/local/bin/sync-arch-apps" 2>/dev/null || true

cat << 'START_EOF' > "$PREFIX/bin/start-anland"
#!/data/data/com.termux/files/usr/bin/bash
killall -9 anland pulseaudio plasmashell kwin_wayland 2>/dev/null || true
pkill -f anland-compatible 2>/dev/null || true

mkdir -p "$TMPDIR/run" "$TMPDIR/.X11-unix" "$TMPDIR/anland"
chmod -R 700 "$TMPDIR/run"
chmod 1777 "$TMPDIR/.X11-unix"

pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1 2>/dev/null || true

anland >/dev/null 2>&1 &
if [ "$TERMUX_APP__APK_RELEASE" = "F_DROID" ] && command -v anland-compatible >/dev/null 2>&1; then
  anland-compatible < /dev/null >/dev/null 2>&1 &
fi
sleep 1
am start --user 0 -n com.anland.termux/com.anland.termux.MainActivity >/dev/null 2>&1 || true

export MESA_LOADER_DRIVER_OVERRIDE=kgsl
export GALLIUM_DRIVER=freedreno
export TU_DEBUG=noconform

exec "$PREFIX/bin/startplasma-anland.sh"
START_EOF
chmod +x "$PREFIX/bin/start-anland"

sync-arch-apps
echo "==> ALL DONE! Type 'start-anland' to launch your desktop!"
MASTER_EOF
chmod +x ~/anland-arch-setup.sh

# Update only the internal Termux Git repo (no /sdcard used)
mkdir -p ~/anland-arch-minecraft-repo
cp ~/anland-arch-setup.sh ~/anland-arch-minecraft-repo/install.sh
chmod +x ~/anland-arch-minecraft-repo/install.sh
cd ~/anland-arch-minecraft-repo
git add install.sh
git commit -m "Keep all files strictly inside Termux home directory" || true
echo "==> Clean! Only stored in ~/anland-arch-setup.sh and ~/anland-arch-minecraft-repo/install.sh"
