# Build the Sample

This guide walks through building and running the sample NativeAOT Android application.

## Build the Application

Navigate to the sample directory and publish:

<!-- step: build -->
```bash
cd sample
dotnet publish -c Release
```

This will:
1. Compile the C# code to native ARM64 code using NativeAOT
2. Package it into an Android APK
3. Sign the APK for installation

Build time is typically 2-5 minutes depending on your hardware.

## Locate the APK

After a successful build, the signed APK is at:

```text
sample/bin/Release/net9.0-android/publish/com.example.nativeaot-Signed.apk
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
