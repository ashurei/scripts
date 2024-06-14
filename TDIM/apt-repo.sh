#!/bin/bash
########################################################
# Description : TDIM ubuntu update repositry
# Create DATE :
# Last Update DATE : 2024.06 13 ashurei
# Copyright (c) Technical Solution, 2024
########################################################

repo_base="/home/tcore/tcore_dist/yum_repository"
apt_dir="ubuntu16.04"
repo_dir="${repo_base}/${apt_dir}"

cd ${repo_base}

# Create the package index
dpkg-scanpackages -m ${apt_dir} > ${repo_dir}/Packages
cat ${repo_dir}/Packages | gzip -9c > ${repo_dir}/Packages.gz

# Create the Release file
PKGS=$(wc -c ${repo_dir}/Packages)
PKGS_GZ=$(wc -c ${repo_dir}/Packages.gz)

cat << EOF > ${repo_dir}/Release
Architectures: all
Date: $(date -R)
MD5Sum:
 $(md5sum ${repo_dir}/Packages  | cut -d" " -f1) $PKGS
 $(md5sum ${repo_dir}/Packages.gz  | cut -d" " -f1) $PKGS_GZ
SHA1:
 $(sha1sum ${repo_dir}/Packages  | cut -d" " -f1) $PKGS
 $(sha1sum ${repo_dir}/Packages.gz  | cut -d" " -f1) $PKGS_GZ
SHA256:
 $(sha256sum ${repo_dir}/Packages | cut -d" " -f1) $PKGS
 $(sha256sum ${repo_dir}/Packages.gz | cut -d" " -f1) $PKGS_GZ

EOF
