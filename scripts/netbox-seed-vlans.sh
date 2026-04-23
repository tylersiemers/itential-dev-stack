#!/bin/bash
# Seeds NetBox with 10 VLANs

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
    local endpoint=$1 payload=$2
    local response http_code body
    response=$(curl -s -w "\n__HTTP_CODE__%{http_code}" -X POST \
        -H "Authorization: Token $TOKEN" \
        -H "Content-Type: application/json" \
        "$NETBOX_URL/api/$endpoint/" -d "$payload")
    http_code=$(echo "$response" | grep '__HTTP_CODE__' | sed 's/__HTTP_CODE__//')
    body=$(echo "$response" | sed '/__HTTP_CODE__/d')
    if [[ ! "$http_code" =~ ^2 ]]; then
        echo -e "\033[0;31m[ERROR]\033[0m POST $endpoint HTTP $http_code: $body" >&2
        return 1
    fi
    echo "$body"
}

get_id() {
    curl -s -H "Authorization: Token $TOKEN" \
        "$NETBOX_URL/api/$1/?$2" | jq -r '.results[0].id // empty'
}

log_section "creating vlans"

VLANS=(
    "10:Management"
    "20:Data"
    "30:Voice"
    "40:Guest"
    "50:DMZ"
    "60:Storage"
    "70:Backup"
    "80:Monitoring"
    "90:Development"
    "100:Production"
)

for entry in "${VLANS[@]}"; do
    VID="${entry%%:*}"
    NAME="${entry##*:}"
    if [ -z "$(get_id "ipam/vlans" "vid=$VID")" ]; then
        api_post "ipam/vlans" "{\"name\":\"$NAME\",\"vid\":$VID,\"status\":\"active\"}" > /dev/null
        log_info "Created VLAN $VID: $NAME"
    else
        log_info "VLAN $VID already exists"
    fi
done

log_info "Done — 10 VLANs seeded"
