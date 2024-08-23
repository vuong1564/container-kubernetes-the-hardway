#!/usr/bin/env bash

set -euo pipefail

REGISTRY_ENDPOINT="https://registry.hub.docker.com"
TOY_BASE_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEFAULT_IMAGE_STORE="${TOY_BASE_DIR}/image-store"
DEFAULT_CONTAINER_DIR="${TOY_BASE_DIR}/containers"
IP_TRACKING_FILE="${TOY_BASE_DIR}/ips.txt"

DEFAULT_CONTAINER_CMD_FILE="cmd"
DEFAULT_CONTAINER_IMAGE_INFO_FILE="image"
DEFAULT_CONTAINER_OVERLAY_DIR="merged"
DEFAULT_CONTAINER_DIFF_DIR="diff"
DEFAULT_CONTAINER_WORK_DIR="work"
DEFAULT_CONTAINER_INIT_DIR="init"
DEFAULT_CGROUPS_CONTROLLER="memory,cpu"
DEFAULT_CONTAINER_MEMORY_LIMIT_MB="256"

# https://stackoverflow.com/questions/10768160/ip-address-converter
function dec2ip() { # dec2ip <base_10_ip_address>
    local ip dec delim=
    dec=$1
    for e in {3..0}
    do
        ((octet = dec / (256 ** e) ))
        ((dec -= octet * 256 ** e))
        ip+=$delim$octet
        delim=.
    done
    printf '%s\n' "$ip"
}

ip2dec () { # ip2dec <ip_address_str>
    local a b c d ip=$1
    IFS=. read -r a b c d <<< "$ip"
    printf '%d\n' "$((a * 256 ** 3 + b * 256 ** 2 + c * 256 + d))"
}

DEFAULT_CONTAINER_CIDR_NETWORK="10.33.16.0"
DEFAULT_CONTAINER_CIDR_MASK="20"
DEFAULT_BRIDGE_NAME="devops0"
DEFAULT_CONTAINER_GATEWAY_IP=$(dec2ip $(($(ip2dec $DEFAULT_CONTAINER_CIDR_NETWORK)+1)))
CONTAINER_FIRST_IP=$(dec2ip $(($(ip2dec $DEFAULT_CONTAINER_CIDR_NETWORK)+10)))


# Get bearer token
# https://docs.docker.com/registry/spec/auth/token/
function get_bearer_token() { # xxx get_bearer_token <name> <tag>
    local www_authenticate auth_server service scope token
    www_authenticate=$(curl -Ss -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    -si "${REGISTRY_ENDPOINT}/v2/$1/manifests/$2" | grep -i "www-authenticate" | tr -d '"\r')
    auth_server=$(sed -E "s/www-authenticate: Bearer realm=(https?:[a-z\/\.]*).*$/\1/" <<< "$www_authenticate")
    service=$(sed -E "s/.*,service=([a-z\.\/]*).+/\1/" <<< "$www_authenticate")
    scope=$(sed -E "s/.*,scope=([a-z\.\/:]*),*/\1/" <<< "$www_authenticate")

    token=$(curl -s "${auth_server}?service=${service}&scope=${scope}" | jq -r .token)

    [[ -z $token ]] && echo "can not request token" && exit 1

    echo "$token"
}

# TODO: check size
function download_blob() { # xxx download_blob <path> <token> <filename>
    local path token filename dir
    path="$1"
    token="$2"
    filename="$3"
    dir=$(dirname "$filename")

    if [[ ! -d $dir ]]
    then
        mkdir -p "$dir"
        echo "Downloading '${path}'"
        curl -sL -H "Authorization: Bearer $token" \
            "${REGISTRY_ENDPOINT}/v2/${path}" \
            -o "$filename"

        echo "Saved blob to '$filename'"
        tar -C "${DEFAULT_IMAGE_STORE}/${split_digest[1]}" -xf "${DEFAULT_IMAGE_STORE}/${split_digest[1]}/layer.tgz"
        rm -f "${DEFAULT_IMAGE_STORE}/${split_digest[1]}/layer.tgz"
    else
        echo "Layer existed. Skip download..."
    fi
}

