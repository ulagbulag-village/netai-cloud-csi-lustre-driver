# Copyright 1999-2021 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
#
# Copyright (c) 2022 Ho Kim (ho.kim@ulagbulag.io).
# Use of this source code is governed by a GPL-3-style license that can be
# found in the LICENSE file.

EAPI=7

scm="git-r3"
SRC_URI=""
EGIT_REPO_URI="git://git.whamcloud.com/fs/lustre-release.git"
EGIT_COMMIT="${PV}"

inherit ${scm} autotools dist-kernel-utils flag-o-matic linux-info linux-mod toolchain-funcs

DESCRIPTION="Lustre is a parallel distributed file system"
HOMEPAGE="https://wiki.whamcloud.com/"

LICENSE="GPL-2"
SLOT="0"
IUSE="+client +dlc +modules readline +rootfs +server tests +utils"

RDEPEND="
	dlc? ( dev-libs/libyaml )
	readline? ( sys-libs/readline:0 )
	server? (
		sys-cluster/openmpi
		>=sys-fs/zfs-kmod-0.8
		>=sys-fs/zfs-0.8
	)
	sys-apps/sandbox
	virtual/awk
"
DEPEND="${RDEPEND}
	virtual/linux-sources
"

REQUIRED_USE="
	client? ( modules )
	server? ( modules )
"

PATCHES=()

pkg_pretend() {
	use rootfs || return 0
}

pkg_setup() {
	filter-mfpmath sse
	filter-mfpmath i386
	filter-flags -msse* -mavx* -mmmx -m3dnow

	linux-mod_pkg_setup
	ARCH="$(tc-arch-kernel)"
	ABI="${KERNEL_ABI}"
}

src_prepare() {
	default

	if [ ${#PATCHES[0]} -ne 0 ]; then
		eapply ${PATCHES[@]}
	fi

	eapply_user

	# replace upstream autogen.sh by our src_prepare()
	local DIRS="libcfs lnet lustre snmp"
	local ACLOCAL_FLAGS
	for dir in $DIRS; do
		ACLOCAL_FLAGS="$ACLOCAL_FLAGS -I $dir/autoconf"
	done

	export FEATURES="-sandbox -usersandbox"

	_elibtoolize -q
	eaclocal -I config $ACLOCAL_FLAGS
	eautoheader
	eautomake
	eautoconf
}

src_configure() {
	set_arch_to_kernel

	filter-ldflags -Wl,*

	# Set CROSS_COMPILE in the environment.
	# This allows the user to override it via make.conf or via a local Makefile.
	# https://bugs.gentoo.org/811600
	export CROSS_COMPILE=${CROSS_COMPILE-${CHOST}-}

	local myconf
	if use server; then
		SPL_PATH=$(basename $(echo "${EROOT}/usr/src/spl-"*))
		myconf="${myconf} \
			--with-spl=${EROOT}/usr/src/${SPL_PATH} \
			--with-spl-obj=${EROOT}/usr/src/${SPL_PATH}/${KV_FULL}"
		ZFS_PATH=$(basename $(echo "${EROOT}/usr/src/zfs-"*))
		myconf="${myconf} \
			--with-zfs=${EROOT}/usr/src/${ZFS_PATH} \
			--with-zfs-obj=${EROOT}/usr/src/${ZFS_PATH}/${KV_FULL}"
	fi

	econf \
		HOSTCC="$(tc-getBUILD_CC)" \
		${myconf} \
		--bindir="${EPREFIX}/bin" \
		--sbindir="${EPREFIX}/sbin" \
		--without-ldiskfs \
		--with-config=kernel \
		--with-linux="${KV_DIR}" \
		--with-linux-obj="${KV_OUT_DIR}" \
		$(use_enable client) \
		$(use_enable dlc) \
		$(use_enable modules) \
		$(use_enable readline) \
		$(use_enable server) \
		$(use_enable tests) \
		$(use_enable utils)
}

src_compile() {
	default
}

src_install() {
	default
}
