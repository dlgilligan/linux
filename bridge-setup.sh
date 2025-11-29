#!/bin/bash

# Bridge setup script for Debian 12
# Usage: ./bridge-setup.sh [up|down|status]

INTERFACE="enp4s0"
BRIDGE="br0"
BACKUP_DIR="/etc/network/backup"
INTERFACES_FILE="/etc/network/interfaces"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
}

backup_network_config() {
    log "Backing up network configuration..."
    mkdir -p "$BACKUP_DIR"
    
    # Backup interfaces file
    if [[ -f "$INTERFACES_FILE" ]]; then
        cp "$INTERFACES_FILE" "$BACKUP_DIR/interfaces.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Backup current IP configuration
    ip addr show "$INTERFACE" > "$BACKUP_DIR/interface_config.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    ip route show > "$BACKUP_DIR/routes.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
}

restore_network_config() {
    log "Restoring network configuration..."
    
    # Find most recent backup
    local latest_backup=$(ls -t "$BACKUP_DIR"/interfaces.backup.* 2>/dev/null | head -n1)
    
    if [[ -n "$latest_backup" && -f "$latest_backup" ]]; then
        cp "$latest_backup" "$INTERFACES_FILE"
        log "Restored interfaces file from backup"
    else
        warn "No backup found, creating minimal configuration"
        create_default_config
    fi
}

create_default_config() {
    cat > "$INTERFACES_FILE" << EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto $INTERFACE
iface $INTERFACE inet dhcp
EOF
}

stop_network_manager() {
    # Stop NetworkManager if running (it can interfere)
    if systemctl is-active --quiet NetworkManager; then
        log "Stopping NetworkManager to prevent interference"
        systemctl stop NetworkManager
    fi
}

start_network_manager() {
    # Restart NetworkManager if it was running
    if systemctl is-enabled --quiet NetworkManager; then
        log "Restarting NetworkManager"
        systemctl start NetworkManager
    fi
}

setup_bridge() {
    log "Setting up bridge configuration..."
    
    backup_network_config
    stop_network_manager
    
    # Get current IP configuration before making changes
    local current_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || echo "")
    local current_gateway=$(ip route show default | grep -oP 'via \K\S+' | head -n1 || echo "")
    
    if [[ -z "$current_ip" ]]; then
        error "Could not determine current IP address"
        return 1
    fi
    
    log "Current IP: $current_ip, Gateway: $current_gateway"
    
    # Create persistent bridge configuration
    cat > "$INTERFACES_FILE" << EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# Bridge interface
auto $BRIDGE
iface $BRIDGE inet dhcp
bridge_ports $INTERFACE
bridge_stp off
bridge_fd 0
bridge_maxwait 0

# Physical interface (no IP, part of bridge)
auto $INTERFACE
iface $INTERFACE inet manual
EOF

    # Apply configuration using ifupdown
    log "Applying network configuration..."
    
    # Take down the physical interface
    log "Taking down physical interface..."
    ifdown "$INTERFACE" 2>/dev/null || true
    ip link set "$INTERFACE" down 2>/dev/null || true
    
    # Remove any IP addresses from physical interface
    ip addr flush dev "$INTERFACE" 2>/dev/null || true
    
    # Stop DHCP client on physical interface
    pkill -f "dhclient.*$INTERFACE" 2>/dev/null || true
    
    # Create bridge if it doesn't exist
    if ! ip link show "$BRIDGE" &>/dev/null; then
        log "Creating bridge $BRIDGE..."
        ip link add name "$BRIDGE" type bridge
    fi
    
    # Configure bridge
    ip link set "$BRIDGE" type bridge stp_state 0
    
    # Add physical interface to bridge
    log "Adding $INTERFACE to bridge $BRIDGE..."
    ip link set "$INTERFACE" master "$BRIDGE"
    
    # Bring interfaces up
    log "Bringing up interfaces..."
    ip link set "$INTERFACE" up
    ip link set "$BRIDGE" up
    
    # Wait a moment for link to stabilize
    sleep 2
    
    # Start DHCP on bridge
    log "Starting DHCP client on bridge..."
    dhclient "$BRIDGE" &
    
    # Wait for IP assignment
    log "Waiting for IP assignment..."
    local timeout=30
    local count=0
    while [[ $count -lt $timeout ]]; do
        if ip addr show "$BRIDGE" | grep -q "inet.*scope global"; then
            local bridge_ip=$(ip addr show "$BRIDGE" | grep -oP 'inet \K[0-9.]+')
            log "Bridge $BRIDGE got IP address: $bridge_ip"
            break
        fi
        sleep 1
        ((count++))
    done
    
    if [[ $count -eq $timeout ]]; then
        error "Timeout waiting for IP assignment on bridge"
        return 1
    fi
    
    log "Bridge setup completed successfully"
    return 0
}

teardown_bridge() {
    log "Tearing down bridge configuration..."
    
    stop_network_manager
    
    # Kill DHCP client on bridge
    pkill -f "dhclient.*$BRIDGE" 2>/dev/null || true
    
    # Remove interface from bridge
    if ip link show "$BRIDGE" &>/dev/null; then
        log "Removing $INTERFACE from bridge..."
        ip link set "$INTERFACE" nomaster 2>/dev/null || true
        
        # Take down bridge
        log "Taking down bridge $BRIDGE..."
        ip link set "$BRIDGE" down 2>/dev/null || true
        ip link delete "$BRIDGE" 2>/dev/null || true
    fi
    
    # Restore network configuration
    restore_network_config
    
    # Restart networking
    log "Restarting networking..."
    systemctl restart networking
    
    # Wait for interface to come up
    sleep 5
    
    # If interface doesn't have IP, try DHCP
    if ! ip addr show "$INTERFACE" | grep -q "inet.*scope global"; then
        log "Interface has no IP, starting DHCP..."
        dhclient "$INTERFACE" &
        sleep 5
    fi
    
    start_network_manager
    
    log "Bridge teardown completed"
}

show_status() {
    echo "=== Network Status ==="
    echo
    echo "Interfaces:"
    ip link show | grep -E "^[0-9]+:|state"
    echo
    echo "IP Addresses:"
    ip addr show | grep -E "^[0-9]+:|inet "
    echo
    echo "Routes:"
    ip route show
    echo
    echo "Bridge status:"
    if ip link show "$BRIDGE" &>/dev/null; then
        echo "Bridge $BRIDGE exists"
        if [[ -d "/sys/class/net/$BRIDGE/brif" ]]; then
            echo "Bridge ports:"
            ls "/sys/class/net/$BRIDGE/brif/" 2>/dev/null || echo "No ports"
        fi
    else
        echo "Bridge $BRIDGE does not exist"
    fi
}

main() {
    check_root
    
    case "${1:-up}" in
        up|setup)
            setup_bridge
            ;;
        down|teardown)
            teardown_bridge
            ;;
        status)
            show_status
            ;;
        *)
            echo "Usage: $0 [up|down|status]"
            echo "  up/setup    - Set up bridge configuration"
            echo "  down/teardown - Remove bridge and restore original config"
            echo "  status      - Show current network status"
            exit 1
            ;;
    esac
}

main "$@"
