#!/usr/bin/env bash

set -euo pipefail

info() {
    echo '[INFO] ' "$@"
}

warn() {
    echo '[WARN] ' "$@" >&2
}

fatal() {
    echo '[ERROR] ' "$@" >&2
    exit 1
}

# The name of the fly app
FLY_APP_NAME="warp-app"

# The name prefixes of the nodes
NODE_PREFIX="warp-node-"

# Fly commands
FLY_CMD=fly

# FLy machine sizing
VM_SIZE="shared-cpu-4x"
VM_MEMORY="2048"
VOLUME_SIZE="1"
VOLUME_NAME="warp_app_vol"

# The number of nodes to create
NUM_NODES=5

# The workload parameters
REGION="iad"
CONCURRENCY=10
DURATION=1m
OBJECT_SIZE=4KB
BUCKET="test-bucket"
S3_ENDPOINT="dev-tigris-os.fly.dev"
INSECURE="false"
RANDOMIZE_OBJECT_SIZE="false"

# check for required binaries
for prog in $FLY_CMD jq openssl; do
    command -v "$prog" >/dev/null 2>&1 || {
        echo >&2 "I require $prog but it's not installed.  Aborting."
        exit 1
    }
done

# --- usage info ---
usage() {
    cat <<EOF
A utility to run S3 benchmarks on Fly.io

Usage: $(basename "$0") [-r|-n|-c|-o|-e|-d|-s|-h]
r             - region to run the benchmark in (default: $REGION)
n             - number of warp client nodes to use to run the benchmark (default: $NUM_NODES)
c             - per warp client concurrency (default: $CONCURRENCY)
o             - objects size (default: $OBJECT_SIZE)
e             - s3 endpoint to use (default: $S3_ENDPOINT)
d             - duration of the benchmark (default: $DURATION)
i             - use insecure connections to the s3 endpoint (default: $INSECURE)
f             - randomize size of objects up to a max defined by [-o] (default: $RANDOMIZE_OBJECT_SIZE)
s             - shutdown the warp nodes
h             - help
EOF
}

# --- fetches the instance id of a node ---
fetch_instance_id() {
    local node_name="$1"
    local node_id=

    node_id=$($FLY_CMD machine list -j | jq '.[] | select(.name=="'$node_name'") | .id' -r)
    if [[ -z "$node_id" ]]; then
        fatal "Node not found"
    fi

    # return the node_id
    echo "$node_id"
}

# --- creates the volume ---
create_volume() {
    local volume_info=

    volume_info=$($FLY_CMD volumes create "$VOLUME_NAME" --region "$REGION" --size "$VOLUME_SIZE" --yes -j)

    if [[ $(echo "$volume_info" | jq .id -r) != "vol_"* ]]; then
        fatal "Failed to create volume"
    fi

    if [[ $(echo "$volume_info" | jq .zone -r) == "null" ]]; then
        fatal "Failed to fetch zone info for volume"
    fi

    # return the volume id and zone
    echo "$volume_info"
}

# --- add nodes ---
create_machines() {
    NODE_PREFIX="${NODE_PREFIX}${REGION}-"

    # create the nodes
    for ((i = 0; i < NUM_NODES; i++)); do
        local node_name="${NODE_PREFIX}${i}"

        info "Checking if node exists... (name: $node_name, vm-size: $VM_SIZE)"
        # check if worker node already exists
        if [[ $($FLY_CMD machine list -j | jq '.[] | select(.name=="'"$node_name"'") | .name' -r 2>/dev/null) == "$node_name" ]]; then
            continue
        fi

        # create volume
        info "Creating volume... (name: $VOLUME_NAME, region: $REGION, size: $VOLUME_SIZE)"
        local volume_info='' volume_id='' volume_zone=''

        volume_info=$(create_volume)
        volume_id=$(echo "$volume_info" | jq .id -r)
        volume_zone=$(echo "$volume_info" | jq .zone -r)

        info "Creating node... (name: $node_name, vm-size: $VM_SIZE, zone: $volume_zone)"
        $FLY_CMD machine run . \
            --name "$node_name" \
            --vm-size "$VM_SIZE" \
            --vm-memory "$VM_MEMORY" \
            --region "$REGION" \
            --volume "$volume_id:/data"
    done
}

# --- destroy nodes ---
destroy_machines() {
    for m in $($FLY_CMD machine list -j | jq '.[] | .id' -r); do
        info "Destroying node... (name: $m)"
        $FLY_CMD machine rm "$m" --force
    done

    for v in $($FLY_CMD volumes list -j | jq '.[] | .id' -r); do
        info "Destroying volume... (name: $v)"
        $FLY_CMD volume destroy "$v" --force
    done
}

# --- run workload ---
run_workload() {
    local client_nodes='' master_node_id=''

    master_node_id=$(fetch_instance_id "${NODE_PREFIX}0")
    client_nodes=$(fly machines list -j | jq '[.[] | select(.name != "'${NODE_PREFIX}0'" ) | (.id + ".vm.'${FLY_APP_NAME}'.internal")] | join(",")' -r)

    # fetch the access key and secret key
    eval "$(fly machine exec $master_node_id 'env' | grep -E 'TIGRIS_ACCESS_KEY_ID|TIGRIS_SECRET_ACCESS_KEY')"

    local tls_arg=''
    if [[ "$INSECURE" == "false" ]]; then
        tls_arg="--tls"
    fi

    local obj_rand_size_arg=''
    if [[ "$RANDOMIZE_OBJECT_SIZE" == "true" ]]; then
        obj_rand_size_arg="--obj.randsize"
    fi

    info "Running workload (endpoint: $S3_ENDPOINT, bucket: $BUCKET, max object_size: $OBJECT_SIZE, duration: $DURATION, concurrency: $CONCURRENCY)..."

    $FLY_CMD ssh console \
        -A "$master_node_id.vm.$FLY_APP_NAME.internal" \
        -C "/warp get --warp-client=$client_nodes --analyze.v --host=$S3_ENDPOINT --access-key=$TIGRIS_ACCESS_KEY_ID --secret-key=$TIGRIS_SECRET_ACCESS_KEY --bucket=$BUCKET $tls_arg --obj.size=$OBJECT_SIZE $obj_rand_size_arg --duration=$DURATION --concurrent=$CONCURRENCY"
}

# --- main ---
while getopts "r:n:c:o:e:d:ifsh" opt; do
    case "$opt" in
    r)
        REGION="$OPTARG"
        ;;
    n)
        NUM_NODES="$OPTARG"
        ;;
    c)
        CONCURRENCY="$OPTARG"
        ;;
    o)
        OBJECT_SIZE="$OPTARG"
        ;;
    e)
        S3_ENDPOINT="$OPTARG"
        ;;
    d)
        DURATION="$OPTARG"
        ;;
    i)
        INSECURE="true"
        ;;
    f)
        RANDOMIZE_OBJECT_SIZE="true"
        ;;
    s)
        destroy_machines
        exit 0
        ;;
    h)
        usage
        exit 0
        ;;
    *)
        usage
        exit 1
        ;;
    esac
done

create_machines
run_workload
