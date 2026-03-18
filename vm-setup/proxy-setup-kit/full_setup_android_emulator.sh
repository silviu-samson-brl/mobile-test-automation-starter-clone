#!/usr/bin/env bash
set -euo pipefail

# Get script directory to find other scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREATE_EMULATOR_SCRIPT="${SCRIPT_DIR}/create_android_emulator.sh"
SETUP_PROXY_SCRIPT="${SCRIPT_DIR}/proxy_setup_android_emulator.sh"

# Load proxy configuration from proxy.env (distributed in the setup kit)
if [[ -f "${SCRIPT_DIR}/proxy.env" ]]; then
  # shellcheck source=proxy.env
  source "${SCRIPT_DIR}/proxy.env"
fi
PROXY_HOST="${PROXY_HOST:-54.80.17.8}"
PROXY_PORT="${PROXY_PORT:-7777}"
PROXY_URL="${PROXY_HOST}:${PROXY_PORT}"

AVD_NAME="${1:-MediumPhoneGoogleAPIs}"

# Show usage if help requested
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  echo "Usage: $0 [AVD_NAME]"
  echo ""
  echo "Complete emulator setup script that runs both:"
  echo "  1. create_android_emulator.sh - Creates the Android Virtual Device"
  echo "  2. proxy_setup_android_emulator.sh - Sets up mitmproxy certificate and HTTP proxy"
  echo ""
  echo "Arguments:"
  echo "  AVD_NAME    Name of the Android Virtual Device (default: MediumPhoneGoogleAPIs)"
  echo ""
  echo "Prerequisites:"
  echo "  - Android SDK installed and tools in PATH"
  echo "  - Docker container 'mitm-mirror' running (for certificate)"
  echo ""
  echo "This script will:"
  echo "  1. Create the emulator if it doesn't exist"
  echo "  2. Install system image if needed"
  echo "  3. Start the emulator (if not running)"
  echo "  4. Set up mitmproxy certificate"
  echo "  5. Configure HTTP proxy (${PROXY_URL})"
  echo ""
  exit 0
fi

echo "════════════════════════════════════════════════════════════"
echo "  Complete Emulator Setup"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "AVD Name: ${AVD_NAME}"
echo ""

# Check if scripts exist
if [[ ! -f "${CREATE_EMULATOR_SCRIPT}" ]]; then
  echo "❌ Error: create_android_emulator.sh not found at ${CREATE_EMULATOR_SCRIPT}"
  exit 1
fi

if [[ ! -f "${SETUP_PROXY_SCRIPT}" ]]; then
  echo "❌ Error: proxy_setup_android_emulator.sh not found at ${SETUP_PROXY_SCRIPT}"
  exit 1
fi

# Make sure scripts are executable
chmod +x "${CREATE_EMULATOR_SCRIPT}" "${SETUP_PROXY_SCRIPT}"

# Step 1: Create emulator
echo "════════════════════════════════════════════════════════════"
echo "  Step 1/2: Creating Emulator"
echo "════════════════════════════════════════════════════════════"
echo ""

if ! bash "${CREATE_EMULATOR_SCRIPT}" "${AVD_NAME}"; then
  echo ""
  echo "❌ Failed to create emulator. Aborting setup."
  exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Step 2/2: Setting Up Proxy and Certificate"
echo "════════════════════════════════════════════════════════════"
echo ""

# Step 2: Setup proxy
if ! bash "${SETUP_PROXY_SCRIPT}" "${AVD_NAME}"; then
  echo ""
  echo "❌ Failed to set up proxy and certificate. Aborting setup."
  exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  ✔ Complete Emulator Setup Finished Successfully!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Your emulator '${AVD_NAME}' is now ready to use with:"
echo "  - mitmproxy certificate installed"
echo "  - HTTP proxy configured (${PROXY_URL})"
echo ""
echo "To stop routing traffic through the proxy, run:"
echo "  adb shell settings put global http_proxy :0"
echo ""

