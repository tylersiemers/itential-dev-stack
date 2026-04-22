#!/bin/bash
# Assigns a management IP to each of the 25 seeded devices
# servers:  10.0.10.1-10/24
# switches: 10.0.20.1-10/24
# routers:  10.0.30.1-5/24

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/defaults.env"
[ -f "$PROJECT_ROOT/.env" ] && source "$PROJECT_ROOT/.env"

NETBOX_URL="http://localhost:${NETBOX_PORT:-8002}"
TOKEN="0123456789abcdef0123456789abcdef01234567"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_section() { echo -e "\n${BLUE}--- $1 ---${NC}"; }

api_post() {
    curl -sf -X POST \
        -H "Authorization: Token $TOKEN" \
        -H "Content-Type: application/json" \
        "$NETBOX_URL/api/$1/" -d "$2"
}

api_patch() {
    curl -sf -X PATCH \
        -H "Authorization: Token $TOKEN" \
        -H "Content-Type: application/json" \
        "$NETBOX_URL/api/$1/$2/" -d "$3"
}

get_id() {
    curl -sf -H "Authorization: Token $TOKEN" \
        "$NETBOX_URL/api/$1/?$2" | jq -r '.results[0].id // empty'
}

assign_ip() {
    local device_name=$1 ip_addr=$2

    local device_id=$(get_id "dcim/devices" "name=$device_name")
    if [ -z "$device_id" ]; then
        echo "  skipping $device_name (not found)"
        return
    fi

    # create mgmt0 interface if needed
    local iface_id=$(get_id "dcim/interfaces" "device_id=$device_id&name=mgmt0")
    if [ -z "$iface_id" ]; then
        iface_id=$(api_post "dcim/interfaces" \
            "{\"device\":$device_id,\"name\":\"mgmt0\",\"type\":\"1000base-t\"}" | jq -r '.id')
    fi

    # create IP and assign to interface
    local ip_id
    ip_id=$(api_post "ipam/ip-addresses" \
        "{\"address\":\"$ip_addr\",\"status\":\"active\",\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$iface_id}" \
        2>/dev/null | jq -r '.id // empty') || true

    # if already exists, look it up
    if [ -z "$ip_id" ]; then
        local encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$ip_addr'))" 2>/dev/null || echo "$ip_addr")
        ip_id=$(curl -sf -H "Authorization: Token $TOKEN" \
            "$NETBOX_URL/api/ipam/ip-addresses/?address=$encoded" | jq -r '.results[0].id // empty')
    fi

    [ -z "$ip_id" ] && echo "  could not create/find IP $ip_addr, skipping" && return

    # set as primary IPv4 on device
    api_patch "dcim/devices" "$device_id" "{\"primary_ip4\":$ip_id}" > /dev/null
    log_info "$device_name → $ip_addr"
}

log_section "servers (10.0.10.x)"
for i in $(seq 1 10); do assign_ip "server-$(printf '%02d' $i)" "10.0.10.$i/24"; done

log_section "switches (10.0.20.x)"
for i in $(seq 1 10); do assign_ip "switch-$(printf '%02d' $i)" "10.0.20.$i/24"; done

log_section "routers (10.0.30.x)"
for i in $(seq 1 5); do assign_ip "router-$(printf '%02d' $i)" "10.0.30.$i/24"; done

log_info "Done — IPs assigned to all 25 devices"
