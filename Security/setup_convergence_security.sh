#!/bin/bash
########################################################
# Description : Setup convergence security
# Create DATE : 2026.09.07
# Last Update DATE : 2026.09.08 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2026
########################################################

SCRIPT_VER="2026.09.08.r04"

# ========================================================================================== #
# Pre install configuration
# ========================================================================================== #
set -euo pipefail

### Check virtual machine
VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || true)
if [ "$VIRT_TYPE" != "none" ] && [ -n "$VIRT_TYPE" ]
then
        echo "[ERROR] This machine is Virtual Server."
        echo "[ERROR] Virtualization: $VIRT_TYPE"
        exit 1
fi

### Check root permission
if [ "$(id -u)" -ne 0 ]
then
        echo "[ERROR] You have to execute this script with 'sudo' or 'root'."
        exit 1
fi

### Check manufacturer
MANUFACTURER=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
echo "Manufacturer: $MANUFACTURER"
echo "Product     : $PRODUCT"

case "$MANUFACTURER" in
        *HPE*|*HP*|*Hewlett-Packard*)
                VENDOR="HP"
                ;;
        *Dell*)
                VENDOR="DELL"
                ;;
        *)
                echo "[ERROR] This script supports only HP and DELL server"
                exit 1
                ;;
esac


# ========================================================================================== #
# Functions
# ========================================================================================== #
function print_summary() {
    if [ "$SUMMARY_PRINTED" -eq 1 ]; then
        return
    fi
    SUMMARY_PRINTED=1

    echo
    echo "=================================================="
    echo "[SUMMARY]"
    echo "=================================================="

    local i
    for i in {1..5}; do
        if [ -n "${STEP_MESSAGE[$i]:-}" ]; then
            printf '[%-7s] %s - %s\n' "${STEP_STATUS[$i]}" "${STEP_NAMES[$i]}" "${STEP_MESSAGE[$i]}"
        else
            printf '[%-7s] %s\n' "${STEP_STATUS[$i]}" "${STEP_NAMES[$i]}"
        fi
    done

    if [ "$FAILED_RC" -eq 0 ]; then
        echo "[FINAL] OK - 전체 작업 완료"
    else
        echo "[FINAL] FAILED - ${STEP_NAMES[$FAILED_STEP]} 실패, rc=${FAILED_RC}"
    fi
}

function exit_with_error() {
    local rc="$1"
    local msg="$2"

    FAILED_RC="$rc"
    FAILED_STEP="$CURRENT_STEP"
    STEP_STATUS[CURRENT_STEP]="FAILED"
    STEP_MESSAGE[CURRENT_STEP]="$msg"
    echo "[ERROR] $msg"
    print_summary
    exit "$rc"
}

function mark_ok() {
    local step="$1"
    local msg="$2"
    STEP_STATUS[step]="OK"
    STEP_MESSAGE[step]="$msg"
}

function mark_skipped() {
    local step="$1"
    local msg="$2"
    STEP_STATUS[step]="SKIPPED"
    STEP_MESSAGE[step]="$msg"
}

function run_cmd() {
    local rc
        if "$@"; then
                return 0
        else
        rc=$?
            exit_with_error "$rc" "Execution failed: $*"
    fi
}

function detect_rhel_major() {
        local os_major=""
        [ -r /etc/os-release ] || return 1
        source /etc/os-release
        os_major="${VERSION_ID:-}"
        [ -n "$os_major" ] || return 1
        printf '%s\n' "${os_major%%.*}"
}

# ========================================================================================== #
### Configure common variable
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

### Set to install rpm name with vendor
OS_MAJOR=$(detect_rhel_major) || exit_with_error 1 "Unable to detect OS major version."
case "$VENDOR" in
        HP)
                BMC_PACKAGE="ilorest"
                RPM_DIR="${BASE_DIR}/rpms/el${OS_MAJOR}/hp"
                CRON_SCRIPT="ilo_monitor.sh"
                ;;
        DELL)
                BMC_PACKAGE="idrac-link-monitor"
                RPM_DIR="${BASE_DIR}/rpms/el${OS_MAJOR}/dell"
                CRON_SCRIPT="idrac_monitor.sh"
                ;;
esac

RUN_SCRIPT="find_idle_ports.sh"
ILO_DIR="/root/ilo_monitor"

SRC_CRON_SCRIPT="${BASE_DIR}/${CRON_SCRIPT}"
SRC_RUN_SCRIPT="${BASE_DIR}/${RUN_SCRIPT}"

DST_CRON_SCRIPT="${ILO_DIR}/${CRON_SCRIPT}"
DST_RUN_SCRIPT="${ILO_DIR}/${RUN_SCRIPT}"

CRON_COMMENT="### Convergence Security"

STEP_NAMES=(
    ""
    "[STEP 1] Install RPMS (ilorest, ipmitool)"
    "[STEP 2] ilo_monitor - Create directory and move script files"
    "[STEP 3] Execute script now"
    "[STEP 4] Check log file"
    "[STEP 5] Register crontab"
)
STEP_STATUS=("" "PENDING" "PENDING" "PENDING" "PENDING" "PENDING")
STEP_MESSAGE=("" "" "" "" "" "")
CURRENT_STEP=0
FAILED_STEP=0
FAILED_RC=0
SUMMARY_PRINTED=0

