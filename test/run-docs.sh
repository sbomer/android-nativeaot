#!/bin/bash
set -euo pipefail

# run-docs.sh - Extract and run code blocks from documentation
#
# Usage:
#   ./test/run-docs.sh                           # Incremental (skip completed steps)
#   ./test/run-docs.sh --force                   # Re-run all steps
#   ./test/run-docs.sh --list                    # Show all steps
#   ./test/run-docs.sh --local-android=/path     # Use local dotnet/android build
#   ./test/run-docs.sh --env-file=/path          # Source additional environment setup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DOCS_DIR="$REPO_ROOT/docs"
ARTIFACTS_DIR="$REPO_ROOT/artifacts"
ENV_FILE="$ARTIFACTS_DIR/env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[DONE]${NC} $1"; }
log_skip()    { echo -e "${GRAY}[SKIP]${NC} $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; }
log_run()     { echo -e "${YELLOW}[RUN]${NC} $1"; }

# Logging for skip checks (used by skip.sh functions)
# These are captured and only shown on failure or in verbose mode
SKIP_CHECK_LOG=""
SKIP_CHECK_FAILED=""

log_check_ok() {
    SKIP_CHECK_LOG+="        ${GREEN}✓${NC} $1"$'\n'
}

log_check_fail() {
    SKIP_CHECK_LOG+="        ${RED}✗${NC} $1"$'\n'
    SKIP_CHECK_FAILED="true"
}

reset_check_log() {
    SKIP_CHECK_LOG=""
    SKIP_CHECK_FAILED=""
}

show_check_log() {
    if [[ -n "$SKIP_CHECK_LOG" ]]; then
        echo -en "$SKIP_CHECK_LOG"
    fi
}

# Parse arguments
FORCE=false
LIST_ONLY=false
LOCAL_ANDROID_REPO=""
EXTRA_ENV_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)  FORCE=true; shift ;;
        --list)   LIST_ONLY=true; shift ;;
        --local-android=*)
            LOCAL_ANDROID_REPO="${1#*=}"
            shift
            ;;
        --local-android)
            LOCAL_ANDROID_REPO="$2"
            shift 2
            ;;
        --env-file=*)
            EXTRA_ENV_FILE="${1#*=}"
            shift
            ;;
        --env-file)
            EXTRA_ENV_FILE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --force                 Re-run all steps (ignore skip checks)"
            echo "  --list                  List all steps without running"
            echo "  --local-android=PATH    Use local dotnet/android build instead of installed workload"
            echo "  --env-file=PATH         Source additional environment variables from file"
            echo "  --help                  Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Force mode clears env file (skip functions check actual state, not markers)
if [[ "$FORCE" == "true" ]]; then
    rm -f "$ENV_FILE"
fi

mkdir -p "$ARTIFACTS_DIR"
touch "$ENV_FILE"

# Source skip functions (provides skip_<step> functions)
source "$SCRIPT_DIR/skip.sh"

# Include extra environment file if specified
if [[ -n "$EXTRA_ENV_FILE" ]]; then
    if [[ ! -f "$EXTRA_ENV_FILE" ]]; then
        log_error "Environment file not found: $EXTRA_ENV_FILE"
        exit 1
    fi
    cat "$EXTRA_ENV_FILE" >> "$ENV_FILE"
fi

