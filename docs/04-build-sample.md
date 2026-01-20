# Build the Sample

This guide walks through building and running the sample NativeAOT Android application.

## Build the Application

Navigate to the sample directory and publish:

<!-- step: build -->
```bash
cd sample
dotnet publish -c Release -v detailed 2>&1 | tee build.log
```

This will:
1. Compile the C# code to native ARM64 code using NativeAOT
2. Package it into an Android APK
3. Sign the APK for installation

Build time is typically 2-5 minutes depending on your hardware.

## Locate the APK

After a successful build, the signed APK is at:

```text
sample/bin/Release/net10.0-android/publish/com.example.nativeaot-Signed.apk
```

## Install on Device (Optional)

If you have an Android device connected via USB or an emulator running:

```bash
adb install -r bin/Release/net9.0-android/publish/*-Signed.apk
```

Launch the app:

```bash
adb shell am start -n com.example.nativeaot/.MainActivity
```

## Verify the Build

<!-- step: verify -->
```bash
cd sample
APK=$(find bin/Release -name "*-Signed.apk" -type f | head -1)
if [[ -f "$APK" ]]; then
    echo "SUCCESS: APK built at $APK"
    ls -lh "$APK"
else
    echo "FAILED: APK not found"
    exit 1
fi
```

## Run in Emulator

First, install the emulator and create an AVD (Android Virtual Device):

<!-- step: emulator-setup -->
```bash
sdkmanager --install "emulator" "system-images;android-36;google_apis;x86_64"
echo "no" | avdmanager create avd -n test -k "system-images;android-36;google_apis;x86_64" --force
```

Start the emulator in the background and wait for it to boot:

<!-- step: emulator-start -->
```bash
export ANDROID_SERIAL=emulator-5554

# Start emulator only if not already running
if ! adb devices 2>/dev/null | grep -q "$ANDROID_SERIAL"; then
    emulator -avd test -port 5554 -no-audio -no-window -no-snapshot &
    timeout 60 adb wait-for-device || { echo "Emulator failed to connect"; exit 1; }
fi

# Wait for boot to complete
timeout 60 adb shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done' || { echo "Emulator failed to boot"; exit 1; }

echo "Emulator ready"
```

Install the app:

<!-- step: install-app -->
```bash
cd sample
APK=$(find bin/Release -name "*-Signed.apk" -type f | head -1)
adb uninstall com.example.nativeaot 2>/dev/null || true
adb install "$APK"
```

Launch and verify the app:

<!-- step: run-app -->
```bash
cd sample
PACKAGE="com.example.nativeaot"
SUCCESS_TAG="NativeAotSample"
SUCCESS_MSG="APP_STARTED_SUCCESSFULLY"

# Get the actual activity name from the APK (NativeAOT uses hashed class names)
APK=$(find bin/Release -name "*-Signed.apk" -type f | head -1)
AAPT=$(find "$ANDROID_HOME/build-tools" -name "aapt" | sort -V | tail -1)
ACTIVITY=$("$AAPT" dump badging "$APK" 2>/dev/null | grep "launchable-activity" | sed "s/.*name='\([^']*\)'.*/\1/")
if [[ -z "$ACTIVITY" ]]; then
    echo "FAILED: Could not determine activity name from APK"
    exit 1
fi
echo "Launching activity: $ACTIVITY"

# Clear logcat so we only see messages from this launch
adb logcat -c

# Start activity
adb shell am start -n "$PACKAGE/$ACTIVITY"

# Wait for success message or crash (up to 15 seconds)
echo "Waiting for app to start..."
for i in $(seq 1 15); do
    sleep 1
    
    # Check for success message in logcat
    if adb logcat -d -s "$SUCCESS_TAG:I" 2>/dev/null | grep -q "$SUCCESS_MSG"; then
        echo "SUCCESS: App started successfully"
        exit 0
    fi
    
    # Check for crash
    if adb logcat -d 2>/dev/null | grep -q "Process $PACKAGE.*has died"; then
        echo "FAILED: App crashed"
        adb logcat -d | grep -E "FATAL|F DEBUG|AndroidRuntime" | head -20
        exit 1
    fi
done

echo "FAILED: Timeout waiting for app to start"
adb logcat -d | grep -E "$SUCCESS_TAG|FATAL|AndroidRuntime" | tail -20
exit 1
```

## Troubleshooting

### Out of Memory

NativeAOT compilation requires significant RAM. If the build fails or the system becomes unresponsive:

```bash
# Add temporary swap space
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### NDK Not Found

Ensure environment variables are set:

```bash
echo $ANDROID_NDK_HOME
# Should output: /home/<user>/android-sdk/ndk/27.2.12479018
```

If empty, re-run the SDK setup steps.

## Next Steps

Congratulations! You've built a NativeAOT Android application.

Explore the sample code in [sample/](../sample/) to understand how it works.