trap 'rc=$?; if [ "$rc" -ne 0 ]; then FAILED_RC="$rc"; FAILED_STEP="$CURRENT_STEP"; STEP_STATUS[$CURRENT_STEP]="FAILED"; STEP_MESSAGE[$CURRENT_STEP]="ERROR"; print_summary; fi' EXIT

echo "==============================================================="
echo "[STEP 1] Install RPMS (ilorest, ipmitool)"
echo "==============================================================="
CURRENT_STEP=1

### Check rpm files and install
RPM_FILES=("$RPM_DIR"/*.rpm)
if [ ! -e "${RPM_FILES[0]}" ]
then
        exit_with_error 1 "No BMC RPM files: $RPM_DIR"
fi
yum install -y --disablerepo='*' "${RPM_FILES[@]}" || true

IPMITOOL_BIN=$(command -v ipmitool || true)
[ -n "$IPMITOOL_BIN" ] || exit_with_error 1 "ipmitool command not found after installation."

echo "[OK] ${BMC_PACKAGE}, ipmitool install is completed."
mark_ok 1 "${BMC_PACKAGE}, ipmitool install is completed"


echo
echo "==============================================================="
echo "[STEP 2] ilo_monitor - Create directory and move script files"
echo "==============================================================="
CURRENT_STEP=2

if [ ! -d "$ILO_DIR" ]; then
    run_cmd mkdir -p "$ILO_DIR"
    echo "[OK] Create directory completed. : ${ILO_DIR}"
else
    echo "[OK] Directory exists. : ${ILO_DIR}"
fi

if [ ! -f "$SRC_CRON_SCRIPT" ]; then
    exit_with_error 1 "There is no cron script. : $SRC_CRON_SCRIPT"
fi

if [ ! -f "$SRC_RUN_SCRIPT" ]; then
    exit_with_error 1 "There is no port_disable script. : $SRC_RUN_SCRIPT"
fi

#run_cmd cp -f "$SRC_CRON_SCRIPT" "$DST_CRON_SCRIPT"
#run_cmd cp -f "$SRC_RUN_SCRIPT" "$DST_RUN_SCRIPT"
#run_cmd chmod +x "$DST_CRON_SCRIPT"
#run_cmd chmod +x "$DST_RUN_SCRIPT"
run_cmd install -o root -g root -m 0750 "$SRC_CRON_SCRIPT" "$DST_CRON_SCRIPT"
run_cmd install -o root -g root -m 0750 "$SRC_RUN_SCRIPT" "$DST_RUN_SCRIPT"

echo "[OK] Cron script copy is completed. : $DST_CRON_SCRIPT"
echo "[OK] port_disable script copy is completed. : $DST_RUN_SCRIPT"
mark_ok 2 "Directory and script is deployed."


echo
echo "=================================================="
echo "[STEP 3] Execute script now"
echo "=================================================="
CURRENT_STEP=3

### cron script
echo "[INFO] Execute cron script : ${DST_CRON_SCRIPT}"
run_cmd "$DST_CRON_SCRIPT"

sleep 2
echo "[OK] Execute cron script is succeeded."

### port_disable script
echo "[INFO] Execute port_disable script : ${DST_RUN_SCRIPT}"
run_cmd "$DST_RUN_SCRIPT" --apply

sleep 2
echo "[OK] Execute port_disable is succeeded."

mark_ok 3 "Execute script is completed."


echo
echo "=================================================="
echo "[STEP 4] Check log file"
echo "=================================================="
CURRENT_STEP=4

LOG_FILE="/var/log/bmc_monitor.log"

if [ -s "$LOG_FILE" ]; then
    echo "[OK] Check log file is completed. : ${LOG_FILE}"
    mark_ok 4 "Check log file is completed. : ${LOG_FILE}"
else
    exit_with_error 1 "There is no log file. : ${LOG_FILE}"
fi

echo
echo "=================================================="
echo "[STEP 5] Register crontab"
echo "=================================================="
CURRENT_STEP=5

FLOCK_BIN=$(command -v flock || true)
[ -n "$FLOCK_BIN" ] ||  exit_with_error 1 "flock command is not found."

CRON_USER="root"
CRON_JOB1="* * * * * ${FLOCK_BIN} -n /var/run/bmc_monitor.lock ${DST_CRON_SCRIPT} >/dev/null 2>&1"
CRON_JOB2="* * * * * sleep 30; ${FLOCK_BIN} -n /var/run/bmc_monitor.lock ${DST_CRON_SCRIPT} >/dev/null 2>&1"
CURRENT_CRON=$(crontab -u "$CRON_USER" -l 2>/dev/null || true)

if echo "$CURRENT_CRON" | grep -Fqx "$CRON_JOB1" &&
   echo "$CURRENT_CRON" | grep -Fqx "$CRON_JOB2"; then
    echo "[SKIP] Crontab script is already registerd."
    mark_skipped 5 "Crontab script is already registerd."
elif (
        echo "$CURRENT_CRON"
        echo "$CRON_COMMENT"
        echo "$CRON_JOB1"
        echo "$CRON_JOB2"
        ) | crontab -u "$CRON_USER" -
then
        echo "[OK] Register crontab is succeeded."
        echo "[CRONTAB]"
        echo "$CRON_COMMENT"
        echo "${CRON_JOB1}"
        echo "${CRON_JOB2}"
        mark_ok 5 "Register crontab is succeeded."
else
        rc=$?
        exit_with_error "$rc" "Register crontab is failed."
fi

FAILED_RC=0
print_summary
exit 0
