Device Setup Kit
================

This folder contains:
  - proxy.env                          Proxy configuration (edit if address changes)
  - mitmproxy-ca-cert.pem              CA certificate for proxy interception (not here, on github, but needs to be copied here before VM setup)
  - full_setup_android_emulator.sh     Full Android setup (create + proxy + cert)
  - create_android_emulator.sh         Create Android emulator only
  - proxy_setup_android_emulator.sh    Proxy & certificate setup for existing emulator

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
