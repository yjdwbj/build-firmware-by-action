#!/bin/bash

set -e

export TARGET_ARCH=arm-linux-gnueabi
export BOARD_NAME="riotboard"
export CROSS_COMPILE=${TARGET_ARCH}-
export ARCH=arm
export KBUILD_BUILD_USER="yjdwbj"
export KBUILD_BUILD_HOST="gmail.com"
export INSTALL_MOD_STRIP=1
export KERNEL_SRC=""
declare BUILD_KER_VER=5.10.160

shell_dir="$(pwd)"
repo_dir="${shell_dir}"

[ ! -d ${repo_dir} ] && mkdir -pv ${repo_dir}

function create_debian_folder (){
    pdir=${1}
    [ -d ${pdir} ] && rm -rf ${pdir}
    local_ver=${2}
    [ -d ${pdir} ] && rm -rf ${pdir}
    mkdir -pv ${pdir}/{boot,DEBIAN,etc/kernel/{post{rm,inst},pre{rm,inst}}.d}

    cat > ${pdir}/DEBIAN/control << EOF
Package: linux-image-${local_ver}
Version: ${BUILD_KER_VER}
Source: linux-${BUILD_KER_VER}
Kernel-Version: ${BUILD_KER_VER}
Kernel-Version-Family: ${local_ver}
Installed-Size: 0
Architecture: ${ARCH}hf
Maintainer: github.com/yjdwbj <yjdwbj@gmail.com>
Section: kernel
Priority: optional
Provides: linux-image, riotboard
Depends: initramfs-tools
Description: Linux latest stable kernel image ${local_ver}-${ARCH}
 This package contains the Linux kernel, modules and corresponding other files.

EOF
    echo "create install scripts"
    debhookdir=/etc/kernel
    for script in postinst postrm preinst prerm; do
		mkdir -pv "${pdir}${debhookdir}/${script}.d"

		mkdir -pv "${pdir}/DEBIAN"
		cat  > "${pdir}/DEBIAN/${script}" << EOF
#!/bin/sh

set -e


# Pass maintainer script parameters to hook scripts
export DEB_MAINT_PARAMS="\$*"

# Tell initramfs builder whether it's wanted
export INITRD=Yes

test -d ${debhookdir}/${script}.d && run-parts --arg="${local_ver}" --arg="/boot/vmlinuz-${local_ver}" ${debhookdir}/${script}.d
EOF
		chmod 755 "${pdir}/DEBIAN/${script}"

        if [ ${script} == "postinst" ]; then
            echo "depmod ${local_ver}" >> "${pdir}/DEBIAN/${script}"
            echo "update-initramfs -c -k ${local_ver}" >> "${pdir}/DEBIAN/${script}"
            echo "mkimage -A arm -O linux -T ramdisk -C gzip -n uInitrd -d /boot/initrd.img-${local_ver} /boot/uInitrd" >> "${pdir}/DEBIAN/${script}"
            echo "exit 0" >> "${pdir}/DEBIAN/${script}"
        else
            echo "exit 0" >> "${pdir}/DEBIAN/${script}"
        fi
	done
}


build_88XXau(){
    # support 0bda:0811 Realtek Semiconductor Corp. Realtek 8812AU/8821AU 802.11ac WLAN Adapter [USB Wireless Dual-Band Adapter 2.4/5Ghz]
    MOD_PATH=${1}
    KER_PATH=${repo_dir}/linux-${BUILD_KER_VER}
    export UR=${BUILD_KER_VER}-${BOARD_NAME}

    [ ! -d  ${repo_dir}/rtl8812au ] && git clone https://github.com/aircrack-ng/rtl8812au.git --depth=1 ${repo_dir}/rtl8812au
    cd ${repo_dir}/rtl8812au && git pull
    sed -i 's/CONFIG_PLATFORM_I386_PC = y/CONFIG_PLATFORM_I386_PC = n/g' Makefile
    sed -i 's/CONFIG_PLATFORM_ARM_RPI = n/CONFIG_PLATFORM_ARM_RPI = y/g' Makefile
    sed -i 's/KSRC :=/KSRC ?=/g' Makefile
    sed -i 's/CROSS_COMPILE :=/CROSS_COMPILE ?=/g' Makefile
    # build custom wifi driver
    echo "build custom wifi driver for ARCH: ${ARCH}"
    KVER=${BUILD_KER_VER} KSRC=${KER_PATH} make -j $(grep -c processor /proc/cpuinfo)
    cp 88XXau.ko ${MOD_PATH}/lib/modules/${UR}/kernel/drivers/net/wireless/
    echo "build kernel and driver modules done."
}

