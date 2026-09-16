#!/bin/bash
########################################################
# Description : Upgrade HP firmware for Gen 9
# Create DATE : 2026.09.16
# Last Update DATE : 2026.09.16 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2026
########################################################

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] You have to execute this script with root."
    exit 1
fi

PRODUCT=$(cat /sys/class/dmi/id/product_name)

case "$PRODUCT" in
    "ProLiant DL380 Gen9"|"ProLiant DL360 Gen9")
        ;;
    *)
        echo "[ERROR] Unsupported model: $PRODUCT"
        exit 1
        ;;
esac


# ========================================================= #
### Variable
GEN="9"

BIOS="firmware-system-p89-3.40_2024_08_29-1.1.i386.rpm"
SMARTARRAY="firmware-smartarray-ea3138d8e8-7.20-1.1.x86_64.rpm"
ILO="firmware-ilo4-2.82-1.1.i386.rpm"
WORKDIR="/tmp/hp-firmware-update"

function install_firmware()
{
    local RPM_FILE="$1"
    local NAME="$2"
    local SETUP_PATH

    echo "======================================================================================"
    echo "[UPDATE] $NAME : $RPM_FILE"
    echo "======================================================================================"

    SETUP_PATH=$(rpm -qlp "$RPM_FILE" | grep '/setup$' | head -1)

    if [ -z "$SETUP_PATH" ]; then
        echo "[ERROR] setup executable was not found in $RPM_FILE"
        exit 1
    fi

    echo "[INFO] Install RPM: $RPM_FILE"
    rpm -Uvh --replacepkgs "$RPM_FILE"

    echo "[INFO] Execute: $SETUP_PATH -s"

    set +e
    "$SETUP_PATH" -s
    RC=$?
    set -e

    case "$RC" in
        1)
            echo "[SUCCESS] $NAME firmware update completed."
            echo "[NOTICE] Reboot is required."
            ;;
        2|3)
            echo "[INFO] $NAME firmware update was not required"
            echo "[INFO] H/W may already be current or not applicable."
            ;;
        *)
            echo "[ERROR] $NAME firmware update failed. Return code: $RC"
            ;;
    esac
}


### Download firmware from tb-ossrepo
echo
echo "======================================================================================"
echo "[STEP 2] Download firmware files from tb-ossrepo"
echo "======================================================================================"
mkdir -p "$WORKDIR" && cd "$WORKDIR"
curl -fL --retry 3 -O "http://60.30.131.100/repos/firmware/hp/gen${GEN}/${BIOS}"
curl -fL --retry 3 -O "http://60.30.131.100/repos/firmware/hp/gen${GEN}/${SMARTARRAY}"
curl -fL --retry 3 -O "http://60.30.131.100/repos/firmware/hp/gen${GEN}/${ILO}"

install_firmware "$BIOS" "System ROM P89"
install_firmware "$SMARTARRAY" "Smart Array"
install_firmware "$ILO" "iLO 4"

echo
echo "======================================================================================"
echo "[NOTICE] Firmware update completed."
echo "[NOTICE] Reboot the server to activate firmware that requires a restart."
echo "======================================================================================"