function get_image_manifest() { # get_image_manifest <token> <name> <tag>
    local name tag token
    token="$1"
    name="$2"
    tag="$3"

    manifest=$(curl -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    -H "Authorization: Bearer $token" \
    -sS "${REGISTRY_ENDPOINT}/v2/$name/manifests/$tag")

    version=$(jq -r .schemaVersion <<< $manifest)
    if [[ -z $version || $version == "null" ]]
    then
        echo "Invalid manifest $manifest"
        exit 1
    fi

    echo "$manifest"
}

function get_image_layers_digest() { # get_image_layers_digest <token> <name> <tag>
    manifest=$(get_image_manifest "$@")
    layer_digests=$(jq -r .layers[].digest <<< "$manifest")

    echo "${layer_digests}"
}

function normalize_image() { # normalize_image <name>
    if [[ ! "${1}" == *"/"* ]]
    then
        echo "library/${1}"
    else
        echo "$1"
    fi
}

function toy_pull() { # xxx pull <token> <name> <tag>
    local name token
    name=$(normalize_image "$2")
    set -- "${@:1:1}" "$name" "${@:3}"

    token=$1

    [[ -z $token ]] && get_bearer_token "${@:2}"
    # Get manifest
    manifest=$(get_image_manifest "$@")

    # local config_digest config_type
    # config_digest=$(jq -r .config.digest <<< "$manifest")
    # config_type=$(jq -r .config.mediaType <<< "$manifest")

    local layer_digests
    # local layers
    # layers=$(jq -r .layers <<< "$manifest")
    layer_digests=$(jq -r .layers[].digest <<< "$manifest")
    for digest in $layer_digests
    do
        path="$name/blobs/${digest}"
        IFS=: read -ra split_digest <<< "$digest"
        download_blob "$path" "$token" "${DEFAULT_IMAGE_STORE}/${split_digest[1]}/layer.tgz"
    done

    # echo "$layers" > layers.json
}

function generate_container_id() { # generate_container_id <size>
    local id size
    size="$1"
    id=$(openssl rand -hex "${size}")
    echo "$id"
}

function _calculate_next_ip() {
    local ip
    ip="$CONTAINER_FIRST_IP"

    if [[ -f ${IP_TRACKING_FILE} ]]
    then
        local last_used
        last_used=$(cat "${IP_TRACKING_FILE}")
        ip=$(dec2ip $(($(ip2dec "${last_used}")+1)))
    fi

    echo "${ip}"
}

function _setup_bridge() {
    ip link add "${DEFAULT_BRIDGE_NAME}" type bridge
    ip link set "${DEFAULT_BRIDGE_NAME}" up
    ip addr add "${DEFAULT_CONTAINER_GATEWAY_IP}/${DEFAULT_CONTAINER_CIDR_MASK}" dev "${DEFAULT_BRIDGE_NAME}"

    iptables -t nat -A POSTROUTING \
        -s ${DEFAULT_CONTAINER_CIDR_NETWORK}/${DEFAULT_CONTAINER_CIDR_MASK} \
        ! -o ${DEFAULT_BRIDGE_NAME} -j MASQUERADE
    iptables -A FORWARD \
        -i ${DEFAULT_BRIDGE_NAME} -j ACCEPT
    iptables -A FORWARD \
        -o ${DEFAULT_BRIDGE_NAME} -j ACCEPT
}

function _cleanup_network() {
    local container_id
    container_id="$1"

    ip link del "${container_id}_0"
    if [[ -n $(ip netns | grep -oF netns_${container_id}) ]]
    then
        ip netns delete "netns_${container_id}"
    fi
}

