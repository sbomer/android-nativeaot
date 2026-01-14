#!/bin/bash
set -euo pipefail

# run-in-vm.sh - Provision an Ubuntu VM and run docs inside it
#
# Usage:
#   ./test/run-in-vm.sh          # Incremental (reuse VM and step markers)
#   ./test/run-in-vm.sh --force  # Fresh VM, run all steps
#   ./test/run-in-vm.sh --list   # Show all steps

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="$REPO_ROOT/artifacts"
MARKER_DIR="$ARTIFACTS_DIR/step-markers"

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
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[VM]${NC} $1"; }
log_success() { echo -e "${GREEN}[VM]${NC} $1"; }
log_error()   { echo -e "${RED}[VM]${NC} $1"; }

# Parse arguments
FORCE=false
LIST_ONLY=false
KEEP_VM=false
INNER_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)  FORCE=true; INNER_ARGS+=("--force"); shift ;;
        --list)   LIST_ONLY=true; INNER_ARGS+=("--list"); shift ;;
        --keep)   KEEP_VM=true; shift ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --force   Fresh VM and re-run all steps"
            echo "  --list    List all steps without running"
            echo "  --keep    Keep VM running after tests (default: stop)"
            echo "  --help    Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check prerequisites
check_prereqs() {
    local missing=()
    
    command -v virsh &>/dev/null || missing+=("libvirt (virsh)")
    command -v virt-install &>/dev/null || missing+=("virt-install")
    command -v cloud-localds &>/dev/null || missing+=("cloud-image-utils (cloud-localds)")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing prerequisites: ${missing[*]}"
        echo ""
        echo "Install with:"
        echo "  sudo apt-get install -y libvirt-daemon-system virtinst cloud-image-utils"
        echo "  sudo usermod -aG libvirt \$USER"
        echo "  # Log out and back in for group membership"
        exit 1
    fi
}

# Check if VM exists
vm_exists() {
    $VIRSH list --all --name 2>/dev/null | grep -q "^${VM_NAME}$"
}

# Check if VM is running
vm_running() {
    $VIRSH list --name 2>/dev/null | grep -q "^${VM_NAME}$"
}

# Wait for VM to be accessible via SSH port forwarding
wait_for_vm() {
    log_info "Waiting for VM to be accessible on localhost:$VM_SSH_PORT..."
    
    local attempts=60
    while [[ $attempts -gt 0 ]]; do
        if ssh -q $SSH_OPTS -o ConnectTimeout=2 -p "$VM_SSH_PORT" ubuntu@localhost true 2>/dev/null; then
            log_success "VM accessible at localhost:$VM_SSH_PORT"
            return 0
        fi
        
        sleep 5
        ((attempts--))
    done
    
    log_error "Timeout waiting for VM"
    return 1
}

# Download base image
download_image() {
    if [[ -f "$VM_IMAGE" ]]; then
        log_info "Using cached Ubuntu image"
        return 0
    fi
    
    log_info "Downloading Ubuntu 25.10 cloud image..."
    mkdir -p "$VM_IMAGE_DIR"
    wget -q --show-progress -O "$VM_IMAGE" "$VM_IMAGE_URL"
    log_success "Image downloaded"
}

# Create cloud-init config
create_cloud_init() {
    local ssh_key
    
    # Use existing SSH key or generate one
    if [[ -f "$HOME/.ssh/id_rsa.pub" ]]; then
        ssh_key=$(cat "$HOME/.ssh/id_rsa.pub")
    elif [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
        ssh_key=$(cat "$HOME/.ssh/id_ed25519.pub")
    else
        log_info "Generating SSH key..."
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
    
    # Create the cloud-init disk
    cloud-localds "$VM_CLOUD_INIT_DIR/cloud-init.img" "$VM_CLOUD_INIT_DIR/user-data.yaml"
}

# Create VM
create_vm() {
    log_info "Creating VM: $VM_NAME"
    
    download_image
    create_cloud_init
    
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
    
    log_success "VM created"
}

# Destroy VM
destroy_vm() {
    if vm_exists; then
        log_info "Destroying VM: $VM_NAME"
        $VIRSH destroy "$VM_NAME" 2>/dev/null || true
        $VIRSH undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
        rm -f "$VM_DISK"
        log_success "VM destroyed"
    fi
}

# Run test in VM
run_test() {
    log_info "Copying local repository to VM..."
    rsync -az -e "ssh $SSH_OPTS -p $VM_SSH_PORT" \
        --exclude='.git' \
        --exclude='artifacts' \
        "$REPO_ROOT/" ubuntu@localhost:~/android-nativeaot/

    log_info "Running docs in VM..."
    ssh $SSH_OPTS -p "$VM_SSH_PORT" ubuntu@localhost \
        "cd ~/android-nativeaot && chmod +x test/*.sh && ./test/run-docs.sh ${INNER_ARGS[*]:-}"
}

# Main
main() {
    check_prereqs
    
    # List mode - just show steps and exit
    if [[ "$LIST_ONLY" == "true" ]]; then
        "$SCRIPT_DIR/run-docs.sh" --list
        exit 0
    fi
    
    # Force mode - destroy existing VM
    if [[ "$FORCE" == "true" ]]; then
        destroy_vm
    fi
    
    # Create VM if needed, otherwise reuse
    if ! vm_exists; then
        create_vm
    elif ! vm_running; then
        log_info "Starting existing VM..."
        $VIRSH start "$VM_NAME"
    else
        log_info "Reusing running VM..."
    fi
    
    # Wait for VM and run test
    wait_for_vm
    
    TEST_START=$(date +%s)
    
    if run_test; then
        TEST_END=$(date +%s)
        log_success "All tests passed! ($((TEST_END - TEST_START))s)"
        if [[ "$KEEP_VM" == "true" ]]; then
            log_info "VM kept running. SSH: ssh -p $VM_SSH_PORT ubuntu@localhost"
        else
            log_info "Stopping VM..."
            $VIRSH shutdown "$VM_NAME" 2>/dev/null || true
            log_info "VM stopped. Disk preserved for fast restart."
        fi
        exit 0
    else
        log_error "Tests failed!"
        log_info "VM kept for debugging. SSH: ssh -p $VM_SSH_PORT ubuntu@localhost"
        exit 1
    fi
}

main "$@"
