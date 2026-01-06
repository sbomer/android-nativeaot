#!/bin/bash
set -euo pipefail

# run-docs.sh - Extract and run code blocks from documentation
#
# Usage:
#   ./test/run-docs.sh          # Incremental (skip completed steps)
#   ./test/run-docs.sh --force  # Re-run all steps
#   ./test/run-docs.sh --list   # Show all steps

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DOCS_DIR="$REPO_ROOT/docs"
ARTIFACTS_DIR="$REPO_ROOT/artifacts"
MARKER_DIR="$ARTIFACTS_DIR/step-markers"
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

# Parse arguments
FORCE=false
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)  FORCE=true; shift ;;
        --list)   LIST_ONLY=true; shift ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --force   Re-run all steps (clears markers first)"
            echo "  --list    List all steps without running"
            echo "  --help    Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Force mode clears markers and env first
if [[ "$FORCE" == "true" ]]; then
    rm -rf "$MARKER_DIR"
    rm -f "$ENV_FILE"
fi

mkdir -p "$MARKER_DIR"
touch "$ENV_FILE"

# Extract steps from all docs using a temp directory approach
# This avoids delimiter issues with code containing special characters
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
        
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Check for step marker
            if [[ "$line" =~ ^\<!--\ step:\ ([a-zA-Z0-9_-]+)\ --\>$ ]]; then
                current_step="${BASH_REMATCH[1]}"
                continue
            fi
            
            # Check for bash block start
            if [[ "$line" == '```bash' && -n "$current_step" ]]; then
                in_bash_block=true
                code_buffer=""
                continue
            fi
            
            # Check for block end
            if [[ "$line" == '```' && "$in_bash_block" == "true" ]]; then
                in_bash_block=false
                # Write step info to temp files
                printf '%s\n' "$current_step" > "$temp_dir/${step_index}.step"
                printf '%s\n' "$(basename "$doc")" > "$temp_dir/${step_index}.doc"
                printf '%s\n' "$code_buffer" > "$temp_dir/${step_index}.code"
                ((step_index++))
                current_step=""
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
        marker="$MARKER_DIR/$step.done"
        if [[ -f "$marker" ]]; then
            echo -e "  ${GREEN}✓${NC} $step (${STEP_DOC[$step]})"
        else
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
    local marker="$MARKER_DIR/$step.done"
    
    # Check if should skip (already completed)
    if [[ -f "$marker" ]]; then
        log_skip "$step ($doc)"
        return 0
    fi
    
    log_run "$step ($doc)"
    
    # Show commands being run
    echo -e "${GRAY}────────────────────────────────────────${NC}"
    echo -e "${GRAY}${code}${NC}"
    echo -e "${GRAY}────────────────────────────────────────${NC}"
    
    # Extract export lines and save to env file
    while IFS= read -r line; do
        if [[ "$line" =~ ^export\ +([A-Za-z_][A-Za-z0-9_]*)= ]]; then
            echo "$line" >> "$ENV_FILE"
        fi
    done <<< "$code"
    
    # Run in subshell with env sourced
    if (
        set +u  # Allow unbound vars during source
        source "$ENV_FILE"
        set -u
        cd "$REPO_ROOT"
        set -x
        eval "$code"
    ); then
        touch "$marker"
        log_success "$step"
        return 0
    else
        log_error "$step"
        return 1
    fi
}

# Run all steps
steps_run=0
steps_skipped=0
steps_failed=0

log_info "Running documentation steps..."
echo ""

for step in "${STEPS[@]}"; do
    if run_step "$step"; then
        if [[ -f "$MARKER_DIR/$step.done" ]]; then
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
log_info "Summary: $steps_run completed, $steps_skipped skipped, $steps_failed failed"

if [[ $steps_failed -gt 0 ]]; then
    exit 1
fi
