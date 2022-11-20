# Copyright (c) 2022 Ho Kim (ho.kim@ulagbulag.io). All rights reserved.
# Use of this source code is governed by a GPL-3-style license that can be
# found in the LICENSE file.

# Configure environment variables
ARG DRIVER_NAME="Lustre"
ARG DRIVER_VERSION="2.15.52"
ARG ROCKYLINUX_VERSION="8"

# Be ready for building
FROM docker.io/library/rockylinux:${ROCKYLINUX_VERSION} as builder

# Inherit environment variables
ARG DRIVER_NAME
ARG DRIVER_VERSION
ARG ROCKYLINUX_VERSION
ENV DRIVER_NAME=${DRIVER_NAME}
ENV DRIVER_VERSION=${DRIVER_VERSION}

# Volumes Configuration
VOLUME /opt/driver/

# Install dependencies
RUN dnf install --assumeyes epel-release rocky-release \
    # Install packages
    && dnf install --assumeyes --enablerepo=powertools \
    kmod lbzip2 \
    # Cleanup
    && dnf clean all \
    && rm -rf /var/cache /var/log/dnf* /var/log/yum.*

# Builder Configuration
WORKDIR /usr/src/driver/
CMD ["/usr/src/driver/flatcar-driver-helper.sh"]

# Load files
ADD ./*.sh /usr/src/driver/
