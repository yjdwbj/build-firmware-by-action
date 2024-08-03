 #!bin/bash
 #
 set -e
 export top_dir=$(pwd)
 export src_dir=${top_dir}/syncthing
    cd ${top_dir}
    [ ! -d ${src_dir} ] &&  git clone https://github.com/syncthing/syncthing
    cd ${src_dir} && git pull

function build_debpkg(){
    ARCH=${1}
    deb_dir=${top_dir}/deb_dir_${ARCH}

    cd ${src_dir}
    [ ! -d ${deb_dir} ] && mkdir -pv ${deb_dir}/{usr/bin,etc/systemd}
    # if use sudo root to install need to re-download librarys.
     ./build.sh
     cp bin/syncthing ${deb_dir}/usr/bin/

     cp -av etc/linux-systemd/* ${deb_dir}/etc/systemd/

     mkdir -pv ${deb_dir}/DEBIAN

     # version number should be digit first.
     local_ver=$(sed -n 's/^\.TH.*\([0-9]\.[0-9]\{1,2\}\.[0-9]\{1,2\}\).*/\1/p' man/syncthing-config.5)
     cat > ${deb_dir}/DEBIAN/control << EOF
Package: syncthing-git
Version: ${local_ver}
Installed-Size: 0
Architecture: ${ARCH}
Maintainer: github.com/yjdwbj <yjdwbj@gmail.com>
Homepage: https://syncthing.net/
Section: net
Priority: optional
Description: Private WireGuard® networks made easy
 The easiest, most secure way to use WireGuard and 2FA.
 syncthing makes creating software-defined networks easy: securely connecting users, services, and devices.
EOF
    sh -c "cd '${deb_dir}'; find . -type f ! -path './DEBIAN/*' -printf '%P\0' \
		| xargs -r0 md5sum > DEBIAN/md5sums"
    [ ${ARCH} == "arm" ] && sed -i '/^Architecture:/!b;cArchitecture: armhf' ${deb_dir}/DEBIAN/control

    pkg_size_bytes=$(du -s -b "${deb_dir}" | cut -f1)
    installed_size=$(((pkg_size_bytes + 1023) / 1024))
    sh -c " cd '${deb_dir}'; \
        sed -i '/^Installed-Size:/!b;cInstalled-Size: ${installed_size}' DEBIAN/control"
    dpkg-deb -b -Znone "${deb_dir}" ../
}

for arch in arm64 arm amd64; do
    build_debpkg ${arch}
done
