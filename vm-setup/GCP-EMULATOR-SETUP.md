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
| Appium , appium-doctor | Global npm install + uiautomator2 driver |
| openbox | Lightweight window manager (drag/resize emulator windows on VNC) |
| KVM | User added to `kvm` group |

---

## How It Works (VNC — Option A)

No full desktop environment. A virtual framebuffer renders the emulator windows, and VNC exposes them remotely.

```
Xvfb (virtual display :1)
  -> openbox (window manager — enables drag/resize)
  -> emulator windows render here
  -> x11vnc serves display :1 on port 5900
  -> macOS Screen Sharing connects to <VM_IP>:5900
```

---

## Auto-start (systemd service)

A systemd service (`emulators.service`) is registered during setup. It runs `~/start-emulators.sh` automatically on every VM boot — no need to SSH in and start things manually.

The service starts: Xvfb (display :1), openbox (window manager), x11vnc (VNC on port 5900), emulator1, waits for full boot, then emulator2.

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
ExecStop=/bin/bash -c 'pkill -f emulator; pkill x11vnc; pkill openbox; pkill Xvfb'
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

### 2. Update firewall with your current IP (from local machine)

Your home/office IP changes — update the firewall rule so VNC is reachable:

```bash
gcloud compute firewall-rules update allow-vnc --project=appium-sandbox-poc --source-ranges $(curl -s ifconfig.me)/32
```

### 3. Connect via VNC

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

Default resources were low. To increase (edit config while emulator is stopped):

```
hw.ramSize = 4096M
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
| Google login fails on emulator | Likely network/proxy related, not system image. `google_apis;x86_64` is correct for x86 VMs |
| Apps crashing / slow | Increase `hw.ramSize` in AVD config |
| GPU (NVIDIA T4) considered | Doesn't help Android emulator rendering — abandoned |
