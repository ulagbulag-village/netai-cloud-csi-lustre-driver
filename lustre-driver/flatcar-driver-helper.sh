#!/bin/bash
# Copyright (c) 2018-2021, NVIDIA CORPORATION. All rights reserved.
# LICENSE: https://github.com/ulagbulag-village/nvidia-driver-container-images/blob/b2d5970f6d3c3dddf7b0e6b867e294903ff68788/LICENSE
# SOURCE: https://github.com/ulagbulag-village/nvidia-driver-container-images/blob/72284e8ab86f2b97a4a97bc486d2c9673cdc48f8/flatcar/Dockerfile
#
# Copyright (c) 2022 Ho Kim (ho.kim@ulagbulag.io).
# Use of this source code is governed by a GPL-3-style license that can be
# found in the LICENSE file.

# Prehibit errors
set -eu

# Set default environment variables
RUN_DIR=/run/driver
PID_FILE=${RUN_DIR}/${0##*/}.pid
DRIVER_NAME=${DRIVER_NAME:?"Missing driver name"}
DRIVER_VERSION=${DRIVER_VERSION:?"Missing driver version"}
DRIVER_MODULE=${DRIVER_VERSION:?"Missing driver module name"}
DRIVER_MODULE_DEP=${DRIVER_MODULE_DEP:-""}
DRIVER_SOURCE_DIR=/usr/src/driver/

# The developement environment is required to access gcc and binutils
# binutils is particularly required even if we have precompiled kernel interfaces
# as the ld version needs to match the version used to build the linked kernel interfaces later
# Note that container images can only contain precompiled (but not linked) kernel modules
_install_development_env() {
    echo "Removing the unrelated kernel sources..."

    rm -rf "/lib/modules/${KERNEL_VERSION}"
    rm -rf /usr/src/kernels /usr/src/linux*

    echo "Installing the Flatcar development environment on the filesystem $PWD..."

    # Get the flatcar development environment for a given kernel version.
    # The environment is mounted on a loop device and then we chroot into
    # the mount to build the kernel driver interface.
    # The resulting module files and module dependencies are then archived.
    local dev_image="/tmp/flatcar_developer_container.bin"
    local dev_image_url="https://${FLATCAR_RELEASE_CHANNEL}.release.flatcar-linux.net/${FLATCAR_RELEASE_BOARD}/${FLATCAR_VERSION}/${dev_image##*/}.bz2"

    curl -Ls "${dev_image_url}" | lbzip2 -dq >"${dev_image}"
    local sector_size=$(fdisk -l "${dev_image}" | grep "^Sector size" | awk '{ print $4 }')
    local sector_start=$(fdisk -l "${dev_image}" | grep "^${dev_image}*" | awk '{ print $2 }')
    local offset_limit=$((sector_start * sector_size))

    mkdir -p /mnt/flatcar /mnt/dev
    _exec mount -o offset=${offset_limit} ${dev_image} /mnt/dev
    tar -cp -C /mnt/dev . | tar -xpf - -C /mnt/flatcar
    _exec umount -l /mnt/dev
    rm -f "${dev_image}"

    # Version.txt contains some pre-defined environment variables
    # that we will use when building the kernel modules
    curl -fOSsL "https://${FLATCAR_RELEASE_CHANNEL}.release.flatcar-linux.net/${FLATCAR_RELEASE_BOARD}/${FLATCAR_VERSION}/version.txt"
    cp version.txt /usr/src

    # Append the source code directory information
    echo "DRIVER_NAME=$DRIVER_NAME" >/usr/src/driver.txt
    echo "DRIVER_SOURCE_DIR=$DRIVER_SOURCE_DIR" >>/usr/src/driver.txt
    echo "DRIVER_VERSION=$DRIVER_VERSION" >>/usr/src/driver.txt

    # Copy the build script into source code
    cp "./build-driver.sh" "$DRIVER_SOURCE_DIR"

    # Prepare the mount point for the chroot
    cp --dereference /etc/resolv.conf /mnt/flatcar/etc/
    _exec mount --rbind /dev /mnt/flatcar/dev
    _exec mount --make-rslave /mnt/flatcar/dev
    _exec mount --types proc /proc /mnt/flatcar/proc
    _exec mount --rbind /sys /mnt/flatcar/sys
    _exec mount --make-rslave /mnt/flatcar/sys
    mkdir -p /mnt/flatcar/usr/src
    _exec mount --rbind /usr/src /mnt/flatcar/usr/src
}

_cleanup_development_env() {
    echo "Cleaning up the Flatcar development environment..."

    _exec umount -lR /mnt/flatcar/{dev,proc,sys,usr/src}
    rm -rf /mnt/flatcar
}

# Install the kernel modules header/builtin/order files and generate the kernel version string.
# The kernel sources are installed on the loop mount by following the official documentation at
# https://kinvolk.io/docs/flatcar-container-linux/latest/reference/developer-guides/kernel-modules/
# We also ensure that the kernel version string (/proc/version) is written so it can be
# archived along with the precompiled kernel interfaces.
_build_driver_kernel_module() {
    _install_development_env

    echo "Building the Flatcar kernel sources into the development environment..."

    cat <<'EOF' | chroot /mnt/flatcar /bin/bash
        export KERNEL_VERSION=$(uname -r)
        export KERNEL_STRING=$(echo "${KERNEL_VERSION}" | cut -d "-" -f1)

        echo "Inspecting the Flatcar kernel sources for kernel version ${KERNEL_VERSION}..."
        source /etc/os-release
        export $(cat /usr/src/driver.txt | xargs)
        export $(cat /usr/src/version.txt | xargs)

        echo "Compiling Flatcar ${DRIVER_NAME} driver kernel modules with $(gcc --version | head -1)..."
        cp /lib/modules/${KERNEL_VERSION}/build/scripts/module.lds "${DRIVER_SOURCE_DIR}"
        cd "${DRIVER_SOURCE_DIR}"
        $0 "${DRIVER_SOURCE_DIR}/build-driver.sh"
EOF

    # Copy kernel modules
    mkdir -p /lib/modules/${KERNEL_VERSION}
    cp -r /mnt/flatcar/lib/modules/${KERNEL_VERSION}/* /lib/modules/${KERNEL_VERSION}/
    depmod "${KERNEL_VERSION}"

    # Copy binareis
    if [ -d "/mnt/flatcar/opt/driver" ]; then
        mkdir -p /opt/driver
        cp -r /mnt/flatcar/opt/driver/* /opt/driver/*
    fi

    _cleanup_development_env
}

# Compile the kernel modules, optionally sign them, and generate a precompiled package for use later.
_create_driver_package() (
    _build_driver_kernel_module

    if [ -f "./create-driver.sh" ]; then
        $0 "./create-driver.sh"
    fi
)

# Update if the kernel version requires a new precompiled driver packages.
_update_driver_package() {
    if [ -f "./check-driver.sh" ]; then
        if ! $0 "./check-driver.sh"; then
            _create_driver_package
        fi
    fi
}

# Link and install the kernel modules from a precompiled package.
_install_driver() {
    _update_driver_package

    if [ -f "./install-driver.sh" ]; then
        $0 "./install-driver.sh"
    fi
    _load_driver
}

# Load the kernel modules and start persistence daemon.
_load_driver() {
    echo "Loading ${DRIVER_NAME} driver kernel modules..."
    for module in $DRIVER_MODULE_DEP; do
        modprobe -av "$module"
    done
    modprobe -av "$DRIVER_MODULE"

    if [ -f "./load-driver.sh" ]; then
        $0 "./load-driver.sh"
    fi

    _mount_rootfs
}

# Stop persistence daemon and unload the kernel modules if they are currently loaded.
_unload_driver() {
    _unmount_rootfs || return 1

    if [ -f "./unload-driver.sh" ]; then
        $0 "./unload-driver.sh" || return 1
    fi

    echo "Unloading ${DRIVER_NAME} driver kernel modules..."
    modprobe -rv "$DRIVER_MODULE" || return 1
    for module in $(echo $DRIVER_MODULE_DEP | rev); do
        modprobe -rv "$(echo $module | rev)" || true
    done

    return 0
}

# Execute binaries by root owning them first
_exec() {
    exec_bin_path=$(command -v "$1")
    exec_user=$(stat -c "%u" "${exec_bin_path}")
    exec_group=$(stat -c "%g" "${exec_bin_path}")
    if [[ "${exec_user}" != "0" || "${exec_group}" != "0" ]]; then
        chown 0:0 "${exec_bin_path}"
        "$@"
        chown "${exec_user}":"${exec_group}" "${exec_bin_path}"
    else
        "$@"
    fi
}

# Mount the driver rootfs into the run directory with the exception of sysfs.
_mount_rootfs() {
    echo "Mounting ${DRIVER_NAME} driver rootfs..."
    _exec mount --make-runbindable /sys
    _exec mount --make-private /sys
    mkdir -p ${RUN_DIR}/driver
    _exec mount --rbind / ${RUN_DIR}/driver
}

# Unmount the driver rootfs from the run directory.
_unmount_rootfs() {
    echo "Unmounting ${DRIVER_NAME} driver rootfs..."
    if findmnt -r -o TARGET | grep "${RUN_DIR}/driver" >/dev/null; then
        _exec umount -l -R ${RUN_DIR}/driver
    fi
}

_shutdown() {
    if _unload_driver; then
        rm -f "${PID_FILE}"
        return 0
    fi
    return 1
}

init() {
    printf "\\n========== Flatcar %s Driver Installer ==========\\n" "${DRIVER_NAME}"
    printf "Starting installation of Flatcar %s driver version %s for Linux kernel version %s\\n" "${DRIVER_NAME}" "${DRIVER_VERSION}" "${KERNEL_VERSION}"

    exec 3>"${PID_FILE}"
    if ! flock -n 3; then
        echo "An instance of the Flatcar ${DRIVER_NAME} driver is already running, aborting"
        exit 1
    fi
    echo $$ >&3

    trap "echo 'Caught signal'; exit 1" HUP INT QUIT PIPE TERM
    trap "_shutdown" EXIT

    _unload_driver || exit 1
    _install_driver

    echo "Done, now waiting for signal"
    sleep infinity &
    trap "echo 'Caught signal'; _shutdown && { kill $!; exit 0; }" HUP INT QUIT PIPE TERM
    trap - EXIT
    while true; do wait $! || continue; done
    exit 0
}

update() {
    printf "\\n========== Flatcar %s Driver Updater ==========\\n" "${DRIVER_NAME}"
    printf "Starting update of Flatcar %s driver version %s for Linux kernel version %s\\n" "${DRIVER_NAME}" "${DRIVER_VERSION}" "${KERNEL_VERSION}"

    exec 3>&2
    if exec 2>/dev/null 4<"${PID_FILE}"; then
        if ! flock -n 4 && read -r pid <&4 && kill -0 "${pid}"; then
            exec > >(tee -a "/proc/${pid}/fd/1")
            exec 2> >(tee -a "/proc/${pid}/fd/2" >&3)
        else
            exec 2>&3
        fi
        exec 4>&-
    fi
    exec 3>&-

    trap "echo 'Caught signal'; exit 1" HUP INT QUIT PIPE TERM

    _update_driver_package

    echo "Done"
    exit 0
}

usage() {
    cat >&2 <<EOF
Usage: $0 COMMAND [ARG...]
Commands:
  init   [-a | --accept-license]
  update [-k | --kernel VERSION] [-s | --sign KEYID] [-t | --tag TAG]
EOF
    exit 1
}

main() {
    if [ $# -eq 0 ]; then
        usage
    fi

    command=$1
    shift
    case "${command}" in
    init) options=$(getopt -l accept-license -o a -- "$@") ;;
    update) options=$(getopt -l kernel:,sign:,tag: -o k:s:t: -- "$@") ;;
    *) usage ;;
    esac
    if [ $? -ne 0 ]; then
        usage
    fi
    eval set -- "${options}"

    ACCEPT_LICENSE=""
    KERNEL_VERSION=$(uname -r)
    PRIVATE_KEY=""
    PACKAGE_TAG=""

    for opt in ${options}; do
        case "$opt" in
        -a | --accept-license)
            ACCEPT_LICENSE="yes"
            shift 1
            ;;
        -k | --kernel)
            KERNEL_VERSION=$2
            shift 2
            ;;
        -s | --sign)
            PRIVATE_KEY=$2
            shift 2
            ;;
        -t | --tag)
            PACKAGE_TAG=$2
            shift 2
            ;;
        --)
            shift
            break
            ;;
        esac
    done
    if [ $# -ne 0 ]; then
        usage
    fi

    $command
}

main
