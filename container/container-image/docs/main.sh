#!/usr/bin/env bash

set -euxo pipefail

REGISTRY_ENDPOINT="https://registry.hub.docker.com"

function get_docker_registry_token() {
    local repository action username password
    if [[ $# -eq 0 || ( $# -gt 1 && $# -ne 4) ]]
    then
        echo "get_docker_registry_token <repository> [<action> <username> <password>]"
        exit 1
    fi

    repository="$1"

    if [[ $# -eq 4 ]]
    then
        action="$2"
        username="$3"
        password="$4"
    else
        action="pull"
        username=""
        password=""
    fi

    url="https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repository}:${action}"

    if [[ -z $username && -z $password ]]
    then
        auth=""
    else
        auth="-u ${username}:${password}"
    fi

    curl -SsL $auth "$url" | jq -r .token
}

function _upload_manifest() {
    local repository manifest tag token content_type
    if [[ $# -ne 5 ]]
    then
        echo "_upload_manifest: not enough arguments"
        exit 1
    fi
    repository="$1"
    manifest="$2"
    tag="$3"
    token="$4"
    content_type="$5"

    if [[ ! -f $manifest ]]
    then
        echo "\"${manifest}\" not a file/not found"
        exit 1
    fi

    curl -Ss -H "Authorization: Bearer ${token}" \
        -H "Content-Type: ${content_type}" \
        --data-binary @"${manifest}" \
        -iL -X PUT "${REGISTRY_ENDPOINT}/v2/$repository/manifests/${tag}"
}

function _upload_blob() {
    local repository tarball token
    repository=${1}
    tarball="$2"

    if [[ ! -f $tarball ]]
    then
        echo "${tarball} not a file"
        exit 1
    fi
    sha256_digest=$(sha256sum "$tarball" | cut -d' ' -f 1 | tr -d "\r\n")

    if [[ $# -gt 2 ]]
    then
        token="$3"
    fi

    headers=()
    if [[ -n $token ]]
    then
        headers=(-H "Authorization: Bearer $token")
    fi

    init_url="${REGISTRY_ENDPOINT}/v2/${repository}/blobs/uploads/"

    upload_location=$(curl -Ss "${headers[@]}" -iL -X POST "${init_url}" | grep -Fi "location:" | tr -d '\r' | cut -d " " -f 2)

    if [[ -z $upload_location ]]
    then
        echo "Empty location headers"
        exit 1
    fi

    # Uploading blob
    curl -SsLi -X PUT "$upload_location&digest=sha256:${sha256_digest}" \
    -H "Content-Type: application/octet-stream" \
    -H "Authorization: Bearer ${token}" \
    --data-binary @"${tarball}"
}

function upload_blobs() {
    local token repository

    if [[ $# -lt 3 ]]
    then
        echo "Not enough arguments"
        echo "upload_blobs repository token blob [blob] [blob]"
        exit 1
    fi
    
    repository="$1"
    token="$2"

    shift 2
    
    while (( "$#" ))
    do
        _upload_blob "$repository" "$1" "$token"
        shift
    done
}

function main() {
    local username password image_name cmd token repository
    if [[ $# -lt 3 ]]
    then
        echo "CMD username password image_name command [args]"
        exit 1
    fi
    username="$1"
    password="$2"
    image_name="$3"
    repository="${username}/${image_name}"
    cmd="$4"
    token=$(get_docker_registry_token "${repository}" pull,push "$username" "$password")
    shift 4

    case $cmd in
        upload-blob)
            upload_blobs "${repository}" "${token}" "$@"
        ;;
        upload-manifest)
            _upload_manifest "${repository}" "$1" "$2" "$token" "application/vnd.docker.distribution.manifest.v2+json"
        ;;
        upload-manifest-list)
            _upload_manifest "${repository}" "${1}" "${2}" "${token}" "application/vnd.docker.distribution.manifest.list.v2+json"
        ;;
        *)
            echo "Invalid command"
            exit 1
        ;;
    esac
}

main "$@"