function build_kernel_deb() {
    ker_tar=${1}
    [ -d ${repo_dir}/linux-${kernel_ver} ] && rm -rf ${repo_dir}/linux-${kernel_ver}
    cd ${repo_dir}
    tar xf ${ker_tar}
    cd ${repo_dir}/linux-${BUILD_KER_VER}
    #BUILD_KER_VER=$(make kernelversion)
    cp ${shell_dir}/riotboard_defconfig arch/arm/configs/riotboard_defconfig
    make riotboard_defconfig
    scripts/config --set-str LOCALVERSION ""
    export LOCALVERSION=-${BOARD_NAME}
    make -j`nproc`
    #export INSTALL_PATH=${repo_dir}/kernel_deb
    export UR=${BUILD_KER_VER}-${BOARD_NAME}
    export INSTALL_MOD_PATH=${repo_dir}/kernel_deb_${ARCH}
    export INSTALL_DTBS_PATH=${INSTALL_MOD_PATH}/boot/dtbs-${UR}
    create_debian_folder ${INSTALL_MOD_PATH} ${UR}
    echo "Build kernel at ${PWD}"
    make  modules_install
    make  dtbs
    sh -c "cd '${INSTALL_MOD_PATH}'; find . -type f ! -path './DEBIAN/*' -printf '%P\0' \
		| xargs -r0 md5sum > DEBIAN/md5sums"

    pkg_size_bytes=$(du -s -b "${INSTALL_MOD_PATH}" | cut -f1)
    installed_size=$(((pkg_size_bytes + 1023) / 1024))
    sh -c " cd '${INSTALL_MOD_PATH}'; \
        sed -i '/^Installed-Size:/!b;cInstalled-Size: ${installed_size}' DEBIAN/control"

    [ -f arch/arm/boot/zImage ] && cp arch/arm/boot/zImage  ${INSTALL_MOD_PATH}/boot
    cp arch/arm/boot/dts/nxp/imx/imx6dl-riotboard.dtb ${INSTALL_MOD_PATH}/boot

    cp .config ${INSTALL_MOD_PATH}/boot/config-${UR}
    cp System.map ${INSTALL_MOD_PATH}/boot/System.map-${UR}
    build_88XXau ${INSTALL_MOD_PATH}
    echo "Build deb at $(pwd), github workspace is: ${workspace }"
    dpkg-deb --root-owner-group -b -Znone ${INSTALL_MOD_PATH} ../
    # systemd-nspawn_exec dpkg -i /opt/build/${kernel_deb}
}


function get_kernel_to_build() {
    KERNEL_GIT=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
    vlist=$(git ls-remote --tags $KERNEL_GIT | awk -F '/' '{print $3}' | grep '^v[0-9].[0-9].[0-9]\{1,2\}$')
    maxn=0
    tag=""
    for num in $vlist
    do
        # v=$(echo $num | tr -d -c 0-9)
        ma=$(echo $num | cut -d. -f1 | tr -d -c 0-9)
        mi=$(echo $num | cut -d. -f2)
        re=$(echo $num | cut -d. -f3)
        v=$((ma * 1000 + mi * 100 +  re))
        if (( $v > $maxn )); then
            maxn=$v
            tag=$num
        fi
    done
    M_VER=$(echo ${tag} | awk -F '.' '{print $1".x"}')
    BUILD_KER_VER=$(echo ${tag} | tr -d -c 0-9.)
    kernel_deb=linux-image-${BUILD_KER_VER}-${BOARD_NAME}_${BUILD_KER_VER}-1_${architecture}.deb
    if [ -f ${repo_dir}/${kernel_deb} ]; then
        cp ${repo_dir}/${kernel_deb} ${build_dir}/
        # systemd-nspawn_exec dpkg -i /opt/build/${kernel_deb}
        return 0
    fi

    KER_FNAME="linux-${BUILD_KER_VER}"
    KER_TAR="${KER_FNAME}.tar.xz"
    DKER_URL="https://cdn.kernel.org/pub/linux/kernel/${M_VER}/${KER_TAR}"

    [ ! -f  ${repo_dir}/${KER_TAR} ] && wget -q -c "$DKER_URL" -O ${repo_dir}/${KER_TAR}
    echo "after kernel downloading...."

    build_kernel_deb ${repo_dir}/${KER_TAR} ${BUILD_KER_VER}

}

get_kernel_to_build