function _setup_network() { # _setup_network <container_id>
    local ip container_id
    container_id="$1"
    ip=$(_calculate_next_ip)
    ip link add dev "${container_id}_0" type veth peer "${container_id}_1"
	ip link set dev "${container_id}_0" up

    ip link show ${DEFAULT_BRIDGE_NAME} >/dev/null 2>&1 || _setup_bridge
    ip link set dev "${container_id}_0" master ${DEFAULT_BRIDGE_NAME}

	ip netns add "netns_${container_id}"
	ip link set "${container_id}_1" netns "netns_${container_id}"
	ip netns exec "netns_${container_id}" ip link set dev lo up
	ip netns exec "netns_${container_id}" ip addr add "${ip}/${DEFAULT_CONTAINER_CIDR_MASK}" dev "${container_id}_1"
	ip netns exec "netns_${container_id}" ip link set dev "${container_id}_1" up
	ip netns exec "netns_${container_id}" ip route add default via "${DEFAULT_CONTAINER_GATEWAY_IP}"

    echo "$ip" > "${IP_TRACKING_FILE}"
}

function _setup_cgroups() { # _setup_cgroups <container_id>
    local container_id
    container_id="$1"
    cgcreate -g "${DEFAULT_CGROUPS_CONTROLLER}:${container_id}"
    cgset -r memory.limit_in_bytes="$((DEFAULT_CONTAINER_MEMORY_LIMIT_MB * 1000000))" "${container_id}"
}

function _cleanup_cgroups() { # _cleanup_cgroups <container_id>
    local container_id
    container_id="$1"

    if [[ -d "/sys/fs/cgroup/memory/${container_id}" ]]
    then
        cgdelete -g "${DEFAULT_CGROUPS_CONTROLLER}:${container_id}"
    fi
}

function mount_overlayfs() { # mount_overlayfs <diffs> <container_id>
    local container_id container_data diffs merged lower upper work
    diffs="$1"
    container_id="$2"
    container_data="${DEFAULT_CONTAINER_DIR}/${container_id}"
    [[ -d $container_data ]] && echo "container chroot dir already existed" && exit 1

    merged="${container_data}/${DEFAULT_CONTAINER_OVERLAY_DIR}"
    upper="${container_data}/${DEFAULT_CONTAINER_DIFF_DIR}"
    work="${container_data}/${DEFAULT_CONTAINER_WORK_DIR}"
    init="${container_data}/${DEFAULT_CONTAINER_INIT_DIR}"
    lower=""

    for diff in $diffs
    do
        IFS=: read -ra split_digest <<< "$diff"
        lower="${DEFAULT_IMAGE_STORE}/${split_digest[1]}:${lower}"
    done
    lower="${init}:${lower%:}"

    mkdir -p "${container_data}"/{${DEFAULT_CONTAINER_OVERLAY_DIR},${DEFAULT_CONTAINER_DIFF_DIR},${DEFAULT_CONTAINER_WORK_DIR},${DEFAULT_CONTAINER_INIT_DIR}}
    mkdir "${init}/etc"
    echo "nameserver 1.1.1.1" > "$init/etc/resolv.conf"

    mount -t overlay \
        -o "lowerdir=${lower},upperdir=${upper},workdir=${work}" \
        overlay "${merged}"

    # Allow container access /dev & /sys
    # mount --bind /dev "${merged}/dev"
    
    if [[ ! -d "${merged}/dev/pts" ]]
    then
        mkdir -p "${merged}/dev/pts"
    fi
    mount --bind /dev/pts "${merged}/dev/pts"


    echo "$merged"
}

function _cleanup_container_fs() { # _cleanup_container_fs <container_id>
    local container_data container_id merged
    container_id="$1"
    container_data="${DEFAULT_CONTAINER_DIR}/${container_id}"
    merged="${container_data}/${DEFAULT_CONTAINER_OVERLAY_DIR}"

    echo "unmounting container <$container_id>"
    if mount | grep -q "${merged}/dev/pts"
    then
        umount "${merged}/dev/pts"
    fi
    umount "${merged}"

    echo "removing container <$container_id> data"
    rm -rf "${container_data}"
}


