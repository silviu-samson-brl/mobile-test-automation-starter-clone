Device Setup Kit
================

This archive contains:
  - proxy.env                          Proxy configuration (edit if address changes)
  - mitmproxy-ca-cert.pem              CA certificate for proxy interception
  - full_setup_android_emulator.sh     Full Android setup (create + proxy + cert)
  - create_android_emulator.sh         Create Android emulator only
  - proxy_setup_android_emulator.sh    Proxy & certificate setup for existing emulator
  - serve_certificate_ios.sh           iOS device certificate setup

Proxy address: 54.80.17.8:7777
To change it, edit proxy.env before running any script.

First, make all scripts executable:
  chmod +x *.sh


ANDROID - FULL SETUP (RECOMMENDED)
-----------------------------------
Creates the emulator, installs the certificate, and configures the proxy — all in one step.

  ./full_setup_android_emulator.sh [AVD_NAME]

Default AVD name: MediumPhoneGoogleAPIs


ANDROID - CREATE EMULATOR ONLY
-------------------------------
Use this if you only need to create the emulator without proxy/certificate setup.

  ./create_android_emulator.sh [AVD_NAME]

Requires: avdmanager, sdkmanager in PATH.


ANDROID - PROXY & CERTIFICATE ONLY
------------------------------------
Use this if you already have an emulator and only need the proxy/certificate setup.

  ./proxy_setup_android_emulator.sh [AVD_NAME] ./mitmproxy-ca-cert.pem

The script will start the emulator, install the certificate,
and set the HTTP proxy to 54.80.17.8:7777.


iOS PHYSICAL DEVICE
-------------------
1. Run the script:
   ./serve_certificate_ios.sh [PORT] ./mitmproxy-ca-cert.pem

2. On your iOS device (same WiFi network):
   - Open the URL shown by the script in Safari
   - Install the profile when prompted
   - Go to Settings > General > About > Certificate Trust Settings
   - Enable full trust for the mitmproxy certificate
   - Configure HTTP proxy: Server=54.80.17.8, Port=7777
