#!/usr/bin/env bash
# =============================================================================
# ci/setup-emulator-host-gcp.sh
# =============================================================================
# Sets up a GCP VM as an Android emulator host with VNC access.
# This is NOT a CI runner — it's a dedicated emulator machine for manual
# interaction (Google login, app install, QA work) via VNC.
#
# STEP 1 — Create the VM (from your local machine, once):
#
#   gcloud compute instances create android-emulators-poc \
#     --project=appium-sandbox-poc \
#     --zone=us-central1-a \
#     --machine-type=n2-standard-8 \
#     --enable-nested-virtualization \
#     --image-family=ubuntu-2204-lts \
#     --image-project=ubuntu-os-cloud \
#     --boot-disk-size=80GB \
#     --boot-disk-type=pd-ssd
#
# STEP 2 — Copy this script and proxy-setup-kit to the VM:
#
#   gcloud compute scp setup-emulator-host-gcp.sh android-emulators-poc:~ --zone=us-central1-a --project=appium-sandbox-poc
#   gcloud compute scp --recurse proxy-setup-kit android-emulators-poc:~ --zone=us-central1-a --project=appium-sandbox-poc
#
# STEP 3 — SSH in and run this script:
#
#   gcloud compute ssh android-emulators-poc --zone=us-central1-a --project=appium-sandbox-poc
#   bash setup-emulator-host-gcp.sh
#
# STEP 4 — Create emulators using proxy-setup-kit (after reboot):
#
#   cd ~/proxy-setup-kit
#   ./full_setup_android_emulator.sh emulator1
#   ./full_setup_android_emulator.sh emulator2
#
# STEP 5 — Create a firewall rule for VNC (from local machine, once):
#
#   gcloud compute firewall-rules create allow-vnc \
#     --project=appium-sandbox-poc \
#     --allow=tcp:5900 \
#     --source-ranges=$(curl -s ifconfig.me)/32
# =============================================================================

set -euo pipefail

ANDROID_API="36"
ANDROID_SYSTEM_IMAGE="system-images;android-${ANDROID_API};google_apis;x86_64"
ANDROID_HOME="$HOME/android-sdk"
VNC_PASSWORD="${1:-brillio1703}"

info() { echo -e "\n\033[0;36m>>> $*\033[0m"; }
ok()   { echo -e "\033[0;32m  OK  $*\033[0m"; }
fail() { echo -e "\033[0;31m  FAIL  $*\033[0m"; exit 1; }

# =============================================================================
info "Step 1/8 — System packages"
# =============================================================================
sudo apt-get update -qq
sudo apt-get install -y curl wget unzip git openjdk-17-jdk qemu-kvm libvirt-daemon-system xvfb x11vnc openbox
ok "System packages installed"

sudo usermod -aG kvm "$USER"

if [ -e /dev/kvm ]; then
  ok "KVM available (/dev/kvm exists)"
else
  fail "/dev/kvm not found. The VM must be created with --enable-nested-virtualization."
fi

# =============================================================================
info "Step 2/8 — Node.js 20"
# =============================================================================
if command -v node &>/dev/null; then
  ok "Node.js already installed: $(node --version)"
else
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs -q
  ok "Node.js $(node --version)"
fi

# =============================================================================
info "Step 3/8 — Android SDK + Emulator"
# =============================================================================
mkdir -p "$ANDROID_HOME/cmdline-tools"

wget -q "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -O /tmp/cmdline-tools.zip
rm -rf /tmp/cmdline-tools-extract
unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-extract
rm -rf "$ANDROID_HOME/cmdline-tools/latest"
mv /tmp/cmdline-tools-extract/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest"
rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools-extract

export ANDROID_HOME="$ANDROID_HOME"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses > /dev/null 2>&1 || true
sdkmanager --sdk_root="$ANDROID_HOME" "platform-tools" "emulator" "platforms;android-${ANDROID_API}" "${ANDROID_SYSTEM_IMAGE}" > /dev/null

ok "Android SDK installed at $ANDROID_HOME"

# =============================================================================
info "Step 4/8 — Persist environment variables"
# =============================================================================
# Remove any previous Android SDK entries to avoid duplicates
sed -i '/# Android SDK/d; /ANDROID_HOME/d; /ANDROID_SDK_ROOT/d; /APPIUM_HOME/d; /cmdline-tools/d' "$HOME/.bashrc" 2>/dev/null || true

cat >> "$HOME/.bashrc" << 'ENVBLOCK'

# Android SDK
export ANDROID_HOME="$HOME/android-sdk"
export ANDROID_SDK_ROOT="$HOME/android-sdk"
export APPIUM_HOME="$HOME/.appium"
export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
ENVBLOCK

ok "Environment variables written to ~/.bashrc"

