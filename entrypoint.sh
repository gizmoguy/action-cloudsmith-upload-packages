#!/bin/bash

set -e -o pipefail

PACKAGE_LOCATION="${1}"
CLOUDSMITH_REPO="${2}"
CLOUDSMITH_USERNAME="${3}"
export CLOUDSMITH_API_KEY="${4}"

cloudsmith_default_args=(--no-wait-for-sync --republish)

# required to make python 3 work with cloudsmith script
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# redirect fd 5 to stdout
exec 5>&1

function upload_rpm {
    distro=$1
    pkg_fullpath=$2
    pkg_filename="$(basename "${pkg_fullpath}")"
    rev_filename=$(echo "${pkg_filename}" | rev)

    pkg_name=$(echo "${rev_filename}" | cut -d '-' -f3- | rev)
    pkg_version=$(echo "${rev_filename}" | cut -d '-' -f1-2 | rev | cut -d '.' -f1-3)
    pkg_arch=$(echo "${rev_filename}" | cut -d '.' -f2 | rev)
    pkg_rel=$(echo "${rev_filename}" | cut -d '.' -f3 | rev)
    release_ver="${pkg_rel:2}"

    output=$(cloudsmith push rpm "${cloudsmith_default_args[@]}" "${CLOUDSMITH_REPO}/${distro}/${release_ver}" "${pkg_fullpath}" | tee /dev/fd/5)
    pkg_slug=$(echo "${output}" | grep "Created: ${CLOUDSMITH_REPO}" | awk '{print $2}')
    cloudsmith_sync "${pkg_slug}"
}

function upload_deb {
    distro=$1
    release=$2
    pkg_fullpath=$3

    output=$(cloudsmith push deb "${cloudsmith_default_args[@]}" "${CLOUDSMITH_REPO}/${distro}/${release}" "${pkg_fullpath}" | tee /dev/fd/5)
    pkg_slug=$(echo "${output}" | grep "Created: ${CLOUDSMITH_REPO}" | awk '{print $2}')
    cloudsmith_sync "${pkg_slug}"
}

function cloudsmith_sync {
    pkg_slug=$1

    retry_count=1
    timeout=5
    backoff=1.2
    while true; do
        if [ "${retry_count}" -gt 20 ]; then
            echo "Exceeded retry attempts for package synchronisation"
            exit 1
        fi
        output=$(cloudsmith status "${pkg_slug}" | tee /dev/fd/5)
        if echo "${output}" | grep "Completed / Fully Synchronised"; then
            break
        fi
        sleep ${timeout}
        retry_count=$((retry_count+1))
        timeout=$(python3 -c "print(round(${timeout}*${backoff}))")
    done
}

function cloudsmith_upload {
    distro=$1
    release=$2
    pkg_fullpath=$3

    if [[ ${distro} =~ centos ]]; then
        upload_rpm "centos" "${pkg_fullpath}"
    elif [[ ${distro} =~ fedora ]]; then
        upload_rpm "fedora" "${pkg_fullpath}"
    else
        upload_deb "${distro}" "${release}" "${pkg_fullpath}"
    fi
}

pip3 install --upgrade cloudsmith-cli


while IFS= read -r -d '' path; do
    IFS=_ read -r distro release <<< "$(basename "${path}")"

    while IFS= read -r -d '' pkg; do
        cloudsmith_upload "${distro}" "${release}" "${pkg}"
    done <    <(find "${path}" -maxdepth 1 -type f -print0)
done <   <(find "${PACKAGE_LOCATION}" -mindepth 1 -maxdepth 1 -type d -print0)
