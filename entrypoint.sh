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

    cloudsmith push rpm "${cloudsmith_default_args[@]}" "${CLOUDSMITH_REPO}/${distro}/${release_ver}" "${pkg_fullpath}"
}

function upload_deb {
    distro=$1
    release=$2
    pkg_fullpath=$3

    cloudsmith push deb "${cloudsmith_default_args[@]}" "${CLOUDSMITH_REPO}/${distro}/${release}" "${pkg_fullpath}"
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
