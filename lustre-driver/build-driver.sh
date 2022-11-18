#!/bin/bash
# Copyright (c) 2022 Ho Kim (ho.kim@ulagbulag.io). All rights reserved.
# Use of this source code is governed by a GPL-3-style license that can be
# found in the LICENSE file.

# Prehibit errors
set -eu

# Configure environment variables
export KERNEL_DIR="/lib/modules/${KERNEL_VERSION}/build/"
export KV_OUT_DIR="$KERNEL_DIR"

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

mkdir -p /var/lib/portage/gentoo/metadata/
cat >/var/lib/portage/gentoo/metadata/layout.conf <<'EOF'
repo-name = gentoo
masters = portage-stable
use-manifests = strict
thin-manifests = true
cache-format = md5-dict
EOF

# Load packages info
rm -rf /var/lib/portage/gentoo
emerge-gitclone
emerge --sync gentoo

# Install dependencies
emerge --verbose \
    "bc::portage-stable" \
    "coreos-sources::coreos" \
    "elt-patches::portage-stable" \
    "flex::portage-stable" \
    "linux-sources::coreos" \
    "mt-st::gentoo" \
    "openmpi::gentoo" \
    "perl::portage-stable" \
    "swig::gentoo" \
    "zfs::gentoo"

# Compile the Lustre driver kernel modules into the development environment
pushd ./lustre-release
sh autogen.sh
./configure --enable-client --enable-server
make
# make pkg-kmod
popd
