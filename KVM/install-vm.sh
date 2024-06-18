#!/bin/bash
#####################################################################
# Description : Install KVM image
# Create DATE : 2024.05.31
# Last Update DATE : 2024.06.14 by ashurei
# Copyright (c) ashurei@sk.com, 2024
#####################################################################

#NUMA node0 CPU(s):     0-21,44-65
#NUMA node1 CPU(s):     22-43,66-87

### Default Variables
IMGDIR="/kvm/img"
CPU=4
MEM=4
#SIZE=30
#BASE_IMG="/kvm/_base/Rocky-8-GenericCloud-Base-8.8-20230518.0.x86_64.qcow2"
#BASE_IMG="/kvm/_base/rhel-guest-image-7.2-20160302.0.x86_64.qcow2"
#OS_VARIANT="rhel7.9"

### argument
while [ $# -gt 0 ]
do
  case "$1" in
  -h) echo "usage) ./install_vm.sh -n [Domain name]"
      echo "                       -c [Core count]"
      echo "                       -m [RAM size(GB)]"
      echo "                       -s [Disk size(GB)]"
      echo "                       -i [Base image file path]"
      echo "                       -o [OS variant] (ex. rhel7.9, ubuntu22.04)"
      exit 0
      ;;
  -n) HOST=$2
      shift
      shift
      ;;
  -c) CPU=$2
      shift
      shift
      ;;
  -m) MEM=$2
      shift
      shift
      ;;
  -s) SIZE=$2
      shift
      shift
      ;;
  -i) BASE_IMG=$2
      shift
      shift
      ;;
  -o) OS_VARIANT=$2
      shift
      shift
      ;;
  * ) shift
      ;;
  esac
done

if [ -z "${HOST}" ]
then
  echo "(ERROR) Need hostname."
  exit 1;
fi
if [ -z "${BASE_IMG}" ]
then
  echo "(ERROR) Need base image."
  exit 1;
fi
if [ -z "${OS_VARIANT}" ]
then
  echo "(ERROR) Need os variant."
  exit 1;
fi

QCOW="${IMGDIR}/${HOST}-vda.qcow2"
RAW="${IMGDIR}/${HOST}-vda.raw"
MEM=$((MEM*1024))

### Prepare image file
echo "Process (1/4): Copy image file from base image."
#qemu-img create -f qcow2 -b "${BASE_IMG}" "${QCOW}" "${SIZE}"G
cp "${BASE_IMG}" "${QCOW}"

### Convert to raw
echo "Process (2/4): Convert to raw from qcow2."
qemu-img convert -f qcow2 -O raw "${QCOW}" "${RAW}"
#rm "${QCOW}"

### Resize disk size
echo "Process (3/4): Resize the disk size."
if [ -n "${SIZE}" ]
then
  qemu-img resize "${RAW}" "${SIZE}"G
else
  echo "Pass."
fi

### virt-install
echo "Process (4/4): virt-install"
virt-install --import \
 --name "${HOST}" \
 --vcpus "${CPU}" --cpuset=1-21,44-65 \
 --memory "${MEM}"  \
 --memorybacking hugepages=on \
 --numatune 0 \
 --disk "${RAW}",cache=none \
 --network bridge=br-bond1,model=virtio \
 --os-variant "${OS_VARIANT}" \
 --noautoconsole # --noreboot
# --network network:default \
# --network network:internal \
