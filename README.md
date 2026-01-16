# NativeAOT for Android - Getting Started Guide

Build native Android applications using .NET NativeAOT on Ubuntu.

## Quick Start

**On Ubuntu 25.10**, follow the docs step by step:

1. [Prerequisites](docs/01-prerequisites.md)
2. [Android SDK Setup](docs/02-android-sdk.md)
3. [.NET Setup](docs/03-dotnet-setup.md)
4. [Build the Sample](docs/04-build-sample.md)

Or run all steps at once:

```bash
./test/run-docs.sh
```

## Tested Environment

| Component | Version |
|-----------|---------|
| Ubuntu | 25.10 |
| .NET SDK | 9.0 |
| Android SDK Platform | 35 |
| Android NDK | 27.2.12479018 |

## Repository Structure

```
├── docs/                    # Step-by-step instructions (source of truth)
├── sample/                  # Minimal NativeAOT Android app
└── test/                    # Validation infrastructure
    ├── run-docs.sh          # Runs commands from docs (incremental)
    ├── run-in-vm.sh         # Provisions clean Ubuntu VM and tests
    └── ...
```

## Validating the Docs

### On Your Machine (Incremental)

```bash
./test/run-docs.sh              # Runs all steps, skips completed ones
./test/run-docs.sh --force      # Re-run everything
./test/run-docs.sh --from=sdk   # Start from a specific step
./test/run-docs.sh --step=sdk   # Run only one step
./test/run-docs.sh --list       # Show all steps
./test/run-docs.sh --reset      # Clear completion markers
```

### Using a Local dotnet/android Build

To test against a locally-built Android workload (from a clone of [dotnet/android](https://github.com/dotnet/android)):

```bash
# After running 'make prepare' in your dotnet/android clone
./test/run-docs.sh --local-android=/path/to/dotnet/android
```

This will:
- Use the local dotnet from `bin/{Release,Debug}/dotnet/dotnet`
- Set `DOTNETSDK_WORKLOAD_MANIFEST_ROOTS` and `DOTNETSDK_WORKLOAD_PACK_ROOTS` to point to the local build
- Skip the `dotnet-install` and `dotnet-workload` steps

See [dotnet-local-sh.md](dotnet-local-sh.md) for details on how this works.

> **Note:** The sample currently targets `net11.0-android` for local builds.
> TODO: Update the non-local scenario (docs/03-dotnet-setup.md) to use .NET 11 previews
> once available, so both scenarios use the same TFM.

### In a Clean VM (Full Validation)

```bash
./test/run-in-vm.sh             # Provision VM, run all docs, report result
./test/run-in-vm.sh --keep      # Keep VM after test for debugging
./test/run-in-vm.sh --reuse     # Re-run in existing VM
./test/run-in-vm.sh --clean     # Destroy and recreate VM
```

## Code Guidelines

- All artifacts, caches, etc. should go in a top-level 'artifacts' directory.

## License

MIT
