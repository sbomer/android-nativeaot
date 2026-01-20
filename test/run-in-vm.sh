#!/bin/bash
set -euo pipefail

# run-in-vm.sh - Provision an Ubuntu VM and run docs inside it
#
# Usage:
#   ./test/run-in-vm.sh              # Incremental (reuse VM if valid)
#   ./test/run-in-vm.sh --force      # Fresh VM, run all steps
#   ./test/run-in-vm.sh --list       # Show all steps
#   ./test/run-in-vm.sh --verbose    # Show code blocks being executed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="$REPO_ROOT/artifacts"

VM_NAME="nativeaot-test-25.10"
VM_IMAGE_URL="https://cloud-images.ubuntu.com/questing/current/questing-server-cloudimg-amd64.img"
VM_IMAGE_DIR="$ARTIFACTS_DIR/vm/base-images"
VM_IMAGE="$VM_IMAGE_DIR/ubuntu-25.10.img"
VM_DISK_DIR="$ARTIFACTS_DIR/vm/disks"
VM_DISK="$VM_DISK_DIR/$VM_NAME.qcow2"
VM_CLOUD_INIT_DIR="$ARTIFACTS_DIR/vm/cloud-init"
VM_MEMORY="16384"  # 16 GB
VM_CPUS="4"
VM_SSH_PORT="2222"  # Host port for SSH forwarding

# Use session libvirt connection (runs as user, no permission issues)
VIRSH="virsh --connect qemu:///session"
VIRT_INSTALL="virt-install --connect qemu:///session"

# SSH options for ephemeral VM (ignore host key changes)
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
GRAY='\033[0;90m'
NC='\033[0m'

log_check()   { echo -e "${GRAY}[CHECK]${NC} $1"; }
log_skip()    { echo -e "${GRAY}[SKIP]${NC} $1"; }
log_run()     { echo -e "${YELLOW}[RUN]${NC} $1"; }
log_ok()      { echo -e "${GREEN}[DONE]${NC} $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; }

# Check logging (matches run-docs.sh style)
SKIP_CHECK_LOG=""

log_check_ok() {
    SKIP_CHECK_LOG+="        ${GREEN}✓${NC} $1"$'\n'
}

log_check_fail() {
    SKIP_CHECK_LOG+="        ${RED}✗${NC} $1"$'\n'
}

reset_check_log() {
    SKIP_CHECK_LOG=""
}

show_check_log() {
    [[ -n "$SKIP_CHECK_LOG" ]] && echo -en "$SKIP_CHECK_LOG"
}

# Parse arguments
FORCE=false
LIST_ONLY=false
VERBOSE=false
INNER_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)  FORCE=true; INNER_ARGS+=("--force"); shift ;;
        --list)   LIST_ONLY=true; INNER_ARGS+=("--list"); shift ;;
        --verbose|-v) VERBOSE=true; INNER_ARGS+=("--verbose"); shift ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --force       Fresh VM and re-run all steps"
            echo "  --list        List all steps without running"
            echo "  --verbose, -v Show code blocks being executed"
            echo "  --help        Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Skip functions - return 0 to skip, 1 to run
# ─────────────────────────────────────────────────────────────────────────────

skip_prereqs() {
    command -v virsh &>/dev/null || { log_check_fail "virsh not found"; return 1; }
    log_check_ok "virsh available"

    command -v virt-install &>/dev/null || { log_check_fail "virt-install not found"; return 1; }
    log_check_ok "virt-install available"

    command -v cloud-localds &>/dev/null || { log_check_fail "cloud-localds not found"; return 1; }
    log_check_ok "cloud-localds available"

    return 0
}

skip_image() {
    [[ -f "$VM_IMAGE" ]] || { log_check_fail "image not found: $VM_IMAGE"; return 1; }
    log_check_ok "base image cached"
    return 0
}

skip_cloud_init() {
    [[ -f "$VM_CLOUD_INIT_DIR/cloud-init.img" ]] || { log_check_fail "cloud-init.img not found"; return 1; }
    log_check_ok "cloud-init.img exists"
    return 0
}