# Setup local Android workload if specified
if [[ -n "$LOCAL_ANDROID_REPO" ]]; then
    if [[ ! -d "$LOCAL_ANDROID_REPO" ]]; then
        log_error "Local Android repo not found: $LOCAL_ANDROID_REPO"
        exit 1
    fi

    # Find config (Release or Debug) with built dotnet
    LOCAL_CONFIG=""
    for config in Release Debug; do
        if [[ -x "$LOCAL_ANDROID_REPO/bin/$config/dotnet/dotnet" ]]; then
            LOCAL_CONFIG="$config"
            break
        fi
    done

    if [[ -z "$LOCAL_CONFIG" ]]; then
        log_error "No built dotnet found in $LOCAL_ANDROID_REPO/bin/{Release,Debug}/dotnet/dotnet"
        log_error "Run 'make prepare' in dotnet/android first"
        exit 1
    fi

    LOCAL_DOTNET_DIR="$LOCAL_ANDROID_REPO/bin/$LOCAL_CONFIG/dotnet"
    LOCAL_LIB_DIR="$LOCAL_ANDROID_REPO/bin/$LOCAL_CONFIG/lib"

    # Set environment variables for local workload (matching dotnet-local.sh)
    {
        echo "export PATH=\"$LOCAL_DOTNET_DIR:\$PATH\""
        echo "export DOTNETSDK_WORKLOAD_MANIFEST_ROOTS=\"$LOCAL_LIB_DIR/sdk-manifests\""
        echo "export DOTNETSDK_WORKLOAD_PACK_ROOTS=\"$LOCAL_LIB_DIR\""
    } >> "$ENV_FILE"
fi

