# GCP Android Emulator POC — Setup Summary

## VM Details

- **Name:** `android-emulators-poc`
- **Project:** `appium-sandbox-poc`
- **Zone:** `us-central1-a`
- **Machine:** n2-standard-8 (8 vCPUs, 32GB RAM)
- **Disk:** 80GB SSD, Ubuntu 22.04
- **Nested virtualization:** enabled

---

## Software Installed

| Software | Details |
|---|---|
| System packages | curl, wget, unzip, git, openjdk-17-jdk, qemu-kvm, libvirt-daemon-system, xvfb, x11vnc |
| Node.js | v20 (via nodesource) |
| Android SDK | API 36, `google_apis;x86_64` system image, at `~/android-sdk` |
| Appium, appium-doctor | Global npm install + uiautomator2 driver |
| cloudflared | Cloudflare tunnel — exposes local Appium server to the cloud |
| openbox | Lightweight window manager (drag/resize emulator windows on VNC) |
| KVM | User added to `kvm` group |

---

## How It Works: VNC

No full desktop environment. A virtual framebuffer renders the emulator windows, and VNC exposes them remotely.

```
Xvfb (virtual display :1)
  -> openbox (window manager — enables drag/resize)
  -> emulator windows render here
  -> x11vnc serves display :1 on port 5900
  -> macOS Screen Sharing connects to <VM_IP>:5900
```

---

## Initial Setup (one-time)

### 1. Create the VM (from local machine)

```bash
gcloud compute instances create android-emulators-poc --project=appium-sandbox-poc --zone=us-central1-a --machine-type=n2-standard-8 --enable-nested-virtualization --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud --boot-disk-size=80GB --boot-disk-type=pd-ssd
```

### 2. Copy setup files to the VM (from local machine)

```bash
gcloud compute scp vm-setup/setup-emulator-host-gcp.sh android-emulators-poc:~ --zone=us-central1-a --project=appium-sandbox-poc
```

```bash
gcloud compute scp --recurse vm-setup/proxy-setup-kit android-emulators-poc:~ --zone=us-central1-a --project=appium-sandbox-poc
```

### 3. SSH in and run the setup script

```bash
gcloud compute ssh android-emulators-poc --zone=us-central1-a --project=appium-sandbox-poc
```

```bash
bash ~/setup-emulator-host-gcp.sh
```

This installs all infrastructure: system packages, Java 17, Node.js 20, Android SDK, Appium, cloudflared, KVM, VNC tools (Xvfb, x11vnc, openbox), and registers the systemd auto-start service. At the end, it drops you into a new shell with the KVM group and env vars already loaded.

### 4. Create emulators

```bash
cd ~/proxy-setup-kit && ./full_setup_android_emulator.sh emulator1
```

```bash
cd ~/proxy-setup-kit && ./full_setup_android_emulator.sh emulator2
```

Each `full_setup_android_emulator.sh` run:
1. Creates the AVD (with hardware keyboard, dpad, trackball enabled)
2. Installs the system image if not present
3. Starts the emulator with `-writable-system -no-snapshot -selinux permissive`
4. Installs the mitmproxy CA certificate on the emulator
5. Sets the HTTP proxy (configured in `proxy-setup-kit/proxy.env`)
6. Reboots the emulator to apply changes

### 5. Create firewall rule for VNC (from local machine, one-time)

```bash
gcloud compute firewall-rules create allow-vnc --project=appium-sandbox-poc --allow=tcp:5900 --source-ranges=0.0.0.0/0 --description="Allow VNC from anywhere (password-protected)"
```

### 6. Reboot and connect

```bash
sudo reboot
```

After reboot, the systemd service auto-starts Xvfb + openbox + x11vnc + both emulators + Appium server + cloudflared tunnel. Connect via VNC (see "Startup Steps" below).

---

## Proxy Setup Kit (`~/proxy-setup-kit/`)

A self-contained kit for creating emulators and configuring the mitmproxy certificate + HTTP proxy. Copied to the VM during initial setup.

| File | Purpose |
|---|---|
| `proxy.env` | Proxy address config (`PROXY_HOST`, `PROXY_PORT`) — edit if address changes |
| `mitmproxy-ca-cert.pem` | CA certificate for proxy traffic interception |
| `full_setup_android_emulator.sh` | Creates emulator + installs cert + sets proxy (runs the two scripts below in sequence) |
| `create_android_emulator.sh` | Creates AVD only (system image: `android-36;google_apis;x86_64`, device: `medium_phone`) |
| `proxy_setup_android_emulator.sh` | Installs cert + sets proxy on an existing emulator (starts it if not running) |

**Create a new emulator with full proxy setup:**

```bash
cd ~/proxy-setup-kit && ./full_setup_android_emulator.sh <AVD_NAME>
```

**Re-apply proxy/cert on an existing emulator (e.g. after proxy address change):**

```bash
cd ~/proxy-setup-kit && ./proxy_setup_android_emulator.sh <AVD_NAME>
```

**Disable proxy temporarily:**

```bash
adb -s emulator-5554 shell settings put global http_proxy :0
```

> Current proxy address: `54.80.17.8:7777` (edit `proxy.env` to change)

---

## Auto-start (systemd service)

A systemd service (`emulators.service`) is registered during setup. It runs `~/start-emulators.sh` automatically on every VM boot — no need to SSH in and start things manually.

