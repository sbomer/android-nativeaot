# Android SDK Setup

This guide covers installing the Android SDK and NDK required for NativeAOT compilation.

## Overview

NativeAOT for Android requires:
- **Android SDK Command Line Tools** - For managing SDK components
- **Android NDK** - Provides the native toolchain for ARM/x86 compilation
- **Android Platform Tools** - For deploying to devices (adb)

## Set Up Environment Variables

First, define where the SDK will be installed:

```bash
export ANDROID_HOME="$HOME/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin"
export PATH="$PATH:$ANDROID_HOME/platform-tools"
export PATH="$PATH:$ANDROID_HOME/emulator"
```

## Download Command Line Tools

<!-- step: sdk-download -->
```bash
mkdir -p "$ANDROID_HOME/cmdline-tools"
cd /tmp
wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O cmdline-tools.zip
unzip -q cmdline-tools.zip
rm -rf "$ANDROID_HOME/cmdline-tools/latest"
mv cmdline-tools "$ANDROID_HOME/cmdline-tools/latest"
rm cmdline-tools.zip
```

## Accept Licenses

<!-- step: sdk-licenses -->
```bash
yes | sdkmanager --licenses || true
```

## Install SDK Components

<!-- step: sdk-components -->
```bash
sdkmanager --install \
    "platform-tools" \
    "platforms;android-36" \
    "build-tools;36.0.0" \
    "ndk;27.2.12479018"
```

## Set NDK Environment Variable

```bash
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/27.2.12479018"
```

## Verify Installation

```text
$ sdkmanager --version
12.0

$ adb --version
Android Debug Bridge version 1.0.41

$ ls $ANDROID_NDK_HOME
...
```

## Next Steps

Continue to [.NET Setup](03-dotnet-setup.md).
