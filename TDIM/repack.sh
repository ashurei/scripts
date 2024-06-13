#!/bin/bash
########################################################
# Description : TDIM repack package for ubuntu using zstd
# Create DATE : 2024.06.13
# Last Update DATE : 2024.06.13 by ashurei
# Copyright (c) Technical Solution, 2024
########################################################

PKG="$1"
PKG_NAME=$(echo "$PKG" | rev | cut -d"." -f2- | rev)
#echo $PKG_NAME

# https://unix.stackexchange.com/questions/669004/zst-compression-not-supported-by-apt-dpkg
# Extract files from the archive
ar x "$PKG"
# Uncompress zstd files an re-compress them using xz
zstd -d < control.tar.zst | xz > control.tar.xz
zstd -d < data.tar.zst | xz > data.tar.xz
# Re-create the Debian package
ar -m -c -a sdsd "${PKG_NAME}_repack.deb" debian-binary control.tar.xz data.tar.xz
# Clean up
rm debian-binary control.tar.xz data.tar.xz control.tar.zst data.tar.zst