The service starts: Xvfb (display :1), openbox (window manager), x11vnc (VNC on port 5900), emulator1, waits for full boot, then emulator2, Appium server (port 4723), and a cloudflared tunnel exposing Appium to the internet.

> The cloudflared tunnel URL changes on every restart. Check it with:
> `grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/cloudflared.log`

**Service control (via SSH):**

```bash
sudo systemctl status emulators
```

```bash
sudo systemctl restart emulators
```

```bash
sudo systemctl stop emulators
```

**Service file location:** `/etc/systemd/system/emulators.service`

<details>
<summary>emulators.service content</summary>

```ini
[Unit]
Description=Start Android emulators with VNC
After=network.target

[Service]
Type=forking
User=<your-user>
Environment=HOME=/home/<your-user>
Environment=ANDROID_HOME=/home/<your-user>/android-sdk
Environment=ANDROID_SDK_ROOT=/home/<your-user>/android-sdk
Environment=APPIUM_HOME=/home/<your-user>/.appium
Environment=PATH=/home/<your-user>/android-sdk/emulator:/home/<your-user>/android-sdk/platform-tools:/home/<your-user>/android-sdk/cmdline-tools/latest/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/home/<your-user>/start-emulators.sh
ExecStop=/bin/bash -c 'pkill cloudflared; pkill -f appium; pkill -f emulator; pkill x11vnc; pkill openbox; pkill Xvfb'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

</details>

<details>
<summary>start-emulators.sh content</summary>

```bash
#!/bin/bash
Xvfb :1 -screen 0 1280x800x24 &
sleep 1
export DISPLAY=:1
DISPLAY=:1 openbox &
x11vnc -display :1 -forever -passwd YOUR_PASSWORD -listen 0.0.0.0 -rfbport 5900 &

# Start emulator1 first
emulator -avd emulator1 -no-audio -no-boot-anim -no-snapshot-save -accel on -gpu swiftshader_indirect &

# Wait until it registers as emulator-5554
echo "Waiting for emulator1 (emulator-5554)..."
adb wait-for-device
while [ "$(adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
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
cloudflared tunnel --url http://localhost:4723 > "$TUNNEL_LOG" 2>&1 &
sleep 10
TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$TUNNEL_LOG" | head -1)
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Cloudflared tunnel: ${TUNNEL_URL:-check $TUNNEL_LOG}"
echo "════════════════════════════════════════════════════════════"

echo "Ready — connect via vnc://$(curl -s ifconfig.me):5900"
```

</details>

---

## Startup Steps (after each VM stop/start)

With the systemd service enabled, emulators and VNC start automatically on boot. You only need to:

### 1. Start the VM (from local machine)

```bash
gcloud compute instances start android-emulators-poc --zone=us-central1-a --project=appium-sandbox-poc
```

### 2. Connect via VNC

Get the VM's external IP (it changes on every stop/start):

```bash
gcloud compute instances describe android-emulators-poc --zone=us-central1-a --project=appium-sandbox-poc --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
```

Open macOS **Screen Sharing** and connect to `<IP>:5900`.

> The emulators may still be booting when you connect — give it 1-2 minutes after VM start.

---

## Transfer Files to the VM

```bash
gcloud compute scp /path/to/file.apk android-emulators-poc:~ --zone=us-central1-a --project=appium-sandbox-poc
```

> If macOS blocks access to `~/Downloads`, copy the file to `~/Desktop` first, then scp from there.

Install APK on a specific emulator:

```bash
adb -s emulator-5554 install ~/file.apk
```

---

## Emulator Config

AVD configs are at `~/.android/avd/<name>.avd/config.ini`.

The `create_android_emulator.sh` script auto-configures: `hw.keyboard`, `hw.keyboard.lid`, `hw.dpad`, `hw.trackBall`.

To tune resources (edit config while emulator is stopped):

```
hw.ramSize = 4096
hw.cpu.ncore = 4
```

---

## What's NOT on This VM (by design)

- No Docker — mirror/proxy runs elsewhere in the cloud
- No GitHub Actions runner — not a CI machine
- No Python/behave — tests run from cloud
- This is purely an **emulator host**

---

## Issues Encountered & Fixes

| Issue | Fix |
|---|---|
| Full Ubuntu Desktop (Option B) too laggy | Abandoned. No GPU on n2 VM = unusable desktop. Switched to VNC-only |
| xrdp hanging after login | GNOME too heavy, tried xfce4, still bad. VNC-only solved it |
| Multi-line commands breaking on paste via SSH | Use single-line commands |
| Emulator crash (`core dumped`) | Caused by typo from line split during paste (`-no-snapsho` instead of `-no-snapshot-save`) |
| `Xvfb :1` already active | Display :1 still running from before — `rm /tmp/.X1-lock` or reuse existing |
| Firewall rule already exists | Use `update` instead of `create` |
| VNC not working after VM restart | Solved: `emulators.service` systemd unit auto-starts everything on boot |
| Google login fails on emulator | Likely network/proxy related, not system image. Using `google_apis;x86_64` with mitmproxy cert installed via proxy-setup-kit |
| Apps crashing / slow | Increase `hw.ramSize` in AVD config |
| GPU (NVIDIA T4) considered | Doesn't help Android emulator rendering — abandoned |
