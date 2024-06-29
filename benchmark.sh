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

# Fly commands
FLY_CMD=fly

# FLy machine sizing
VM_SIZE="shared-cpu-4x"
VM_MEMORY="2048"
VOLUME_SIZE="1"
VOLUME_NAME="warp_app_vol"

# Master node related
MASTER_REGION="iad"
MASTER_VM_SIZE="shared-cpu-4x"
MASTER_VM_MEMORY="8192"

# Node name related
MASTER_NODE="warp-node-master"
WORKER_NODE_PREFIX="warp-node-worker-"

# The number of nodes to create per region
NUM_NODES=2

# The workload parameters
REGIONS="iad,ord,sjc"
CONCURRENCY=10
DURATION=1m
OBJECT_SIZE=4KB
BUCKET="test-bucket"
S3_ENDPOINT="idev-storage.fly.tigris.dev"
INSECURE="false"
RANDOMIZE_OBJECT_SIZE="false"
RANGE_REQUESTS="false"
ACCESS_KEY=""
SECRET_KEY=""
WORKLOAD_TYPE="get"

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

Usage: $(basename "$0") [-r|-n|-c|-o|-e|-a|-p|-b|-d|-s|-h]
r             - regions to run the benchmark in (default: $REGIONS)
n             - number of warp client nodes per region to run the benchmark (default: $NUM_NODES)
c             - per warp client concurrency (default: $CONCURRENCY)
o             - objects size (default: $OBJECT_SIZE)
e             - S3 endpoint to use (default: $S3_ENDPOINT)
a             - S3 access key
p             - S3 secret key
b             - S3 bucket to use (default: $BUCKET)
d             - duration of the benchmark (default: $DURATION)
t             - type of workload to run (get|mixed|list|stat default: $WORKLOAD_TYPE)
i             - use insecure connections to the S3 endpoint (default: $INSECURE)
f             - randomize size of objects up to a max defined by [-o] (default: $RANDOMIZE_OBJECT_SIZE)
g             - use range requests (default: $RANGE_REQUESTS)
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
    local region="$1"
    local volume_info=

    volume_info=$($FLY_CMD volumes create "$VOLUME_NAME" --region "$region" --size "$VOLUME_SIZE" --yes -j)

    if [[ $(echo "$volume_info" | jq .id -r) != "vol_"* ]]; then
        fatal "Failed to create volume"
    fi

    if [[ $(echo "$volume_info" | jq .zone -r) == "null" ]]; then
        fatal "Failed to fetch zone info for volume"
    fi

    # return the volume id and zone
    echo "$volume_info"
}

create_machine() {
    local node_name="$1"
    local region="$2"
    local vm_size="$3"
    local vm_memory="$4"

    info "Checking if node exists... (name: $node_name, vm-size: $VM_SIZE)"
    # check if worker node already exists
    if [[ $($FLY_CMD machine list -j | jq '.[] | select(.name=="'"$node_name"'") | .name' -r 2>/dev/null) == "$node_name" ]]; then
        return
    fi

    # create volume
    info "Creating volume... (name: $VOLUME_NAME, region: $region, size: $VOLUME_SIZE)"
    local volume_info='' volume_id='' volume_zone=''

    volume_info=$(create_volume "$region")
    volume_id=$(echo "$volume_info" | jq .id -r)
    volume_zone=$(echo "$volume_info" | jq .zone -r)

    info "Creating node... (name: $node_name, vm-size: $VM_SIZE, zone: $volume_zone)"
    $FLY_CMD machine run . \
        --name "$node_name" \
        --vm-size "$vm_size" \
        --vm-memory "$vm_memory" \
        --region "$region" \
        --volume "$volume_id:/data"
}

# --- add nodes ---
create_all_machines() {
    # create the master node
    create_machine "${MASTER_NODE}" "$MASTER_REGION" "$MASTER_VM_SIZE" "$MASTER_VM_MEMORY"

    # create the worker nodes
    local regions=
    IFS=',' read -r -a regions <<<"$REGIONS"
    for region in "${regions[@]}"; do
        for ((i = 0; i < NUM_NODES; i++)); do
            local node_name="${WORKER_NODE_PREFIX}${region}-${i}"

            create_machine "$node_name" "$region" "$VM_SIZE" "$VM_MEMORY"
        done
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
        $FLY_CMD volume destroy "$v" -y
    done
}

# --- run workload ---
run_workload() {
    local client_nodes='' master_node_id=''

    master_node_id=$(fetch_instance_id "${MASTER_NODE}")
    client_nodes=$(fly machines list -j | jq '[.[] | select(.name != "'${MASTER_NODE}'" ) | (.id + ".vm.'${FLY_APP_NAME}'.internal")] | join(",")' -r)

    # fetch the access key and secret key
    if [[ -z "$ACCESS_KEY" || -z "$SECRET_KEY" ]]; then
        eval "$(fly machine exec $master_node_id 'env' | grep -E 'ACCESS_KEY|SECRET_KEY')"
    fi

    local tls_arg=''
    if [[ "$INSECURE" == "false" ]]; then
        tls_arg="--tls"
    fi

    local obj_rand_size_arg=''
    if [[ "$RANDOMIZE_OBJECT_SIZE" == "true" ]]; then
        obj_rand_size_arg="--obj.randsize"
    fi

    local obj_range_get_arg=''
    if [[ "$RANGE_REQUESTS" == "true" ]]; then
        obj_range_get_arg="--range"
    fi

    info "Running workload (endpoint: $S3_ENDPOINT, bucket: $BUCKET, max object_size: $OBJECT_SIZE, duration: $DURATION, concurrency: $CONCURRENCY)..."

    $FLY_CMD ssh console \
        -A "$master_node_id.vm.$FLY_APP_NAME.internal" \
        -C "/warp $WORKLOAD_TYPE --warp-client=$client_nodes --analyze.v --host=$S3_ENDPOINT --access-key=$ACCESS_KEY --secret-key=$SECRET_KEY --bucket=$BUCKET $tls_arg --obj.size=$OBJECT_SIZE $obj_rand_size_arg $obj_range_get_arg --duration=$DURATION --concurrent=$CONCURRENCY"
}

# --- main ---
while getopts "r:n:c:o:e:a:p:b:d:t:ifgsh" opt; do
    case "$opt" in
    r)
        REGIONS="$OPTARG"
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
    a)
        ACCESS_KEY="$OPTARG"
        ;;
    p)
        SECRET_KEY="$OPTARG"
        ;;
    b)
        BUCKET="$OPTARG"
        ;;
    d)
        DURATION="$OPTARG"
        ;;
    t)
        WORKLOAD_TYPE="$OPTARG"
        ;;
    i)
        INSECURE="true"
        ;;
    f)
        RANDOMIZE_OBJECT_SIZE="true"
        ;;
    g)
        RANGE_REQUESTS="true"
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

create_all_machines
run_workload
