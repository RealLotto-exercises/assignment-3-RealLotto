#!/bin/bash

set -euo pipefail

OUTDIR=${1:-/tmp/aeld}
if [ "$#" -gt 1 ]; then
    printf 'Usage: %s [outdir]\n' "$0" >&2
    exit 1
fi

FINDER_APP_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ASSIGNMENT_DIR=$(cd -- "$FINDER_APP_DIR/.." && pwd -P)
KERNEL_VERSION=v5.15.163
KERNEL_TARBALL=${KERNEL_TARBALL:-"https://mirrors.edge.kernel.org/pub/linux/kernel/v5.x/linux-${KERNEL_VERSION#v}.tar.xz"}
BUSYBOX_REPO=https://git.busybox.net/busybox
BUSYBOX_VERSION=1_33_1
ARCH=arm64
CROSS_COMPILE=${CROSS_COMPILE:-aarch64-none-linux-gnu-}
TOOLCHAIN_BIN="$HOME/.local/opt/arm-gnu-toolchain-14.3.rel1-x86_64-aarch64-none-linux-gnu/bin"

if ! command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1 &&
    [ -x "$TOOLCHAIN_BIN/${CROSS_COMPILE}gcc" ]; then
    PATH="$TOOLCHAIN_BIN:$PATH"
    export PATH
fi

for command_name in git make cpio gzip wget tar "${CROSS_COMPILE}gcc" \
    "${CROSS_COMPILE}readelf"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Error: required command not found: %s\n' "$command_name" >&2
        exit 1
    fi
done

mkdir -p -- "$OUTDIR"
OUTDIR=$(cd -- "$OUTDIR" && pwd -P)
if [ "$OUTDIR" = / ]; then
    printf 'Error: outdir must not be the filesystem root.\n' >&2
    exit 1
fi

JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN)}
KERNEL_DIR="$OUTDIR/linux-stable"
BUSYBOX_DIR="$OUTDIR/busybox"
ROOTFS="$OUTDIR/rootfs"
STAGING_DIR="$OUTDIR/.rootfs-stage.$$"
INITRAMFS_TMP="$OUTDIR/.initramfs.cpio.gz.$$"
KERNEL_ARCHIVE="$OUTDIR/linux-${KERNEL_VERSION#v}.tar.xz"
SYSROOT=$("${CROSS_COMPILE}gcc" -print-sysroot)

cleanup()
{
    rm -rf -- "$STAGING_DIR"
    rm -f -- "$INITRAMFS_TMP"
}
trap cleanup EXIT

if [ -d "$KERNEL_DIR/.git" ]; then
    git -C "$KERNEL_DIR" checkout --detach "$KERNEL_VERSION"
elif [ ! -f "$KERNEL_DIR/Makefile" ]; then
    if [ -e "$KERNEL_DIR" ]; then
        if [ -z "$(find "$KERNEL_DIR" -mindepth 1 -print -quit)" ]; then
            rmdir -- "$KERNEL_DIR"
        else
            printf 'Error: %s exists but is not a usable kernel source tree.\n' \
                "$KERNEL_DIR" >&2
            exit 1
        fi
    fi
    wget --tries=5 --timeout=30 --output-document="$KERNEL_ARCHIVE" \
        "$KERNEL_TARBALL"
    if ! xz --test "$KERNEL_ARCHIVE"; then
        rm -f -- "$KERNEL_ARCHIVE"
        printf 'Error: downloaded kernel archive failed XZ integrity validation.\n' >&2
        exit 1
    fi
    tar -xJf "$KERNEL_ARCHIVE" -C "$OUTDIR"
    mv -- "$OUTDIR/linux-${KERNEL_VERSION#v}" "$KERNEL_DIR"
    rm -f -- "$KERNEL_ARCHIVE"
fi

KERNEL_VERSION_BUILT=$(make -s -C "$KERNEL_DIR" kernelversion)
if [ "$KERNEL_VERSION_BUILT" != "${KERNEL_VERSION#v}" ]; then
    printf 'Error: expected Linux %s but found %s in %s\n' \
        "${KERNEL_VERSION#v}" "$KERNEL_VERSION_BUILT" "$KERNEL_DIR" >&2
    exit 1
fi
if [ ! -f "$KERNEL_DIR/.config" ]; then
    make -C "$KERNEL_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" defconfig
fi
make -C "$KERNEL_DIR" -j"$JOBS" ARCH="$ARCH" \
    CROSS_COMPILE="$CROSS_COMPILE" Image
cp -- "$KERNEL_DIR/arch/$ARCH/boot/Image" "$OUTDIR/Image"

