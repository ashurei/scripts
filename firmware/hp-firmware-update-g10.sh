#!/bin/bash
########################################################
# Description : Upgrade HP firmware
# Create DATE : 2026.09.16
# Last Update DATE : 2026.09.16 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2026
########################################################

set -euo pipefail

### Check root permission
if [ "$(id -u)" -ne 0 ]
then
    echo "[ERROR] You have to execute this script with 'sudo' or 'root'."
    exit 1
fi


# ========================================================= #
### Variable
GEN="10"

PRODUCT=$(cat /sys/class/dmi/id/product_name)
case "$PRODUCT" in
        "ProLiant DL380 Gen10")
                BIOS="U30_3.70_08_19_2026.fwpkg"
                ;;
        "ProLiant DL360 Gen10")
                BIOS="U32_3.70_08_19_2026.fwpkg"
                ;;
        *)
                echo "[ERROR] Unsupported model: $PRODUCT"
                exit 1
        ;;
esac

WORKDIR="/tmp/hp-firmware-update"
INNOVATION="IEGen10_0.2.3.0.fwpkg"
SPS="SPSGen10_04.01.05.312.fwpkg"
SMARTARRAY="HPE_SR_Gen10_8.23_A.fwpkg"
ILO="ilo5_321.fwpkg"
# ========================================================= #


### Install ilorest from tb-ossrepo
echo "======================================================================================"
echo "[STEP 1] Install ilorest with dnf(yum) from tb-ossrepo"
echo "======================================================================================"
if command -v dnf >/dev/null 2>&1;then
    dnf install -y ilorest
elif command -v yum >/dev/null 2>&1;then
    yum install -y ilorest
else
    echo "[ERROR] dnf/yum is not found."
    exit 1
fi

### Download firmware from tb-ossrepo
echo
echo "======================================================================================"
echo "[STEP 2] Download firmware files from tb-ossrepo"
echo "======================================================================================"
mkdir -p "$WORKDIR" && cd "$WORKDIR"
curl -fL --retry 3 -O "http://60.30.131.100/repos/hp/gen${GEN}/${BIOS}"
curl -fL --retry 3 -O "http://60.30.131.100/repos/hp/gen${GEN}/${INNOVATION}"
curl -fL --retry 3 -O "http://60.30.131.100/repos/hp/gen${GEN}/${SPS}"
curl -fL --retry 3 -O "http://60.30.131.100/repos/hp/gen${GEN}/${SMARTARRAY}"
curl -fL --retry 3 -O "http://60.30.131.100/repos/hp/gen${GEN}/${ILO}"

### Check before firmware version
echo
echo "======================================================================================"
echo "[STEP 3] Check before firmware version"
echo "======================================================================================"
ilorest serverinfo --firmware | grep -E "^System ROM|^Server Platform Services|^iLO|^HPE Smart Array|^Innovation Engine"

### Upgrade firmware
echo
echo "======================================================================================"
echo "[STEP 4] Upgrade firmware"
echo "======================================================================================"
echo "[UPDATE] System ROM       : $BIOS"
echo "+------------------------------------------------------------------------------------+"
ilorest flashfwpkg "$BIOS"
echo "+------------------------------------------------------------------------------------+"
echo "[UPDATE] Innovation Engine: $INNOVATION"
echo "+------------------------------------------------------------------------------------+"
ilorest flashfwpkg "$INNOVATION"
echo "+------------------------------------------------------------------------------------+"
echo "[UPDATE] SPS              : $SPS"
echo "+------------------------------------------------------------------------------------+"
ilorest flashfwpkg "$SPS"
echo "+------------------------------------------------------------------------------------+"
echo "[UPDATE] Smart Array      : $SMARTARRAY"
echo "+------------------------------------------------------------------------------------+"
ilorest flashfwpkg "$SMARTARRAY"
echo "+------------------------------------------------------------------------------------+"
echo "[UPDATE] iLO              : $ILO"
echo "+------------------------------------------------------------------------------------+"
ilorest flashfwpkg "$ILO"

### Need to REBOOT this server.
echo
echo "======================================================================================"
echo "[NOTICE] Firmware update packages have been staged."
echo "[NOTICE] Power off and power on this server to complete firmware activation."
echo "[NOTICE] Boot time may be longer than usual during firmware update."
echo "======================================================================================"
