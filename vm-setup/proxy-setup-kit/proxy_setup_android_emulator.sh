#!/usr/bin/env bash
set -euo pipefail

EMULATOR_CERT_PATH="/sdcard/mitmproxy-ca-cert.pem"
AVD_NAME="${1:-MediumPhoneGoogleAPIs}"  # Allow AVD name as first argument, default to MediumPhoneGoogleAPIs
CERT_FILE="${2:-./mitmproxy-ca-cert.pem}"  # Allow certificate file path as second argument, default to ./mitmproxy-ca-cert.pem
MAX_WAIT_TIME=180  # Maximum wait time in seconds for emulator to boot (increased for cold start)

# Load proxy configuration from proxy.env (distributed in the setup kit)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/proxy.env" ]]; then
  # shellcheck source=proxy.env
  source "${SCRIPT_DIR}/proxy.env"
fi
PROXY_HOST="${PROXY_HOST:-54.80.17.8}"
PROXY_PORT="${PROXY_PORT:-7777}"
PROXY_URL="${PROXY_HOST}:${PROXY_PORT}"
# Show usage if help requested
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  echo "Usage: $0 [AVD_NAME]"
  echo ""
  echo "Sets up mitmproxy certificate and HTTP proxy for Android emulator."
  echo ""
  echo "Arguments:"
  echo "  AVD_NAME    Name of the Android Virtual Device (default: MediumPhoneGoogleAPIs)"
  echo ""
  echo "The script will:"
  echo "  1. Start the emulator if not already running (with -writable-system flags)"
  echo "  2. Install certificate as user CA certificate automatically"
  echo "  3. Set HTTP proxy to ${PROXY_URL}"
  echo ""
  echo "Note: To create an emulator first, run: ./create_emulator.sh [AVD_NAME]"
  echo ""
  echo "Note: User certificates work for most apps. Google services may fail"
  echo "due to certificate pinning, even with system certificates installed."
  echo ""
  exit 0
fi

echo "→ Setting up mitmproxy certificate and proxy for Android emulator..."
echo ""

# Check if emulator is connected
echo "→ Checking for connected emulator..."
if ! adb devices | grep -q "device$"; then
  echo "   No emulator detected. Starting emulator..."
  echo "   AVD: ${AVD_NAME}"
  echo ""
  
  # Check if emulator command exists
  if ! command -v emulator &> /dev/null; then
    echo "❌ emulator command not found. Make sure Android SDK is installed and emulator is in PATH"
    echo "   Expected location: \$ANDROID_SDK_ROOT/emulator/emulator"
    exit 1
  fi
  
  # Start emulator in background
  echo "→ Starting emulator with required flags..."
  emulator -avd "${AVD_NAME}" -writable-system -no-snapshot -selinux permissive > /dev/null 2>&1 &
  EMULATOR_PID=$!
  echo "   Emulator started (PID: ${EMULATOR_PID})"
  echo "   Waiting for emulator to connect (this may take a minute or two)..."
  
  # Wait for device to appear
  WAIT_COUNT=0
  while ! adb devices | grep -q "device$"; do
    if [ $WAIT_COUNT -ge $MAX_WAIT_TIME ]; then
      echo ""
      echo "❌ Timeout waiting for emulator to connect"
      echo "   You may need to start it manually with:"
      echo "   emulator -avd \"${AVD_NAME}\" -writable-system -no-snapshot -selinux permissive"
      exit 1
    fi
    # Check if emulator process is still running
    if ! kill -0 "${EMULATOR_PID}" 2>/dev/null; then
      echo ""
      echo "❌ Emulator process died unexpectedly"
      exit 1
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 2))
    if [ $((WAIT_COUNT % 10)) -eq 0 ]; then
      echo -n " (${WAIT_COUNT}s)"
    else
      echo -n "."
    fi
  done
  echo ""
  echo "   Emulator connected!"
else
  echo "   Emulator already connected"
fi

# Wait for emulator to fully boot
echo "→ Waiting for emulator to fully boot..."
WAIT_COUNT=0
while [ "$(adb shell getprop sys.boot_completed | tr -d '\r\n')" != "1" ]; do
  if [ $WAIT_COUNT -ge $MAX_WAIT_TIME ]; then
    echo "❌ Timeout waiting for emulator to boot"
    exit 1
  fi
  sleep 2
  WAIT_COUNT=$((WAIT_COUNT + 2))
  echo -n "."
done
echo ""
echo "   Emulator is ready!"

# Get root access early (needed for system operations and may help with permissions)
echo "→ Getting root access..."
if ! adb root > /dev/null 2>&1; then
  echo "❌ Failed to get root access. Make sure the emulator was started with -writable-system flag"
  exit 1
fi
sleep 2

# Wait for root to be available
WAIT_COUNT=0
while ! adb shell "id" | grep -q "uid=0"; do
  if [ $WAIT_COUNT -ge 10 ]; then
    echo "❌ Timeout waiting for root access"
    exit 1
  fi
  sleep 1
  WAIT_COUNT=$((WAIT_COUNT + 1))
done
echo "   Root access obtained"

# Remount system partition as writable (needed for system certificate installation)
echo "→ Remounting system partition..."
if ! adb remount > /dev/null 2>&1; then
  echo "❌ Failed to remount system partition. Make sure the emulator was started with -writable-system flag"
  exit 1
fi
sleep 1
echo "   System partition remounted"

