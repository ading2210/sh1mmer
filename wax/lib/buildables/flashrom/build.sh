#!/usr/bin/env bash

# note: on debian, libftdi1-dev is mutually incompatible with itself for different dpkg architectures,
# you will need to reinstall the one for the arch you want to build here
echo "Cross your fingers..."

set -e

CROSS=
STRIP="strip"
PKG_CONFIG="pkg-config"
CROSSFILE=

fail() {
	printf "%b\n" "$*" >&2
	exit 1
}

cleanup() {
	[ ! -f "$CROSSFILE" ] || rm "$CROSSFILE"
	trap - EXIT INT
}

trap 'echo $BASH_COMMAND failed with exit code $?.' ERR
trap 'cleanup; exit' EXIT
trap 'echo Abort.; cleanup; exit' INT

if [ -n "$1" ]; then
	echo "Cross compiling for arch $1"
	CROSS="--host=${1}"
	STRIP="${1}-strip"
	PKG_CONFIG="${1}-pkg-config"
	CROSSFILE="$(mktemp)"
	CPU_FAMILY="$(echo "$1" | cut -d- -f1)"
	case "$CPU_FAMILY" in
		i[3-6]86) CPU_FAMILY=x86 ;;
		arm*) CPU_FAMILY=arm ;;
	esac
	(
	echo "[binaries]"
	echo "c = '${1}-gcc'"
	echo "cpp = '${1}-g++'"
	echo "ar = '${1}-ar'"
	echo "strip = '${1}-strip'"
	echo "pkgconfig = '${1}-pkg-config'"
	echo "pkg-config = '${1}-pkg-config'"
	echo ""
	echo "[host_machine]"
	echo "system = '$(echo "$1" | cut -d- -f2)'"
	echo "cpu_family = '$CPU_FAMILY'"
	echo "cpu = '$CPU_FAMILY'"
	echo "endian = 'little'"
	) >"$CROSSFILE"
	CROSSFILE="--cross-file=$CROSSFILE"
fi

"$PKG_CONFIG" --libs libftdi1 libusb-1.0 libcap zlib >/dev/null || fail "PLEASE INSTALL THESE PACKAGES BEFORE CONTINUING"

rm -rf lib
mkdir lib
LIBDIR="$(realpath lib)"

if ! [ -d libjaylink ]; then
	git clone -n https://gitlab.zapb.de/libjaylink/libjaylink
	cd libjaylink
	git checkout fa52ee261ba39f9806ac7cfa658d4f231132ab4a
	grep -rIl socket_bind | xargs sed -i 's/socket_bind/jl_socket_bind/g'
	grep -rIl socket_set_option | xargs sed -i 's/socket_set_option/jl_socket_set_option/g'
else
	cd libjaylink
	make clean
fi

./autogen.sh
./configure --prefix="$LIBDIR" --enable-static=yes --enable-shared=no "$CROSS"
make install
cd ..

if ! [ -d pciutils ]; then
	git clone -n https://github.com/pciutils/pciutils
	cd pciutils
	git checkout v3.14.0
else
	cd pciutils
	make clean
fi

if [ -z "$1" ]; then
	make install-lib DESTDIR="$LIBDIR" PREFIX=
else
	make install-lib DESTDIR="$LIBDIR" PREFIX= CROSS_COMPILE="$1"- HOST="$1"
fi
cd ..

if ! [ -d systemd ]; then
	git clone -n https://github.com/systemd/systemd
	cd systemd
	git checkout v257.6
else
	cd systemd
	rm -rf build
fi

meson setup -Dbuildtype=release -Dstatic-libudev=true -Dprefix=/ -Dc_args="-Wno-error=format-overflow" "$CROSSFILE" build
ninja -C build libudev.a devel
cp build/libudev.a "$LIBDIR/lib"
mkdir -p "$LIBDIR/lib/pkgconfig"
cp build/src/libudev/libudev.pc "$LIBDIR/lib/pkgconfig"
cd ..

if ! [ -d flashrom-repo ]; then
	git clone -n https://chromium.googlesource.com/chromiumos/third_party/flashrom flashrom-repo
	cd flashrom-repo
	git checkout 1a677e0331eb7e78169d96dbdc557b61f8f05aed
	git apply ../flashrom2.patch
else
	cd flashrom-repo
	rm -rf build
fi

export PKG_CONFIG_PATH="$LIBDIR/lib/pkgconfig"
export LIBRARY_PATH="$LIBDIR/lib"
meson setup -Dbuildtype=release -Ddefault_library=static -Dprefer_static=true -Dtests=disabled -Dprogrammer=all -Ddefault_programmer_name=internal -Dwerror=false -Dc_args="-I$LIBDIR/include" -Dc_link_args="-static -lcap -lz -L$LIBDIR/lib" "$CROSSFILE" build
ninja -C build flashrom
"$STRIP" -s build/flashrom
cp build/flashrom ..
[ ! -f "$CROSSFILE" ] || rm "$CROSSFILE"
