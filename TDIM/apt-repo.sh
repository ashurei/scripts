#!/bin/bash
########################################################
# Description : TDIM ubuntu update repositry
# Create DATE : 2024.06.12
# Last Update DATE : 2024.06.14 ashurei
# Copyright (c) Technical Solution, 2024
########################################################

apt_dir="$1"
if [ -z "$apt_dir" ]
then
  echo "usage) ./apt-repo.sh [Repository direcetory]"
  exit 1
fi

repo_base="/home/tcore/tcore_dist/yum_repository"
repo_dir="${repo_base}/${apt_dir}"

cd ${repo_base}

# Create the package index
dpkg-scanpackages -m ${apt_dir} > ${repo_dir}/Packages
cat ${repo_dir}/Packages | gzip -9c > ${repo_dir}/Packages.gz

# Create the Release file (have to execute in target directory)
cd "$repo_dir" && PKGS=$(wc -c Packages)
cd "$repo_dir" && PKGS_GZ=$(wc -c Packages.gz)

cat << EOF > ${repo_dir}/Release
Architectures: all
Date: $(date -Ru)
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
