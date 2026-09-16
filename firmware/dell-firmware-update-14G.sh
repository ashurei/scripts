#!/bin/bash
########################################################
# Description : Upgrade DELL firmware (R640,R740)
# Create DATE : 2026.09.16
# Last Update DATE : 2026.09.16 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2026
########################################################

set -euo pipefail

### Check root permission
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] You have to execute this script with root."
    exit 1
fi

### Check product model
PRODUCT=$(< /sys/class/dmi/id/product_name)
case "$PRODUCT" in
    "PowerEdge R640"|"PowerEdge R740")
        GEN="14"
        ;;
    *)
        echo "[ERROR] Unsupported model: $PRODUCT"
        exit 1
        ;;
esac


# ========================================================= #
### Variables
BIOS="BIOS_188CW_LN64_2.28.1.BIN"
IDRAC="iDRAC-with-Lifecycle-Controller_Firmware_CPCHX_LN64_7.30.30.51_A00.BIN"
PERC_H740P="SAS-RAID_Firmware_F3J22_LN_51.16.0-4076_A16_01.BIN"
PERC_H730P="SAS-RAID_Firmware_700GG_LN_25.5.9.0001_A17_01.BIN"

WORKDIR="/tmp/dell-firmware-update"
BASE_URL="http://60.30.131.100/repos/dell"
# ========================================================= #

### Function : Run Dell DUP compatibility check
function check_firmware()
{
    local DUP_FILE="$1"
    local NAME="$2"
    local RC

    chmod +x "$DUP_FILE"
    echo "[CHECK] $NAME : $DUP_FILE"

    set +e
    "./$DUP_FILE" -c >/dev/null 2>&1
    RC=$?
    set -e

    case "$RC" in
        0|2|3)
            # 2: Applicable, reboot would be required
            # 3: Soft dependency: Same version already installed or downgrade attempted.
            return 0
            ;;
        4|5)
            # Hard dependency / qualification error
            return 1
            ;;
        *)
            echo "[WARNING] Compatibility check returned code $RC for $NAME"
            return 1
            ;;
    esac
}

### Function : Install Dell DUP firmware
function install_firmware()
{
    local DUP_FILE="$1"
    local NAME="$2"
    local RC

    echo
    echo "======================================================================================"
    echo "[UPDATE] $NAME : $DUP_FILE"
    echo "======================================================================================"

    chmod +x "$DUP_FILE"

    set +e
    "./$DUP_FILE" -q
    RC=$?
    set -e

    case "$RC" in
        0)
            echo "[SUCCESS] $NAME firmware update completed."
            ;;
        2)
            echo "[SUCCESS] $NAME firmware update completed."
            echo "[NOTICE] Reboot is required."
            ;;
        3)
            echo "[INFO] $NAME firmware was not updated."
            echo "[INFO] Same version may already be installed or downgrade was requested."
            ;;
        6)
            echo "[NOTICE] $NAME requested system reboot."
            ;;
        9)
            echo "[NOTICE] $NAME firmware update is pending."
            ;;
        1|4|5|7|8|10)
            echo "[ERROR] $NAME firmware update failed."
            echo "[ERROR] Return code: $RC"
            exit "$RC"
            ;;
        *)
            echo "[ERROR] Unknown return code: $RC"
            exit "$RC"
            ;;
    esac
}


### STEP 1 : System information
echo "======================================================================================"
echo "[STEP 1] Check Dell server information"
echo "======================================================================================"
echo "[INFO] Product    : $PRODUCT"
echo "[INFO] Generation : ${GEN}G"
echo "[INFO] BIOS       : $(< /sys/class/dmi/id/bios_version)"
echo "[INFO] BIOS Date  : $(< /sys/class/dmi/id/bios_date)"


### STEP 2 : Download firmware
echo
echo "======================================================================================"
echo "[STEP 2] Download Dell firmware files"
echo "======================================================================================"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

curl -fL --retry 3 -O "${BASE_URL}/${BIOS}"
curl -fL --retry 3 -O "${BASE_URL}/${IDRAC}"
curl -fL --retry 3 -O "${BASE_URL}/${PERC_H740P}"
curl -fL --retry 3 -O "${BASE_URL}/${PERC_H730P}"


### STEP 3 : Detect PERC using DUP compatibility check
echo
echo "======================================================================================"
echo "[STEP 3] Detect supported PERC controller"
echo "======================================================================================"

if check_firmware "$PERC_H740P" "PERC H740P"; then
    PERC="$PERC_H740P"
    PERC_NAME="PERC H740P"
    echo "[INFO] Detected compatible controller: $PERC_NAME"

elif check_firmware "$PERC_H730P" "PERC H730/H730P"; then
    PERC="$PERC_H730P"
    PERC_NAME="PERC H730/H730P"
    echo "[INFO] Detected compatible controller: $PERC_NAME"

else
    echo "[WARNING] Supported PERC controller was not detected."
    echo "[WARNING] PERC firmware update will be skipped."
    PERC=""
    PERC_NAME=""
fi


### STEP 4 : Firmware update
echo
echo "======================================================================================"
echo "[STEP 4] Upgrade Dell firmware"
echo "======================================================================================"
install_firmware "$BIOS" "System BIOS"

if [ -n "$PERC" ]; then
    install_firmware "$PERC" "$PERC_NAME"
fi

### iDRAC is intentionally updated last
install_firmware "$IDRAC" "iDRAC9"


### STEP 5 : Final notice
echo
echo "======================================================================================"
echo "[NOTICE] Firmware update commands completed."
echo "[NOTICE] Reboot the server if requested by the DUP."
echo "[NOTICE] Some firmware may require Power Off -> Power On."
echo "[NOTICE] BIOS version can be verified after reboot with:"
echo "         cat /sys/class/dmi/id/bios_version"
echo "======================================================================================"
