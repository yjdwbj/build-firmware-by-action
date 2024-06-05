#!/bin/bash
#
set +x

export top_dir=$(pwd)
export src_dir=${top_dir}/v2ray-core

cd ${top_dir}
[ ! -d ${src_dir} ] &&  git clone https://github.com/v2fly/v2ray-core
cd ${src_dir} && git pull

function download_geoip(){
    echo ">>> Download latest geoip.dat"
	wget --no-proxy -O release/config/geoip.dat "https://github.com/v2fly/geoip/raw/release/geoip.dat"

	echo ">>> Download latest geoip-only-cn-private.dat"
	wget --no-proxy -O release/config/geoip-only-cn-private.dat "https://github.com/v2fly/geoip/raw/release/geoip-only-cn-private.dat"

	echo ">>> Download latest geosite.dat"
	wget --no-proxy -O release/config/geosite.dat "https://github.com/v2fly/domain-list-community/raw/release/dlc.dat"
}


function build_v2ray_deb() {
    ARCH=${1}

    cd ${src_dir}
    VERSIONTAG=$(git describe --abbrev=0 --tags)
    BUILDNAME=lcy
    deb_dir=${top_dir}/deb_dir_${ARCH}
    [ ! -d ${deb_dir} ] && mkdir -pv ${deb_dir}/{usr/{bin,share/v2ray},etc/{v2ray,systemd/system}}
    LDFLAGS="-s -w -buildid= -X github.com/v2fly/v2ray-core/v5.codename=${CODENAME} -X github.com/v2fly/v2ray-core/v5.build=${BUILDNAME} -X github.com/v2fly/v2ray-core/v5.version=${VERSIONTAG}"
    env CGO_ENABLED=0 GOARCH=${ARCH} GOARM=6 go build -o ${deb_dir}/usr/bin/v2ray -ldflags "$LDFLAGS" ./main

    mkdir -pv ${deb_dir}/DEBIAN
    cp release/debian/copyright ${deb_dir}/DEBIAN/
    cp release/debian/changelog ${deb_dir}/DEBIAN/
    #cp release/debian/*.service ${deb_dir}/etc/systemd/system/
    cp release/config/*.dat  ${deb_dir}/usr/share/v2ray/
    cp release/config/config.json  ${deb_dir}/etc/v2ray/
    cat >${deb_dir}/etc/systemd/system/v2ray.service <<EOF
[Unit]
Description=V2Ray Service
Documentation=https://www.v2fly.org/
After=network.target nss-lookup.target

[Service]
DynamicUser=yes
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/v2ray  run -config /etc/v2ray/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target

EOF

   local_ver=$(git describe --abbrev=0 --tags | tr -d -c .0-9)
   cat > ${deb_dir}/DEBIAN/control << EOF
Package: v2ray-core-${local_ver}
Version: ${local_ver}
Installed-Size: 0
Architecture: ${ARCH}
Maintainer: github.com/yjdwbj <yjdwbj@gmail.com>
Homepage: https://www.v2fly.org/
Section: net
Priority: optional
Description: Library platform for building proxies in golang
 Project V2Ray is a set of network tools that help you to build your
 own computer network. It secures your network connections and thus
 protects your privacy.
EOF
   cat > ${deb_dir}/DEBIAN/preinst << EOF
cp /etc/v2ray/config.json /etc/v2ray/config.json.old
EOF

   cat > ${deb_dir}/DEBIAN/postinst << EOF
[ -f /etc/v2ray/config.json.old ] && mv /etc/v2ray/config.json.old /etc/v2ray/config.json
EOF
   chmod +x ${deb_dir}/DEBIAN/preinst
   chmod +x ${deb_dir}/DEBIAN/postinst

   sh -c "cd '${deb_dir}'; find . -type f ! -path './DEBIAN/*' -printf '%P\0' \
		| xargs -r0 md5sum > DEBIAN/md5sums"
   [ ${ARCH} == "arm" ] && sed -i '/^Architecture:/!b;cArchitecture: armhf' ${deb_dir}/DEBIAN/control

   pkg_size_bytes=$(du -s -b "${deb_dir}" | cut -f1)
   installed_size=$(((pkg_size_bytes + 1023) / 1024))
   sh -c " cd '${deb_dir}'; \
       sed -i '/^Installed-Size:/!b;cInstalled-Size: ${installed_size}' DEBIAN/control"
   [ ! -d output-debs ] && mkdir -pv output-debs
   dpkg-deb -b -Znone "${deb_dir}" ../
   rm -rf ${deb_dir}
}

download_geoip

echo "Starting to build debs"
for arch in arm64 arm amd64; do
    build_v2ray_deb ${arch}
done