# =============================================================================
info "Step 5/8 — Appium + UIAutomator2 driver"
# =============================================================================
sudo npm install -g appium --silent
export APPIUM_HOME="$HOME/.appium"
appium driver install uiautomator2 2>&1 | tail -3
sudo npm install -g appium-doctor --silent 2>/dev/null || true
ok "Appium $(appium --version) with uiautomator2 driver"

# =============================================================================
info "Step 6/8 — Cloudflared"
# =============================================================================
if command -v cloudflared &>/dev/null; then
  ok "cloudflared already installed: $(cloudflared --version)"
else
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflared.list > /dev/null
  sudo apt-get update -qq
  sudo apt-get install -y cloudflared -q
  ok "cloudflared $(cloudflared --version)"
fi

# =============================================================================
info "Step 7/8 — Create start-emulators.sh"
# =============================================================================
cat > "$HOME/start-emulators.sh" << SCRIPT
#!/bin/bash
Xvfb :1 -screen 0 1280x800x24 &
sleep 1
export DISPLAY=:1
DISPLAY=:1 openbox &
x11vnc -display :1 -forever -passwd ${VNC_PASSWORD} -listen 0.0.0.0 -rfbport 5900 &

# Start emulator1 first
emulator -avd emulator1 -no-audio -no-boot-anim -no-snapshot-save -accel on -gpu swiftshader_indirect &

# Wait until it registers as emulator-5554
echo "Waiting for emulator1 (emulator-5554)..."
adb wait-for-device
while [ "\$(adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
  sleep 2
done
echo "emulator1 ready"

# Now start emulator2
emulator -avd emulator2 -no-audio -no-boot-anim -no-snapshot-save -accel on -gpu swiftshader_indirect &
echo "Starting emulator2..."

# Start Appium server
appium --base-path / --port 4723 --allow-insecure='*:session_discovery,*:adb_shell' --allow-cors &
echo "Appium server started on port 4723"

# Start cloudflared tunnel to expose Appium server
TUNNEL_LOG="/tmp/cloudflared.log"
cloudflared tunnel --url http://localhost:4723 > "\$TUNNEL_LOG" 2>&1 &
sleep 10
TUNNEL_URL=\$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "\$TUNNEL_LOG" | head -1)
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Cloudflared tunnel: \${TUNNEL_URL:-check \$TUNNEL_LOG}"
echo "════════════════════════════════════════════════════════════"

echo "Ready — connect via vnc://\$(curl -s ifconfig.me):5900"
SCRIPT
chmod +x "$HOME/start-emulators.sh"
ok "~/start-emulators.sh created"

# =============================================================================
info "Step 8/8 — Register systemd service (auto-start on boot)"
# =============================================================================
sudo tee /etc/systemd/system/emulators.service > /dev/null << SVCEOF
[Unit]
Description=Start Android emulators with VNC
After=network.target

[Service]
Type=forking
User=$USER
Environment=HOME=$HOME
Environment=ANDROID_HOME=$HOME/android-sdk
Environment=ANDROID_SDK_ROOT=$HOME/android-sdk
Environment=APPIUM_HOME=$HOME/.appium
Environment=PATH=$HOME/android-sdk/emulator:$HOME/android-sdk/platform-tools:$HOME/android-sdk/cmdline-tools/latest/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$HOME/start-emulators.sh
ExecStop=/bin/bash -c 'pkill cloudflared; pkill -f appium; pkill -f emulator; pkill x11vnc; pkill openbox; pkill Xvfb'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF

sudo systemctl daemon-reload
sudo systemctl enable emulators.service
ok "emulators.service enabled (will auto-start on boot)"

# =============================================================================
echo ""
echo -e "\033[0;32m========================================\033[0m"
echo -e "\033[0;32m  Setup complete!\033[0m"
echo -e "\033[0;32m========================================\033[0m"
echo ""
echo "  Installed: Java 17, Node.js, Android SDK (API ${ANDROID_API}), Appium, KVM, VNC tools"
echo "  Service:   emulators.service (auto-starts on boot)"
echo ""
echo "  Next steps:"
echo "    1. Log out and back in (so kvm group takes effect), or run: newgrp kvm"
echo "    2. Create emulators using proxy-setup-kit:"
echo "       cd ~/proxy-setup-kit"
echo "       ./full_setup_android_emulator.sh emulator1"
echo "       ./full_setup_android_emulator.sh emulator2"
echo "    3. Reboot the VM: sudo reboot"
echo "    4. Emulators + VNC will start automatically on boot"
echo "    5. Connect via VNC: vnc://<VM_EXTERNAL_IP>:5900"
echo ""
echo "  Manual control:"
echo "    sudo systemctl status emulators    # check status"
echo "    sudo systemctl restart emulators   # restart everything"
echo "    sudo systemctl stop emulators      # stop everything"
echo ""