skip_vm_create() {
    $VIRSH list --all --name 2>/dev/null | grep -q "^${VM_NAME}$" || {
        log_check_fail "VM '$VM_NAME' does not exist"
        return 1
    }
    log_check_ok "VM '$VM_NAME' exists"
    return 0
}

skip_vm_start() {
    $VIRSH list --name 2>/dev/null | grep -q "^${VM_NAME}$" || {
        log_check_fail "VM '$VM_NAME' not running"
        return 1
    }
    log_check_ok "VM '$VM_NAME' running"
    return 0
}

skip_vm_accessible() {
    ssh -q "${SSH_OPTS[@]}" -o ConnectTimeout=2 -p "$VM_SSH_PORT" ubuntu@localhost true 2>/dev/null || {
        log_check_fail "SSH to localhost:$VM_SSH_PORT failed"
        return 1
    }
    log_check_ok "SSH accessible at localhost:$VM_SSH_PORT"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Step implementations
# ─────────────────────────────────────────────────────────────────────────────

run_prereqs() {
    # Prereqs are just a check - if we get here, they failed
    echo ""
    echo "Install with:"
    echo "  sudo pacman -S libvirt virt-install cloud-image-utils  # Arch"
    echo "  sudo apt-get install -y libvirt-daemon-system virtinst cloud-image-utils  # Ubuntu"
    echo "  sudo usermod -aG libvirt \$USER"
    echo "  # Log out and back in for group membership"
    return 1
}

run_image() {
    mkdir -p "$VM_IMAGE_DIR"
    echo "        Downloading Ubuntu 25.10 cloud image..."
    wget -q --show-progress -O "$VM_IMAGE" "$VM_IMAGE_URL"
}

run_cloud_init() {
    local ssh_key

    # Use existing SSH key or generate one
    if [[ -f "$HOME/.ssh/id_rsa.pub" ]]; then
        ssh_key=$(cat "$HOME/.ssh/id_rsa.pub")
    elif [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
        ssh_key=$(cat "$HOME/.ssh/id_ed25519.pub")
    else
        echo "        Generating SSH key..."
        ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -q
        ssh_key=$(cat "$HOME/.ssh/id_ed25519.pub")
    fi

    mkdir -p "$VM_CLOUD_INIT_DIR"

    cat > "$VM_CLOUD_INIT_DIR/user-data.yaml" << EOF
#cloud-config
users:                                                      
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    groups: kvm
    ssh_authorized_keys:
      - $ssh_key

package_update: true
packages:
  - git

runcmd:
  - echo "Cloud-init complete" > /var/log/cloud-init-done
EOF

    cloud-localds "$VM_CLOUD_INIT_DIR/cloud-init.img" "$VM_CLOUD_INIT_DIR/user-data.yaml"
}

run_vm_create() {
    mkdir -p "$VM_DISK_DIR"

    # Create disk from base image
    qemu-img create -f qcow2 -b "$VM_IMAGE" -F qcow2 "$VM_DISK" 50G

    # Use user networking with port forwarding (no need for system privileges)
    $VIRT_INSTALL \
        --name "$VM_NAME" \
        --memory "$VM_MEMORY" \
        --vcpus "$VM_CPUS" \
        --disk "$VM_DISK" \
        --disk "$VM_CLOUD_INIT_DIR/cloud-init.img,device=cdrom" \
        --os-variant ubuntu25.10 \
        --network none \
        --graphics none \
        --console pty,target_type=serial \
        --noautoconsole \
        --import \
        --qemu-commandline="-netdev user,id=net0,hostfwd=tcp::${VM_SSH_PORT}-:22 -device virtio-net-pci,netdev=net0,addr=0x10"
}

run_vm_start() {
    $VIRSH start "$VM_NAME"
}

run_vm_accessible() {
    echo "        Waiting for VM to be accessible..."
    local attempts=60
    while [[ $attempts -gt 0 ]]; do
        if ssh -q "${SSH_OPTS[@]}" -o ConnectTimeout=2 -p "$VM_SSH_PORT" ubuntu@localhost true 2>/dev/null; then
            echo "        Waiting for cloud-init to complete..."
            ssh "${SSH_OPTS[@]}" -p "$VM_SSH_PORT" ubuntu@localhost "cloud-init status --wait" >/dev/null 2>&1
            return 0
        fi
        sleep 5
        ((attempts--))
    done
    log_error "Timeout waiting for VM"
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Step runner
# ─────────────────────────────────────────────────────────────────────────────

# Run a step with validation-based skipping
# Returns 0 on success, 1 on failure
run_step() {
    local step_name="$1"
    local skip_fn="skip_${step_name//-/_}"
    local run_fn="run_${step_name//-/_}"

    reset_check_log
    log_check "$step_name"

    # Check if step can be skipped
    if ! $FORCE && type "$skip_fn" &>/dev/null && $skip_fn; then
        show_check_log
        log_skip "$step_name"
        return 0
    fi

    show_check_log
    log_run "$step_name"

    # Run the step
    if $run_fn; then
        log_ok "$step_name"
        return 0
    else
        log_error "$step_name"
        return 1
    fi
}

# Destroy VM (used by --force)
destroy_vm() {
    if $VIRSH list --all --name 2>/dev/null | grep -q "^${VM_NAME}$"; then
        echo -e "${GRAY}[INFO]${NC} Destroying existing VM..."
        $VIRSH destroy "$VM_NAME" 2>/dev/null || true
        $VIRSH undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
        rm -f "$VM_DISK"
    fi
}

# Run docs inside VM
run_docs_in_vm() {
    echo ""
    echo -e "${GRAY}────────────────────────────────────────${NC}"
    echo -e "${GRAY}Syncing repository to VM...${NC}"
    echo -e "${GRAY}────────────────────────────────────────${NC}"

    rsync -az -e "ssh ${SSH_OPTS[*]} -p $VM_SSH_PORT" \
        --exclude='.git' \
        --exclude='artifacts' \
        --exclude='bin' \
        --exclude='obj' \
        "$REPO_ROOT/" ubuntu@localhost:~/android-nativeaot/

    echo ""
    echo -e "${GRAY}────────────────────────────────────────${NC}"
    echo -e "${GRAY}Running docs in VM...${NC}"
    echo -e "${GRAY}────────────────────────────────────────${NC}"
    echo ""

    ssh "${SSH_OPTS[@]}" -p "$VM_SSH_PORT" ubuntu@localhost \
        "cd ~/android-nativeaot && chmod +x test/*.sh && ./test/run-docs.sh ${INNER_ARGS[*]:-}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    # List mode - just show steps and exit
    if [[ "$LIST_ONLY" == "true" ]]; then
        "$SCRIPT_DIR/run-docs.sh" --list
        exit 0
    fi

    # Force mode - destroy existing VM first
    if [[ "$FORCE" == "true" ]]; then
        destroy_vm
    fi

    # VM setup steps
    STEPS=(prereqs image cloud-init vm-create vm-start vm-accessible)

    for step in "${STEPS[@]}"; do
        run_step "$step" || exit 1
    done

    # Run docs in VM
    TEST_START=$(date +%s)

    if run_docs_in_vm; then
        TEST_END=$(date +%s)
        echo ""
        log_ok "All tests passed! ($((TEST_END - TEST_START))s)"
        echo -e "${GRAY}[INFO]${NC} VM kept running. SSH: ssh -p $VM_SSH_PORT ubuntu@localhost"
        exit 0
    else
        echo ""
        log_error "Tests failed!"
        echo -e "${GRAY}[INFO]${NC} VM kept for debugging. SSH: ssh -p $VM_SSH_PORT ubuntu@localhost"
        exit 1
    fi
}

main "$@"
