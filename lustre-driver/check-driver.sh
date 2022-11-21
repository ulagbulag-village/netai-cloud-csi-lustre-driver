#!/bin/bash
# Copyright (c) 2022 Ho Kim (ho.kim@ulagbulag.io). All rights reserved.
# Use of this source code is governed by a GPL-3-style license that can be
# found in the LICENSE file.

# Prehibit errors
set -eu

# Get the driver's information
LAST_DRIVER_VERSION=$(
    "/opt/driver/lib/ld-linux-x86-64.so.2" --library-path "/opt/driver/lib/" "/opt/driver/bin/lfs" --version |
        grep -Po '[0-9\.]+'
)

# Test the driver version
if [[ "${DRIVER_VERSION}" != "${LAST_DRIVER_VERSION}" ]]; then
    exit 1
fi

# All the tests are passed
exit 0
