#!/bin/bash
# Copyright (c) 2022 Ho Kim (ho.kim@ulagbulag.io). All rights reserved.
# Use of this source code is governed by a GPL-3-style license that can be
# found in the LICENSE file.

# Prehibit errors
set -eu

# Get Gentoo repository
cat >/etc/portage/repos.conf/gentoo.conf <<'EOF'
[DEFAULT]
main-repo = gentoo

[gentoo]
disabled = false
location = /var/lib/portage/gentoo
sync-type = git
sync-uri = https://github.com/gentoo/gentoo.git
EOF

mkdir -p /var/lib/portage/scripts/sdk_container/src/third_party/portage-stable/metadata/
cat >/var/lib/portage/scripts/sdk_container/src/third_party/portage-stable/metadata/layout.conf <<'EOF'
repo-name = portage-stable
masters = gentoo
use-manifests = strict
thin-manifests = true
cache-format = md5-dict
EOF

# Load packages info
rm -rf /var/lib/portage/gentoo
emerge-gitclone
emerge --sync gentoo

# Unmask lustre package as missing keyword
mkdir -p /etc/portage/package.accept_keywords/
cat >/etc/portage/package.accept_keywords/liblo <<'EOF'
sys-cluster/lustre **
EOF

# Install dependencies
emerge --verbose \
    "bc::portage-stable" \
    "coreos-sources::coreos" \
    "dev-libs/libyaml::portage-stable" \
    "elt-patches::portage-stable" \
    "flex::portage-stable" \
    "linux-sources::coreos" \
    "mt-st::gentoo" \
    "openmpi::gentoo" \
    "perl::portage-stable" \
    "rpm::gentoo" \
    "swig::gentoo"

# Configure environment variables
export FEATURES="-sandbox -usersandbox"
export KV_DIR="/usr/src/linux"
export KV_OUT_DIR="/lib/modules/${KERNEL_VERSION}/build/"
export LUSTRE_DIR="/opt/driver"

# Use full linux kernel sources
mv "/lib/modules/${KERNEL_VERSION}/source/" "/lib/modules/${KERNEL_VERSION}/source-bak/"
ln -sf "/usr/src/linux" "/lib/modules/${KERNEL_VERSION}/source"

# Fix package version
pushd /var/lib/portage/portage-stable
mv "./sys-cluster/lustre/lustre-9999.ebuild" "./sys-cluster/lustre/lustre-${DRIVER_VERSION}.ebuild"
popd

# Install packages
emerge --verbose "lustre::portage-stable"

# Copy linked shared libraries
mkdir -p "$LUSTRE_DIR/lib"
for lib in $(
    file ${LUSTRE_DIR}/*bin/* |
        awk -F: '$2 ~ "dynamically linked" {print $1}' |
        xargs lddtree |
        grep -Po '=> \K(/lib[0-9a-zA-Z_/\.\-]*)'
); do
    lib_dst="$LUSTRE_DIR/lib/$(dirname $lib)"
    if [ ! -f "$lib_dst" ]; then
        cp "/usr/$lib" "$lib_dst"
    fi
done
