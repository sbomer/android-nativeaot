# Prerequisites

This guide covers the system requirements for building NativeAOT Android applications.

## System Requirements

- **Ubuntu 25.10**
- At least 16 GB RAM (NativeAOT compilation is memory-intensive)
- 30 GB free disk space

## Install Required Packages

<!-- step: prerequisites -->
```bash
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    curl \
    wget \
    git \
    unzip \
    zip \
    openjdk-17-jdk
```

## Verify Java Installation

After installing, verify Java is available:

```text
$ java -version
openjdk version "17.0.x" ...
```

## Set JAVA_HOME

<!-- step: java-home -->
```bash
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
```

## Next Steps

Continue to [Android SDK Setup](02-android-sdk.md).
