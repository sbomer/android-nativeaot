# .NET Setup

This guide covers installing .NET SDK with NativeAOT support for Android.

## Install .NET SDK

<!-- step: dotnet-install -->
```bash
curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 10.0
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools"
```

## Install Android Workload

The Android workload provides NativeAOT support for Android targets.

<!-- step: dotnet-workload -->
```bash
dotnet workload install android
```

## Verify Installation

```text
$ dotnet --version
10.0.x

$ dotnet workload list
Installed Workload Id    Manifest Version    Installation Source
----------------------------------------------------------------------
android                  ...                 SDK 10.0.x
```

## NativeAOT Configuration

When creating a NativeAOT Android project, ensure your `.csproj` includes:

```xml
<PropertyGroup>
    <PublishAot>true</PublishAot>
    <RuntimeIdentifier>android-arm64</RuntimeIdentifier>
</PropertyGroup>
```

## Supported Runtime Identifiers

| RID | Description |
|-----|-------------|
| `android-arm64` | 64-bit ARM (most modern devices) |
| `android-arm` | 32-bit ARM (legacy devices) |
| `android-x64` | 64-bit x86 (emulators) |
| `android-x86` | 32-bit x86 (legacy emulators) |

## Next Steps

Continue to [Build the Sample](04-build-sample.md).
