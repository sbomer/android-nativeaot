#!/bin/bash
# skip.sh - Skip functions for run-docs.sh
#
# Each function returns:
#   0 = skip (state already achieved)
#   1 = must run
#
# If no function is defined for a step, the step always runs (action steps).
#
# For logging, functions call:
#   log_check_ok "description"   - for successful checks
#   log_check_fail "description" - for failed checks (also returns 1)

# Prerequisites: build tools and Java installed
skip_prerequisites() {
    local gcc_path gcc_version
    gcc_path=$(command -v gcc) || { log_check_fail "gcc not found"; return 1; }
    gcc_version=$(gcc --version 2>/dev/null | head -1)
    log_check_ok "gcc $gcc_version ($gcc_path)"

    local java_path java_version
    java_path=$(command -v java) || { log_check_fail "java not found"; return 1; }
    java_version=$(java -version 2>&1 | head -1 | sed 's/.*"\(.*\)".*/\1/')
    log_check_ok "java $java_version ($java_path)"

    return 0
}

# JAVA_HOME set and valid
skip_java_home() {
    [[ -n "$JAVA_HOME" ]] || { log_check_fail "JAVA_HOME not set"; return 1; }
    [[ -d "$JAVA_HOME" ]] || { log_check_fail "JAVA_HOME directory not found: $JAVA_HOME"; return 1; }
    local java_version
    java_version=$("$JAVA_HOME/bin/java" -version 2>&1 | head -1 | sed 's/.*"\(.*\)".*/\1/')
    log_check_ok "JAVA_HOME $java_version ($JAVA_HOME)"

    return 0
}

# SDK command line tools downloaded
skip_sdk_download() {
    [[ -n "$ANDROID_HOME" ]] || { log_check_fail "ANDROID_HOME not set"; return 1; }
    local sdkmanager="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
    [[ -x "$sdkmanager" ]] || {
        log_check_fail "sdkmanager not found at $sdkmanager"
        return 1
    }
    local sdk_version
    sdk_version=$("$sdkmanager" --version 2>/dev/null | head -1)
    log_check_ok "sdkmanager $sdk_version ($sdkmanager)"

    return 0
}

# SDK licenses accepted
skip_sdk_licenses() {
    [[ -d "$ANDROID_HOME/licenses" ]] || {
        log_check_fail "licenses directory not found at $ANDROID_HOME/licenses"
        return 1
    }
    log_check_ok "SDK licenses accepted"

    return 0
}

# SDK components (platform-tools, NDK) installed
skip_sdk_components() {
    local adb="$ANDROID_HOME/platform-tools/adb"
    [[ -x "$adb" ]] || {
        log_check_fail "adb not found at $adb"
        return 1
    }
    local adb_version
    adb_version=$("$adb" version 2>/dev/null | head -1 | sed 's/.*version //')
    log_check_ok "adb $adb_version ($adb)"

    local ndk_dir="$ANDROID_HOME/ndk/27.2.12479018"
    [[ -d "$ndk_dir" ]] || {
        log_check_fail "NDK not found at $ndk_dir"
        return 1
    }
    local ndk_version
    if [[ -f "$ndk_dir/source.properties" ]]; then
        ndk_version=$(grep "Pkg.Revision" "$ndk_dir/source.properties" 2>/dev/null | cut -d= -f2 | tr -d ' ')
    else
        ndk_version="27.2.12479018"
    fi
    log_check_ok "NDK $ndk_version ($ndk_dir)"

    return 0
}

# .NET SDK installed
skip_dotnet_install() {
    local dotnet_path dotnet_version
    # Check DOTNET_ROOT first (set by install script), fall back to PATH
    if [[ -n "${DOTNET_ROOT:-}" && -x "$DOTNET_ROOT/dotnet" ]]; then
        dotnet_path="$DOTNET_ROOT/dotnet"
    else
        dotnet_path=$(command -v dotnet) || { log_check_fail "dotnet not found in PATH or DOTNET_ROOT"; return 1; }
    fi
    dotnet_version=$("$dotnet_path" --version 2>/dev/null) || { log_check_fail "dotnet --version failed"; return 1; }
    [[ "$dotnet_version" == 11.0.* ]] || {
        log_check_fail "dotnet version $dotnet_version (expected 11.0.x)"
        return 1
    }
    log_check_ok "dotnet $dotnet_version ($dotnet_path)"

    return 0
}