# Extract steps from all docs using a temp directory approach
# This avoids delimiter issues with code containing special characters
#
# Unmarked bash blocks (no step marker) are accumulated as "preamble" and
# prepended to the next real step. This allows env var exports to be in
# separate code blocks in docs without being separate steps.
extract_steps() {
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" RETURN

    local step_index=0

    for doc in "$DOCS_DIR"/*.md; do
        [[ -f "$doc" ]] || continue

        local current_step=""
        local in_bash_block=false
        local code_buffer=""
        local preamble=""  # Accumulates unmarked code blocks

        while IFS= read -r line || [[ -n "$line" ]]; do
            # Check for step marker
            if [[ "$line" =~ ^\<!--\ step:\ ([a-zA-Z0-9_-]+)\ --\>$ ]]; then
                current_step="${BASH_REMATCH[1]}"
                continue
            fi

            # Check for bash block start
            if [[ "$line" == '```bash' ]]; then
                in_bash_block=true
                code_buffer=""
                continue
            fi

            # Check for block end
            if [[ "$line" == '```' && "$in_bash_block" == "true" ]]; then
                in_bash_block=false

                if [[ -n "$current_step" ]]; then
                    # This is a real step - prepend any accumulated preamble
                    if [[ -n "$preamble" ]]; then
                        code_buffer="${preamble}"$'\n'"${code_buffer}"
                        preamble=""
                    fi
                    # Write step info to temp files
                    printf '%s\n' "$current_step" > "$temp_dir/${step_index}.step"
                    printf '%s\n' "$(basename "$doc")" > "$temp_dir/${step_index}.doc"
                    printf '%s\n' "$code_buffer" > "$temp_dir/${step_index}.code"
                    ((step_index++))
                    current_step=""
                else
                    # Unmarked block - accumulate as preamble for next step
                    if [[ -n "$preamble" ]]; then
                        preamble="${preamble}"$'\n'"${code_buffer}"
                    else
                        preamble="${code_buffer}"
                    fi
                fi
                continue
            fi

            # Accumulate code
            if [[ "$in_bash_block" == "true" ]]; then
                if [[ -n "$code_buffer" ]]; then
                    code_buffer="${code_buffer}"$'\n'"${line}"
                else
                    code_buffer="${line}"
                fi
            fi
        done < "$doc"
    done

    # Output the temp dir path
    echo "$temp_dir"
    trap - RETURN  # Don't delete on return, caller will handle
}

# Store steps in arrays
declare -a STEPS=()
declare -A STEP_CODE=()
declare -A STEP_DOC=()

TEMP_STEPS_DIR=$(extract_steps)
trap "rm -rf '$TEMP_STEPS_DIR'" EXIT

shopt -s nullglob
# Sort by numeric index (the filename before .step)
while IFS= read -r stepfile; do
    [[ -f "$stepfile" ]] || continue

    local_base="${stepfile%.step}"
    step=$(cat "$local_base.step")
    doc=$(cat "$local_base.doc")
    code=$(cat "$local_base.code")

    STEPS+=("$step")
    STEP_CODE["$step"]="$code"
    STEP_DOC["$step"]="$doc"
done < <(find "$TEMP_STEPS_DIR" -name "*.step" -print0 | sort -zV | xargs -0 -n1 echo)
shopt -u nullglob

# List mode
if [[ "$LIST_ONLY" == "true" ]]; then
    echo "Available steps:"
    echo ""

    for step in "${STEPS[@]}"; do
        skip_func="skip_${step//-/_}"

        if ! declare -f "$skip_func" > /dev/null; then
            # No skip function = always runs
            echo -e "  ${YELLOW}▶${NC} $step (${STEP_DOC[$step]}) ${GRAY}[always runs]${NC}"
        else
            # Has skip function = state check
            echo -e "  ○ $step (${STEP_DOC[$step]})"
        fi
    done
    exit 0
fi

# Run steps
run_step() {
    local step="$1"
    local code="${STEP_CODE[$step]}"
    local doc="${STEP_DOC[$step]}"
    local skip_func="skip_${step//-/_}"  # Convert hyphens to underscores

    # Always extract export lines to env file (even if step is skipped)
    # This ensures env vars from preamble blocks are available to later steps
    while IFS= read -r line; do
        if [[ "$line" =~ ^export\ +([A-Za-z_][A-Za-z0-9_]*)= ]]; then
            echo "$line" >> "$ENV_FILE"
        fi
    done <<< "$code"

    # Check if skip function exists
    if declare -f "$skip_func" > /dev/null; then
        # Skip function exists - use it to validate state
        if [[ "$FORCE" != "true" ]]; then
            reset_check_log

            # Source env and run skip check
            set +u
            source "$ENV_FILE"
            set -u

            if "$skip_func"; then
                # Validation passed - state already achieved
                echo -e "${GRAY}[CHECK]${NC} $step"
                show_check_log
                log_skip "$step ($doc)"
                LAST_STEP_ACTION="skipped"
                return 0
            else
                # Validation failed - need to run step
                echo -e "${GRAY}[CHECK]${NC} $step"
                show_check_log
            fi
        fi
    fi
    # No skip function = always run (action step), fall through

    log_run "$step ($doc)"

    # Show commands being run
    echo -e "${GRAY}────────────────────────────────────────${NC}"
    echo -e "${GRAY}${code}${NC}"
    echo -e "${GRAY}────────────────────────────────────────${NC}"

    # Run in subshell with env sourced
    if (
        set +u  # Allow unbound vars during source
        source "$ENV_FILE"
        set -u
        cd "$REPO_ROOT"
        eval "$code"
    ); then
        # Step succeeded - validate postcondition if skip function exists
        if declare -f "$skip_func" > /dev/null; then
            reset_check_log
            # Source env for postcondition check
            set +u
            source "$ENV_FILE"
            set -u

            if "$skip_func"; then
                log_success "$step [validated]"
                LAST_STEP_ACTION="ran"
                return 0
            else
                echo -e "${RED}[VALIDATE]${NC} $step - postcondition failed:"
                show_check_log
                log_error "$step (ran but postcondition not satisfied)"
                LAST_STEP_ACTION="failed"
                return 1
            fi
        else
            log_success "$step"
            LAST_STEP_ACTION="ran"
            return 0
        fi
    else
        log_error "$step"
        LAST_STEP_ACTION="failed"
        return 1
    fi
}

# Run all steps
steps_run=0
steps_skipped=0
steps_failed=0
LAST_STEP_ACTION=""  # Set by run_step: "ran", "skipped", or "failed"

for step in "${STEPS[@]}"; do
    if run_step "$step"; then
        if [[ "$LAST_STEP_ACTION" == "ran" ]]; then
            ((steps_run++)) || true
        else
            ((steps_skipped++)) || true
        fi
    else
        ((steps_failed++))
        log_error "Stopping due to failure"
        break
    fi
done

echo ""
log_info "Summary: $steps_run ran, $steps_skipped skipped, $steps_failed failed"

if [[ $steps_failed -gt 0 ]]; then
    exit 1
fi
