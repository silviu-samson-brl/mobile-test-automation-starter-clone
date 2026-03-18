#!/usr/bin/env bash
set -euo pipefail

# Emulator creation parameters
AVD_NAME="${1:-MediumPhoneGoogleAPIs}"
DEVICE_NAME="medium_phone"
SYSTEM_IMAGE="system-images;android-36;google_apis;x86_64"
PACKAGE="system-images;android-36;google_apis;x86_64"

# Show usage if help requested
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  echo "Usage: $0 [AVD_NAME]"
  echo ""
  echo "Creates an Android Virtual Device (AVD) for testing."
  echo ""
  echo "Arguments:"
  echo "  AVD_NAME    Name of the Android Virtual Device (default: MP)"
  echo ""
  echo "The script will:"
  echo "  1. Check if emulator already exists"
  echo "  2. Install system image if needed (API 36 Google APIs ARM64)"
  echo "  3. Create AVD with Medium Phone device profile"
  echo "  4. Configure hardware properties for keyboard input and button controls"
  echo ""
  exit 0
fi

echo "→ Creating Android emulator '${AVD_NAME}'..."
echo ""

# Check if emulator already exists
if avdmanager list avd 2>/dev/null | grep -q "Name: ${AVD_NAME}"; then
  echo "✓ Emulator '${AVD_NAME}' already exists"
  exit 0
fi

echo "   Emulator '${AVD_NAME}' not found. Creating new emulator..."
echo ""

# Check if avdmanager exists
if ! command -v avdmanager &> /dev/null; then
  echo "❌ avdmanager command not found. Make sure Android SDK is installed and tools are in PATH"
  echo "   Expected location: \$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager"
  exit 1
fi

# Check if sdkmanager exists
if ! command -v sdkmanager &> /dev/null; then
  echo "⚠️  sdkmanager command not found. Skipping system image check."
  echo "   Please ensure the system image is installed manually:"
  echo "   sdkmanager \"${PACKAGE}\""
else
  # Check if system image is installed
  echo "→ Checking if system image is installed..."
  if ! sdkmanager --list_installed 2>/dev/null | grep -q "${PACKAGE}"; then
    echo "   System image not found. Installing ${PACKAGE}..."
    echo "   This may take a few minutes..."
    if ! sdkmanager "${PACKAGE}" --accept-licenses; then
      echo "❌ Failed to install system image. Please install it manually:"
      echo "   sdkmanager \"${PACKAGE}\""
      exit 1
    fi
    echo "   ✓ System image installed"
  else
    echo "   ✓ System image already installed"
  fi
fi

# Create the AVD
echo ""
echo "→ Creating AVD '${AVD_NAME}'..."
echo "   Device: ${DEVICE_NAME}"
echo "   System Image: ${SYSTEM_IMAGE}"
echo ""

# Verify device exists
if ! avdmanager list device 2>/dev/null | grep -q "id: ${DEVICE_NAME}\|or \"${DEVICE_NAME}\""; then
  echo "⚠️  Device '${DEVICE_NAME}' not found in available devices."
  echo "   Available devices:"
  avdmanager list device 2>/dev/null | grep "id:" | head -5
  echo ""
  echo "   Continuing anyway (avdmanager will use default if device not found)..."
fi

# Use echo "no" to auto-answer the "Do you wish to create a custom hardware profile" prompt
TEMP_OUTPUT=$(mktemp)
if echo "no" | avdmanager create avd \
  -n "${AVD_NAME}" \
  -k "${SYSTEM_IMAGE}" \
  -d "${DEVICE_NAME}" > "${TEMP_OUTPUT}" 2>&1; then
  echo "✓ Emulator '${AVD_NAME}' created successfully"
  rm -f "${TEMP_OUTPUT}"
  
  # Configure hardware properties for keyboard input and button controls
  echo ""
  echo "→ Configuring hardware properties for keyboard and button controls..."
  
  # Find the AVD config.ini file
  # AVD configs are typically stored in ~/.android/avd/${AVD_NAME}.avd/config.ini
  AVD_CONFIG_DIR="${HOME}/.android/avd/${AVD_NAME}.avd"
  AVD_CONFIG_FILE="${AVD_CONFIG_DIR}/config.ini"
  
  # Alternative location if ANDROID_SDK_ROOT is set
  if [[ -n "${ANDROID_SDK_ROOT:-}" ]] && [[ -d "${ANDROID_SDK_ROOT}/.android/avd/${AVD_NAME}.avd" ]]; then
    AVD_CONFIG_DIR="${ANDROID_SDK_ROOT}/.android/avd/${AVD_NAME}.avd"
    AVD_CONFIG_FILE="${AVD_CONFIG_DIR}/config.ini"
  fi
  
  if [[ -f "${AVD_CONFIG_FILE}" ]]; then
    # Backup original config
    cp "${AVD_CONFIG_FILE}" "${AVD_CONFIG_FILE}.backup"
    
    # Enable hardware keyboard (required for laptop keyboard input)
    if ! grep -q "^hw.keyboard = yes" "${AVD_CONFIG_FILE}"; then
      echo "hw.keyboard = yes" >> "${AVD_CONFIG_FILE}"
      echo "   ✓ Enabled hardware keyboard"
    fi
    
    # Enable keyboard lid (required for proper keyboard handling)
    if ! grep -q "^hw.keyboard.lid = yes" "${AVD_CONFIG_FILE}"; then
      echo "hw.keyboard.lid = yes" >> "${AVD_CONFIG_FILE}"
      echo "   ✓ Enabled keyboard lid support"
    fi
    
    # Ensure DPAD is enabled (for button controls)
    if ! grep -q "^hw.dpad = yes" "${AVD_CONFIG_FILE}"; then
      echo "hw.dpad = yes" >> "${AVD_CONFIG_FILE}"
      echo "   ✓ Enabled DPAD controls"
    fi
    
    # Ensure trackball is enabled (helps with button interactions)
    if ! grep -q "^hw.trackBall = yes" "${AVD_CONFIG_FILE}"; then
      echo "hw.trackBall = yes" >> "${AVD_CONFIG_FILE}"
      echo "   ✓ Enabled trackball"
    fi
    
    echo "   ✓ Hardware configuration updated"
  else
    echo "⚠️  Warning: Could not find AVD config file at ${AVD_CONFIG_FILE}"
    echo "   Keyboard and button controls may not work properly."
    echo "   You may need to configure these manually in Android Studio's AVD Manager."
  fi
else
  echo "❌ Failed to create AVD. Error details:"
  cat "${TEMP_OUTPUT}"
  echo ""
  echo "Troubleshooting tips:"
  echo "  1. Verify the system image is installed: sdkmanager --list_installed | grep '${SYSTEM_IMAGE}'"
  echo "  2. Check available devices: avdmanager list device"
  echo "  3. Try creating manually:"
  echo "     avdmanager create avd -n ${AVD_NAME} -k \"${SYSTEM_IMAGE}\" -d ${DEVICE_NAME}"
  rm -f "${TEMP_OUTPUT}"
  exit 1
fi

echo ""
echo "✔ Emulator creation complete!"
echo ""
echo "You can now start the emulator with:"
echo "  emulator -avd \"${AVD_NAME}\" -writable-system -no-snapshot -selinux permissive"