# Android workload installed
skip_dotnet_workload() {
    local dotnet_path dotnet_root
    # Use DOTNET_ROOT if available
    if [[ -n "${DOTNET_ROOT:-}" && -x "$DOTNET_ROOT/dotnet" ]]; then
        dotnet_path="$DOTNET_ROOT/dotnet"
        dotnet_root="$DOTNET_ROOT"
    else
        dotnet_path=$(command -v dotnet) || { log_check_fail "dotnet not found"; return 1; }
        dotnet_root=$(dirname "$(dirname "$dotnet_path")")
    fi

    local workload_info
    workload_info=$("$dotnet_path" workload list 2>/dev/null | grep android) || {
        log_check_fail "android workload not found in 'dotnet workload list'"
        return 1
    }

    # Extract SDK feature band from workload list (e.g., "SDK 10.0.100" -> "10.0.100")
    local workload_sdk_band
    workload_sdk_band=$(echo "$workload_info" | grep -oE 'SDK [0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}')

    # Get current SDK version and extract feature band (e.g., "10.0.102" -> "10.0.100", "11.0.100-preview.1.xxx" -> "11.0.100")
    local sdk_version sdk_feature_band
    sdk_version=$("$dotnet_path" --version 2>/dev/null)
    # Extract major.minor.patch, strip any suffix (-preview, -rc, etc), then normalize patch to 100
    sdk_feature_band=$(echo "$sdk_version" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/' | sed -E 's/([0-9]+\.[0-9]+\.)[0-9]+/\1100/')

    if [[ "$workload_sdk_band" != "$sdk_feature_band" ]]; then
        log_check_fail "workload SDK band $workload_sdk_band != current SDK band $sdk_feature_band"
        return 1
    fi

    # Find the workload pack path - check DOTNETSDK_WORKLOAD_PACK_ROOTS first (local build),
    # then fall back to standard dotnet packs location
    local workload_path pack_roots
    if [[ -n "${DOTNETSDK_WORKLOAD_PACK_ROOTS:-}" ]]; then
        pack_roots="$DOTNETSDK_WORKLOAD_PACK_ROOTS"
    else
        pack_roots="$dotnet_root/packs"
    fi
    workload_path=$(find "$pack_roots" -maxdepth 2 -type d -name "Microsoft.Android.Sdk.*" 2>/dev/null | head -1)
    [[ -n "$workload_path" ]] || {
        log_check_fail "workload pack not found in $pack_roots"
        return 1
    }

    local workload_version
    workload_version=$(echo "$workload_info" | awk '{print $2}')
    log_check_ok "android workload $workload_version (SDK $workload_sdk_band) ($workload_path)"

    return 0
}

# Sample app built
skip_build() {
    # APK path includes architecture subdirectory: net*-android/android-*/publish/
    local apk
    apk=$(find "$REPO_ROOT/sample/bin/Release" -name "*-Signed.apk" -path "*/publish/*" 2>/dev/null | head -1)
    [[ -n "$apk" ]] || {
        log_check_fail "no signed APK found in sample/bin/Release/**/publish/"
        return 1
    }
    log_check_ok "signed APK exists: ${apk#$REPO_ROOT/}"

    # Check build.log exists (contains verbose output including linker command)
    [[ -f "$REPO_ROOT/sample/build.log" ]] || {
        log_check_fail "build.log not found"
        return 1
    }
    log_check_ok "build.log exists"

    return 0
}

# Verify step (same as build)
skip_verify() {
    skip_build
}

# Emulator AVD created
skip_emulator_setup() {
    avdmanager list avd 2>/dev/null | grep -q "Name: test" || {
        log_check_fail "AVD 'test' not found in 'avdmanager list avd'"
        return 1
    }
    log_check_ok "AVD 'test' exists"

    return 0
}

# Emulator running and responsive
skip_emulator_start() {
    local adb="$ANDROID_HOME/platform-tools/adb"
    [[ -x "$adb" ]] || { log_check_fail "adb not found at $adb"; return 1; }

    # Check if emulator-5554 is in adb devices
    "$adb" devices 2>/dev/null | grep -q "emulator-5554" || {
        log_check_fail "emulator-5554 not in 'adb devices'"
        return 1
    }
    log_check_ok "emulator-5554 connected"

    # Check if emulator has finished booting
    local boot_completed
    boot_completed=$("$adb" -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    [[ "$boot_completed" == "1" ]] || {
        log_check_fail "emulator not fully booted (sys.boot_completed=$boot_completed)"
        return 1
    }
    log_check_ok "emulator fully booted"

    return 0
}

# run-app: no skip function → always runs (it's an action, not a state)
