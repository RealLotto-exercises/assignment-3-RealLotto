#!/bin/bash
# Script to open qemu terminal.
# Author: Siddhant Jajoo.

set -euo pipefail

OUTDIR=${1:-/tmp/aeld}
if [ "$#" -gt 1 ]; then
    printf 'Usage: %s [outdir]\n' "$0" >&2
    exit 1
fi

KERNEL_IMAGE="$OUTDIR/Image"
INITRD_IMAGE="$OUTDIR/initramfs.cpio.gz"

if [ ! -f "$KERNEL_IMAGE" ]; then
    echo "Missing kernel image at $KERNEL_IMAGE" >&2
    exit 1
fi
if [ ! -f "$INITRD_IMAGE" ]; then
    echo "Missing initrd image at $INITRD_IMAGE" >&2
    exit 1
fi

echo "Booting the kernel"
# See trick at https://superuser.com/a/1412150 to route serial port output to file
qemu-system-aarch64 \
        -m 256M \
        -M virt \
        -cpu cortex-a53 \
        -nographic \
        -smp 1 \
        -kernel "$KERNEL_IMAGE" \
        -chardev "stdio,id=char0,mux=on,logfile=$OUTDIR/serial.log,signal=off" \
        -serial chardev:char0 -mon chardev=char0 \
        -append "LD_LIBRARY_PATH=/lib rdinit=/home/autorun-qemu.sh console=ttyAMA0" \
        -initrd "$INITRD_IMAGE"
