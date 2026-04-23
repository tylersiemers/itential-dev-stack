#!/bin/bash
# Seeds NetBox with 25 devices (10 servers, 10 switches, 5 routers)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/defaults.env"
[ -f "$PROJECT_ROOT/.env" ] && source "$PROJECT_ROOT/.env"

NETBOX_URL="http://localhost:${NETBOX_PORT:-8002}"
TOKEN="${NETBOX_API_TOKEN:-0123456789abcdef0123456789abcdef01234567}"

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

log_section "prerequisites"

SITE_ID=$(get_id "dcim/sites" "slug=local-lab")
if [ -z "$SITE_ID" ]; then
    SITE_ID=$(api_post "dcim/sites" '{"name":"Local Lab","slug":"local-lab","status":"active"}' | jq -r '.id')
    log_info "Created site: Local Lab (id=$SITE_ID)"
else
    log_info "Site exists (id=$SITE_ID)"
fi

MFR_ID=$(get_id "dcim/manufacturers" "slug=generic")
if [ -z "$MFR_ID" ]; then
    MFR_ID=$(api_post "dcim/manufacturers" '{"name":"Generic","slug":"generic"}' | jq -r '.id')
    log_info "Created manufacturer: Generic (id=$MFR_ID)"
else
    log_info "Manufacturer exists (id=$MFR_ID)"
fi

DT_ID=$(get_id "dcim/device-types" "slug=generic-device")
if [ -z "$DT_ID" ]; then
    DT_ID=$(api_post "dcim/device-types" "{\"model\":\"Generic Device\",\"slug\":\"generic-device\",\"manufacturer\":$MFR_ID}" | jq -r '.id')
    log_info "Created device type (id=$DT_ID)"
else
    log_info "Device type exists (id=$DT_ID)"
fi

make_role() {
    local name=$1 slug=$2 color=$3
    local id
    id=$(get_id "dcim/device-roles" "slug=$slug")
    if [ -z "$id" ]; then
        id=$(api_post "dcim/device-roles" "{\"name\":\"$name\",\"slug\":\"$slug\",\"color\":\"$color\"}" | jq -r '.id')
        echo -e "${GREEN}[INFO]${NC} Created role: $name (id=$id)" >&2
    else
        echo -e "${GREEN}[INFO]${NC} Role exists: $name (id=$id)" >&2
    fi
    echo "$id"
}

SERVER_ROLE=$(make_role "Server" "server" "0000ff")
SWITCH_ROLE=$(make_role "Switch" "switch" "00aa00")
ROUTER_ROLE=$(make_role "Router" "router" "aa0000")

log_section "creating devices"

make_device() {
    local name=$1 role=$2
    if [ -z "$(get_id "dcim/devices" "name=$name")" ]; then
        api_post "dcim/devices" "{\"name\":\"$name\",\"device_type\":$DT_ID,\"role\":$role,\"site\":$SITE_ID,\"status\":\"active\"}" > /dev/null
        log_info "Created $name"
    else
        log_info "$name already exists"
    fi
}

for i in $(seq -f "%02g" 1 10); do make_device "server-$i" "$SERVER_ROLE"; done
for i in $(seq -f "%02g" 1 10); do make_device "switch-$i" "$SWITCH_ROLE"; done
for i in $(seq -f "%02g" 1 5);  do make_device "router-$i" "$ROUTER_ROLE"; done

log_info "Done — 25 devices seeded"
