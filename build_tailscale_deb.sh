 #!bin/bash
 #
 set -e
 export top_dir=$(pwd)
 export src_dir=${top_dir}/tailscale
    cd ${top_dir}
    [ ! -d ${src_dir} ] &&  git clone https://github.com/tailscale/tailscale
    cd ${src_dir} && git pull

function build_debpkg(){
    ARCH=${1}
    deb_dir=${top_dir}/deb_tailsacle_${ARCH}

    cd ${src_dir}
    [ ! -d ${deb_dir} ] && mkdir -pv ${deb_dir}/{usr/{bin,sbin},etc/{default,systemd/system}}
    # if use sudo root to install need to re-download librarys.
    GOOS=linux GOARCH=${ARCH} GOARM=7 ./tool/go build -o ${deb_dir}/usr/sbin/  tailscale.com/cmd/tailscale tailscale.com/cmd/tailscaled
    GOOS=linux GOARCH=${ARCH} GOARM=7 ./tool/go build -o ${deb_dir}/usr/bin/  tailscale.com/cmd/tailscale tailscale.com/cmd/tailscaled
    cp cmd/tailscaled/tailscaled.defaults ${deb_dir}/etc/default/tailscaled

    sed -i 's/^FLAGS=""/FLAGS="-no-logs-no-support"/' ${deb_dir}/etc/default/tailscaled
    cp cmd/tailscaled/tailscaled.service ${deb_dir}/etc/systemd/system/
     mkdir -pv ${deb_dir}/DEBIAN
     for script in postinst postrm prerm; do
         cp release/deb/debian.${script}.sh ${deb_dir}/DEBIAN/${script}.sh
     done

     local_ver=$(cat VERSION.txt)
     cat > ${deb_dir}/DEBIAN/control << EOF
Package: tailscale-git
Version: ${local_ver}
Installed-Size: 0
Architecture: ${ARCH}
Maintainer: github.com/yjdwbj <yjdwbj@gmail.com>
Homepage: https://tailscale.com/
Section: net
Priority: optional
Description: Private WireGuard® networks made easy
 The easiest, most secure way to use WireGuard and 2FA.
 Tailscale makes creating software-defined networks easy: securely connecting users, services, and devices.
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