# Step 1: Push certificate to emulator /sdcard/ (after root and remount)
echo "→ Pushing PEM certificate to /sdcard/..."
PEM_SDCARD_PATH="${EMULATOR_CERT_PATH}"
if ! adb push "${CERT_FILE}" "${PEM_SDCARD_PATH}"; then
  echo "❌ Failed to push certificate to /sdcard/. Check device permissions."
  exit 1
fi
echo "   Certificate pushed to ${PEM_SDCARD_PATH}"

# Step 2: Install certificate as user CA certificate automatically
echo "→ Installing certificate as user CA certificate..."
echo ""
echo "   Note: User certificates work for most apps, but Google services (Maps, Account)"
echo "   may fail due to certificate pinning."
echo ""

# User certificates are stored in /data/misc/user/0/cacerts-added/
# Get certificate hash (subject_hash_old format)
echo "   Getting certificate hash..."
CERT_HASH=$(openssl x509 -inform PEM -subject_hash_old -in "${CERT_FILE}" | head -n1)
USER_CERT_DIR="/data/misc/user/0/cacerts-added"
USER_CERT_PATH="${USER_CERT_DIR}/${CERT_HASH}.0"

# Create user certificate directory if it doesn't exist
echo "   Creating user certificate directory..."
adb shell "mkdir -p ${USER_CERT_DIR}" 2>/dev/null || true

# Push PEM certificate to user CA store
echo "   Installing certificate to user CA store..."
if ! adb push "${CERT_FILE}" "${USER_CERT_PATH}" 2>/dev/null; then
  echo "❌ Failed to push certificate to user CA store"
  exit 1
fi

# Set proper permissions and ownership
echo "   Setting certificate permissions..."
adb shell "chmod 644 ${USER_CERT_PATH}" 2>/dev/null || true
adb shell "chown system:system ${USER_CERT_PATH}" 2>/dev/null || true
adb shell "chcon u:object_r:system_file:s0 ${USER_CERT_PATH}" 2>/dev/null || true

# Update certificate store by triggering a refresh
echo "   Updating certificate store..."
adb shell "setprop sys.user.0.cacerts-added true" 2>/dev/null || true

# Verify installation
if adb shell "test -f ${USER_CERT_PATH}"; then
  echo "   ✓ User certificate installed successfully at ${USER_CERT_PATH}"
else
  echo "   ⚠️  Warning: Could not verify certificate installation"
fi

echo ""
echo "   Certificate installed as USER CA certificate (works for most apps)."
echo ""

# Step 3: Set HTTP proxy
echo "→ Setting HTTP proxy..."
adb shell settings put global http_proxy "${PROXY_URL}"

# Verify proxy setting
PROXY_VALUE=$(adb shell settings get global http_proxy | tr -d '\r\n')
if [[ "$PROXY_VALUE" == "$PROXY_URL" ]]; then
  echo "   Proxy set successfully: ${PROXY_VALUE}"
else
  echo "⚠️  Warning: Proxy verification failed. Expected: ${PROXY_URL}, Got: ${PROXY_VALUE}"
fi

# Ensure settings are committed to persistent storage before rebooting
echo "→ Ensuring settings are committed to disk..."
adb shell sync
sleep 2  # Give Android time to flush Settings database to disk

# Reboot to apply all changes
echo "→ Rebooting emulator to apply changes..."
adb reboot

# Wait for emulator to come back online
echo "   Waiting for emulator to reboot (this may take a minute)..."
WAIT_COUNT=0
while ! adb devices | grep -q "device$"; do
  if [ $WAIT_COUNT -ge $MAX_WAIT_TIME ]; then
    echo ""
    echo "❌ Timeout waiting for emulator to reboot"
    exit 1
  fi
  sleep 2
  WAIT_COUNT=$((WAIT_COUNT + 2))
  if [ $((WAIT_COUNT % 10)) -eq 0 ]; then
    echo -n " (${WAIT_COUNT}s)"
  else
    echo -n "."
  fi
done
echo ""

# Wait for emulator to fully boot
echo "→ Waiting for emulator to fully boot..."
WAIT_COUNT=0
while [ "$(adb shell getprop sys.boot_completed | tr -d '\r\n')" != "1" ]; do
  if [ $WAIT_COUNT -ge $MAX_WAIT_TIME ]; then
    echo "❌ Timeout waiting for emulator to boot"
    exit 1
  fi
  sleep 2
  WAIT_COUNT=$((WAIT_COUNT + 2))
  echo -n "."
done
echo ""
echo "   Emulator is ready!"

# Verify proxy persisted after reboot
echo "→ Verifying proxy setting persisted after reboot..."
REBOOT_PROXY_VALUE=$(adb shell settings get global http_proxy | tr -d '\r\n')
if [[ "$REBOOT_PROXY_VALUE" == "$PROXY_URL" ]] || [[ "$REBOOT_PROXY_VALUE" == "${PROXY_URL}/" ]]; then
  echo "   ✓ Proxy setting persisted: ${REBOOT_PROXY_VALUE}"
else
  echo "   ⚠️  Warning: Proxy setting did not persist. Got: ${REBOOT_PROXY_VALUE}"
  echo "   Re-applying proxy setting..."
  adb shell settings put global http_proxy "${PROXY_URL}"
fi

echo ""
echo "✔ Setup complete!"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "IMPORTANT NOTES:"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "1. USER CERTIFICATE:"
echo "   - Google services (Maps, Account) may fail due to certificate pinning"
echo ""
echo "2. PROXY SETTING:"
echo "   - HTTP proxy is set to ${PROXY_URL}"
echo "   - if you need stop routing the traffic to the proxy, you can run:"
echo "     adb shell settings put global http_proxy :0"
echo ""
echo "════════════════════════════════════════════════════════════"

