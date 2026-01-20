#!/bin/bash
set -euo pipefail

# stop-emulator.sh - Stop the Android emulator
#
# Usage:
#   ./test/stop-emulator.sh          # Stop emulator if running
#   ./test/stop-emulator.sh --force  # Kill immediately without graceful shutdown

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# Colors
GREEN='\033[0;32m'
GRAY='\033[0;90m'
NC='\033[0m'

SERIAL="emulator-5554"

# Check if emulator is running
if ! adb devices 2>/dev/null | grep -q "$SERIAL"; then
    echo -e "${GRAY}[INFO]${NC} Emulator not running"
    exit 0
fi

if [[ "$FORCE" == "true" ]]; then
    echo -e "${GRAY}[INFO]${NC} Force killing emulator..."
    # Kill the emulator process directly
    pkill -9 -f "emulator.*-avd" 2>/dev/null || true
    adb -s "$SERIAL" emu kill 2>/dev/null || true
else
    echo -e "${GRAY}[INFO]${NC} Stopping emulator gracefully..."
    adb -s "$SERIAL" emu kill 2>/dev/null || true
fi

# Wait for emulator to disappear from adb devices
for i in $(seq 1 30); do
    if ! adb devices 2>/dev/null | grep -q "$SERIAL"; then
        echo -e "${GREEN}[DONE]${NC} Emulator stopped"
        exit 0
    fi
    sleep 1
done

echo -e "${GRAY}[WARN]${NC} Emulator may still be shutting down"
exit 0
