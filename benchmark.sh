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

# The number of nodes to create
NUM_NODES=3

# The workload parameters
REGION="iad"
CONCURRENCY=10
DURATION=1m
OBJECT_SIZE=4KB
BUCKET="test-bucket"
S3_ENDPOINT="dev-tigris-os.fly.dev"

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
o             - object size to use (default: $OBJECT_SIZE)
e             - s3 endpoint to use (default: $S3_ENDPOINT)
d             - duration of the benchmark (default: $DURATION)
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

        info "Creating node... (name: $node_name, vm-size: $VM_SIZE)"
        $FLY_CMD machine run . \
            --name "$node_name" \
            --vm-size "$VM_SIZE" \
            --vm-memory "$VM_MEMORY" \
            --region "$REGION"
    done
}

# --- destroy nodes ---
destroy_machines() {
    for m in $($FLY_CMD machine list -j | jq '.[] | .id' -r); do
        info "Destroying node... (name: $m)"
        $FLY_CMD machine rm "$m" --force
    done
}

# --- run workload ---
run_workload() {
    local client_nodes='' master_node_id=''

    master_node_id=$(fetch_instance_id "${NODE_PREFIX}0")
    client_nodes=$(fly machines list -j | jq '[.[] | select(.name != "'${NODE_PREFIX}0'" ) | (.id + ".vm.'${FLY_APP_NAME}'.internal")] | join(",")' -r)

    # fetch the access key and secret key
    eval "$(fly machine exec $master_node_id 'env' | grep -E 'TIGRIS_ACCESS_KEY_ID|TIGRIS_SECRET_ACCESS_KEY')"

    info "Running workload (endpoint: $S3_ENDPOINT, bucket: $BUCKET, object_size: $OBJECT_SIZE, duration: $DURATION, concurrency: $CONCURRENCY)..."

    $FLY_CMD ssh console \
        -A "$master_node_id.vm.$FLY_APP_NAME.internal" \
        -C "/warp get --warp-client=$client_nodes --analyze.v --host=$S3_ENDPOINT --access-key=$TIGRIS_ACCESS_KEY_ID --secret-key=$TIGRIS_SECRET_ACCESS_KEY --bucket=$BUCKET --tls --obj.size=$OBJECT_SIZE --duration=$DURATION --concurrent=$CONCURRENCY"
}

# --- main ---
while getopts "r:n:c:o:e:d:sh" opt; do
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