function toy_run() { #HELP Start a container:\n toy run <image_name> <image_tag> <cmd>
    local name tag id token diffs cmd
    name="$1"
    name=$(normalize_image "$1")
    set -- "${name}" "${@:2}"

    tag="$2"
    cmd="$3"
    token=$(get_bearer_token "$name" "$tag")
    toy_pull "$token" "$name" "$tag"
    diffs=$(get_image_layers_digest "$token" "$name" "$tag")

    # Generate random ID for container
    id="$(generate_container_id 6)"

    local container_data
    container_data="${DEFAULT_CONTAINER_DIR}/${id}"

    chroot_dir=$(mount_overlayfs "$diffs" "$id")
    _setup_network "${id}"
    _setup_cgroups "${id}"

    echo "$cmd" > "$container_data/${DEFAULT_CONTAINER_CMD_FILE}"
    echo "${name}:${tag}" > "$container_data/${DEFAULT_CONTAINER_IMAGE_INFO_FILE}"

    cgexec -g "${DEFAULT_CGROUPS_CONTROLLER}:${id}" \
        ip netns exec "netns_$id" \
        unshare --mount --uts --pid --fork \
            --mount-proc \
		    -R "$chroot_dir" \
		/bin/sh -c "mknod -m 666 /dev/null c 1 3 \
            && mknod -m 666 /dev/zero c 1 5 \
            && hostname $id && $cmd"
}

function toy_exec() { #HELP Exec into a container:\n toy exec <container_id> <cmd>
    local id container_root
    id="$1"
    container_root="${DEFAULT_CONTAINER_DIR}/${id}/${DEFAULT_CONTAINER_OVERLAY_DIR}"

    # shellcheck disable=SC2009
    cid="$(ps o ppid,pid | grep -E "^\s+$(ps o pid,cmd | grep -E "^\ *[0-9]+ unshare.*$id" | awk '{print $1}')" \
        | awk '{print $2}')"

    [[ ! "$cid" =~ ^\ *[0-9]+$ ]] && echo "Container '$id' exists but is not running" && exit
	nsenter -t "$cid" -m -u -n -p chroot "$container_root" "${@:2}"
}

function toy_ps() { #HELP Listing created container:\n toy ps
    local containers
    echo "CONTAINER ID,COMMAND,IMAGE" | column -s ',' -t
    containers="$(ls -1 "$DEFAULT_CONTAINER_DIR")"

    for id in $containers
    do
        local cmd chrooted_dir image
        cmd="unknown"
        image="unknown"
        chrooted_dir="${DEFAULT_CONTAINER_DIR}/${id}"
        [[ -f ${chrooted_dir}/${DEFAULT_CONTAINER_CMD_FILE} ]] \
            && cmd=$(cat "${chrooted_dir}/${DEFAULT_CONTAINER_CMD_FILE}")
        [[ -f ${chrooted_dir}/${DEFAULT_CONTAINER_IMAGE_INFO_FILE} ]] \
            && image=$(cat "${chrooted_dir}/${DEFAULT_CONTAINER_IMAGE_INFO_FILE}")

        echo "${id},${cmd:=unknown},${image:=unknown}" | column -s "," -t
    done
}

function toy_rm() { #HELP Remove container:\n toy rm <container_id> [<container_id>]
    for id in "$@"
    do
        _cleanup_container_fs "$id"
        _cleanup_network "$id"
        _cleanup_cgroups "$id"
    done
}

function help() {
    sed -n "s/^.*#HELP\\s//p;" < "$1" | sed "s/\\\\n/\n\t/g;s/$/\n/;s!toy!${1/!/\\!}!g"
}

function main() {
    [[ -z "${1:-}" ]] && help "$0" && exit 0
    case $1 in
        run|ps|rm|exec)
            toy_"$1" "${@:2}" ;;
        *) help "$0" ;;
    esac
}
    
main "$@"
