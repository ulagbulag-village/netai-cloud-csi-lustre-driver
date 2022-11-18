#!/bin/bash
# Copyright (c) 2022 Ho Kim (ho.kim@ulagbulag.io). All rights reserved.
# Use of this source code is governed by a GPL-3-style license that can be
# found in the LICENSE file.

# Prehibit errors
set -eu

# Configure environment variables
export KV_OUT_DIR="/lib/modules/${KERNEL_VERSION}/build/"
# export CONFIG_MODULES=y

# Install dependencies
emerge-gitclone &&
    emerge --verbose \
        openmpi

# Get Gentoo repository
cat >/etc/portage/repos.conf/gentoo.conf <<'EOF'
[gentoo]
disabled = false
location = /var/lib/portage/portage-gentoo
sync-type = git
sync-uri = https://github.com/gentoo/gentoo.git
EOF

mkdir -p /var/lib/portage/portage-gentoo/metadata/
cat >/var/lib/portage/portage-gentoo/metadata/layout.conf <<'EOF'
repo-name = gentoo
masters = portage-stable
use-manifests = strict
thin-manifests = true
cache-format = md5-dict
EOF

emerge --sync gentoo

# Get packages from Gentoo repository
PKG_GENTOO=(
    "sys-fs/udev-init-scripts"
    "sys-fs/zfs"
    "sys-fs/zfs-kmod"
    "eclass/dist-kernel-utils.eclass"
    "virtual/dist-kernel"
)

for pkg in ${PKG_GENTOO[@]}; do
    ln -sf "/var/lib/portage/portage-gentoo/$pkg" "/var/lib/portage/portage-stable/$pkg"
done

# Disable Gentoo repository
rm -rf /etc/portage/repos.conf/gentoo.conf

# Install ZFS
emerge --verbose zfs

# Compile the Lustre driver kernel modules into the development environment
pushd ./lustre-release
popd