if [ ! -d "$BUSYBOX_DIR/.git" ]; then
    if [ -e "$BUSYBOX_DIR" ]; then
        printf 'Error: %s exists but is not a Git checkout.\n' "$BUSYBOX_DIR" >&2
        exit 1
    fi
    git clone --depth 1 --single-branch --branch "$BUSYBOX_VERSION" \
        "$BUSYBOX_REPO" "$BUSYBOX_DIR"
fi

git -C "$BUSYBOX_DIR" checkout --detach "$BUSYBOX_VERSION"
if [ ! -f "$BUSYBOX_DIR/.config" ]; then
    make -C "$BUSYBOX_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" defconfig
fi
make -C "$BUSYBOX_DIR" -j"$JOBS" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE"

mkdir -p -- "$STAGING_DIR"/{bin,dev,etc,home,lib,proc,root,sys,tmp,usr/bin,usr/sbin,var}
make -C "$BUSYBOX_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
    CONFIG_PREFIX="$STAGING_DIR" install

copy_runtime_dependencies()
{
    local executable=$1
    local interpreter dependency source destination

    interpreter=$("${CROSS_COMPILE}readelf" -l "$executable" |
        sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')
    if [ -n "$interpreter" ]; then
        source=$(find "$SYSROOT" \( -type f -o -type l \) \
            -name "${interpreter##*/}" -print -quit)
        if [ -z "$source" ]; then
            printf 'Error: cannot locate runtime loader %s under %s\n' \
                "$interpreter" "$SYSROOT" >&2
            return 1
        fi
        destination="$STAGING_DIR$interpreter"
        mkdir -p -- "$(dirname -- "$destination")"
        cp -L -- "$source" "$destination"
    fi

    while IFS= read -r dependency; do
        [ -n "$dependency" ] || continue
        source=$(find "$SYSROOT" \( -type f -o -type l \) \
            -name "$dependency" -print -quit)
        if [ -z "$source" ]; then
            printf 'Error: cannot locate runtime library %s under %s\n' \
                "$dependency" "$SYSROOT" >&2
            return 1
        fi
        mkdir -p -- "$STAGING_DIR/lib"
        cp -L -- "$source" "$STAGING_DIR/lib/$dependency"
    done < <("${CROSS_COMPILE}readelf" -d "$executable" |
        sed -n 's/.*Shared library: \[\(.*\)\].*/\1/p')
}

copy_runtime_dependencies "$STAGING_DIR/bin/busybox"

run_as_root()
{
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

if [ ! -e "$STAGING_DIR/dev/console" ]; then
    run_as_root mknod -m 600 "$STAGING_DIR/dev/console" c 5 1
fi
if [ ! -e "$STAGING_DIR/dev/null" ]; then
    run_as_root mknod -m 666 "$STAGING_DIR/dev/null" c 1 3
fi

make -C "$FINDER_APP_DIR" clean
make -C "$FINDER_APP_DIR" CROSS_COMPILE="$CROSS_COMPILE" writer
cp -- "$FINDER_APP_DIR/writer" "$STAGING_DIR/home/writer"
copy_runtime_dependencies "$STAGING_DIR/home/writer"

cp -- "$FINDER_APP_DIR/finder.sh" "$STAGING_DIR/home/finder.sh"
cp -- "$FINDER_APP_DIR/finder-test.sh" "$STAGING_DIR/home/finder-test.sh"
cp -- "$FINDER_APP_DIR/autorun-qemu.sh" "$STAGING_DIR/home/autorun-qemu.sh"
cp -R -- "$ASSIGNMENT_DIR/conf" "$STAGING_DIR/home/conf"
chmod 755 "$STAGING_DIR/home/finder.sh" \
    "$STAGING_DIR/home/finder-test.sh" "$STAGING_DIR/home/autorun-qemu.sh"

(
    cd -- "$STAGING_DIR"
    find . -print0 | cpio --null --create --format=newc --owner=0:0 |
        gzip -9
) > "$INITRAMFS_TMP"

if [ -d "$ROOTFS" ]; then
    run_as_root rm -rf -- "$ROOTFS"
fi
mv -- "$STAGING_DIR" "$ROOTFS"
mv -- "$INITRAMFS_TMP" "$OUTDIR/initramfs.cpio.gz"
trap - EXIT

printf 'Kernel image: %s/Image\n' "$OUTDIR"
printf 'Root filesystem: %s/rootfs\n' "$OUTDIR"
printf 'Initramfs: %s/initramfs.cpio.gz\n' "$OUTDIR"
