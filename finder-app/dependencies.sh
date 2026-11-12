#!/bin/bash

set -euo pipefail

sudo apt-get update
sudo apt-get install -y \
    bc \
    bison \
    build-essential \
    cpio \
    curl \
    flex \
    git \
    gzip \
    libelf-dev \
    libssl-dev \
    qemu-system-arm \
    tar \
    u-boot-tools \
    xz-utils
