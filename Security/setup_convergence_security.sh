#!/bin/bash
########################################################
# Description : Setup convergence security
# Create DATE : 2026.09.07
# Last Update DATE : 2026.09.07 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2026
########################################################

SCRIPT_VER="2026.09.07.r01"

# 사용법:
# sudo ./setup_convergence_security_HPE-1.0.0.sh <크론등록스크립트명> <실행스크립트명> <계정명>
#
# 예시:
# sudo ./setup_convergence_security_HPE-1.0.0.sh ilo_monitor_v3.sh find_idle_ports_v2.sh skoot
#
# 확인 기준:
# - rc=0: 전체 단계 성공
# - rc!=0: 실패. stdout 마지막의 [SUMMARY]에서 실패 단계 확인 가능

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
	*HP*|*Hewlett-Packard*)
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


### Configure common variable
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
CRON_SCRIPT="bmc_monitor.sh"
RUN_SCRIPT="find_idle_ports.sh"
ILO_DIR="/root/ilo_monitor"

SRC_CRON_SCRIPT="${BASE_DIR}/${CRON_SCRIPT}"
SRC_RUN_SCRIPT="${BASE_DIR}/${RUN_SCRIPT}"

DST_CRON_SCRIPT="${ILO_DIR}/${CRON_SCRIPT}"
DST_RUN_SCRIPT="${ILO_DIR}/${RUN_SCRIPT}"


### Set to install rpm name
if [ "$VENDOR" == "HP" ]
then
	#RPM_FILE="ilorest-3.6.0.0-45.x86_64.rpm"
	RPM_FILE=$(find "$BASE_DIR"/ -name "ilorest*rpm")
elif [ "$VENDOR" == "DELL" ]
then
	#RPM_FILE="idrac-link-monitor-1.0.5-1.el9.noarch.rpm"
	RPM_FILE=$(find "$BASE_DIR"/ -name "idrac-link-monitor*rpm")
fi

### ipmitool
#IPMITOOL_RPM_FILE_EL7="ipmitool-1.8.18-5.el7.x86_64.rpm"
#IPMITOOL_RPM_FILE_EL8="ipmitool-1.8.18-19.el8.x86_64.rpm"
#IPMITOOL_RPM_FILE_EL9="ipmitool-1.8.18-25.el9.x86_64.rpm"
#IPMITOOL_RPM_FILE=""
IPMITOOL_PACKAGE="ipmitool"

CRON_COMMENT="### Convergence Security"

STEP_NAMES=(
    "[STEP 1] Check ilorest installed"
    "[STEP 2] ilo_monitor - Create directory and move script files"
    "[STEP 3] Install ipmitool RPM"
    "[STEP 4] 실행 스크립트 즉시 수행"
    "[STEP 5] 로그 파일 확인"    
    "[STEP 6] 크론탭 등록"
)
STEP_STATUS=("PENDING" "PENDING" "PENDING" "PENDING" "PENDING" "PENDING")
STEP_MESSAGE=("" "" "" "" "" "")
CURRENT_STEP=0
FAILED_STEP=0
FAILED_RC=0
SUMMARY_PRINTED=0

# ========================================================================================== #
# Functions
# ========================================================================================== #
print_summary() {
    if [ "$SUMMARY_PRINTED" -eq 1 ]; then
        return
    fi
    SUMMARY_PRINTED=1

    echo
    echo "=================================================="
    echo "[SUMMARY]"
    echo "=================================================="

    local i
    for i in "${!STEP_NAMES[@]}"; do
        if [ -n "${STEP_MESSAGE[$i]}" ]; then
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

exit_with_error() {
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

mark_ok() {
    local step="$1"
    local msg="$2"
    STEP_STATUS[step]="OK"
    STEP_MESSAGE[step]="$msg"
}

mark_skipped() {
    local step="$1"
    local msg="$2"
    STEP_STATUS[step]="SKIPPED"
    STEP_MESSAGE[step]="$msg"
}

run_cmd() {
    local rc
    "$@"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        exit_with_error "$rc" "명령 실패: $*"
    fi
}

detect_rhel_major() {
	local os_major=""
	[ -r /etc/os-release ] || return 1
	source /etc/os-release
	os_major="${VERSION_ID:-}"
	[ -n "$os_major" ] || return 1
	printf '%s\n' "${os_major%%.*}"
}

# ========================================================================================== #
trap 'rc=$?; if [ "$rc" -ne 0 ]; then FAILED_RC="$rc"; FAILED_STEP="$CURRENT_STEP"; STEP_STATUS[$CURRENT_STEP]="FAILED"; STEP_MESSAGE[$CURRENT_STEP]="ERROR"; print_summary; fi' EXIT

echo "==============================================================="
echo "[STEP 1] Check ilorest installed"
echo "==============================================================="
CURRENT_STEP=1

# Check rpm exists
if rpm -q ilorest >/dev/null 2>&1
then
    if [ ! -f "${BASE_DIR}/${RPM_FILE}" ]; then
        exit_with_error 1 "no RPM files: ${BASE_DIR}/${RPM_FILE}"
    fi
    run_cmd yum upgrade "${BASE_DIR}/${RPM_FILE}" --disablerepo='*'
	echo "[OK] ilorest ${REQUIRED_VERSION} installed."
    mark_ok 1 "ilorest ${REQUIRED_VERSION} installed"
fi

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

run_cmd cp -f "$SRC_CRON_SCRIPT" "$DST_CRON_SCRIPT"
run_cmd cp -f "$SRC_RUN_SCRIPT}" "$DST_RUN_SCRIPT"
run_cmd chmod +x "$DST_CRON_SCRIPT"
run_cmd chmod +x "$DST_RUN_SCRIPT"

echo "[OK] Cron script copy is completed. : $DST_CRON_SCRIPT"
echo "[OK] port_disable script copy is completed. : $DST_RUN_SCRIPT"
mark_ok 2 "Directory and script is deployed."

echo
echo "=================================================="
echo "[STEP 3] Install ipmitool RPM"
echo "=================================================="
CURRENT_STEP=3

if rpm -q "$IPMITOOL_PACKAGE" >/dev/null 2>&1 || command -v ipmitool >/dev/null 2>&1; then
    OS_MAJOR=$(detect_rhel_major)
	IPMITOOL_PACKAGE="ipmitool-*.el${OS_MAJOR}.x86_64.rpm"
	IPMITOOL_BIN=$(command -v ipmitool)
	run_cmd yum upgrade "${BASE_DIR}/${IPMITOOL_PACKAGE}" --disablerepo='*'
	echo "[OK] ipmitool installed: ${IPMITOOL_BIN}"
    mark_ok 3 "ipmitool installed: ${IPMITOOL_BIN}"
fi

echo
echo "=================================================="
echo "[STEP 4] Execute script now"
echo "=================================================="
CURRENT_STEP=4

### cron script
echo "[INFO] Execute cron script : ${DST_CRON_SCRIPT}"
"$DST_CRON_SCRIPT" &
CRON_PID=$!

wait "$CRON_PID"
CRON_RESULT=$?

sleep 2

if [ "$CRON_RESULT" -ne 0 ]; then
    exit_with_error "$CRON_RESULT" "Execute cron script is failed. Error code: ${CRON_RESULT}"
fi
echo "[OK] Execute cron script is succeeded."

### port_disable script
echo "[INFO] Execute port_disable script : ${DST_RUN_SCRIPT}"
"$DST_RUN_SCRIPT" --apply &
RUN_PID=$!

wait "$RUN_PID"
RUN_RESULT=$?

sleep 2

if [ "$RUN_RESULT" -ne 0 ]; then
    exit_with_error "$RUN_RESULT" "Execute port_disable is failed, Error code: ${RUN_RESULT}"
fi
echo "[OK] Execute port_disable is succeeded."
mark_ok 5 "Execute script is completed."

echo
echo "=================================================="
echo "[STEP 5] Check log file"
echo "=================================================="
CURRENT_STEP=5

LOG_FILE="/var/log/bmc_monitor.log"

if [ -f "$LOG_FILE" ]; then
    echo "[OK] Check log file is completed. : ${LOG_FILE}"
    mark_ok 6 "Check log file is completed. : ${LOG_FILE}"
else
    exit_with_error 1 "There is no log file. : ${LOG_FILE}"
fi

echo
echo "=================================================="
echo "[STEP 6] Register crontab"
echo "=================================================="
CURRENT_STEP=6

CRON_JOB="* * * * * ${DST_CRON_SCRIPT} >/dev/null 2>&1; sleep 30; sudo ${DST_CRON_SCRIPT} >/dev/null 2>&1"
CURRENT_CRON=$(cat /var/spool/cron/root 2>/dev/null || true)

if echo "$CURRENT_CRON" | grep -F "$DST_CRON_SCRIPT" >/dev/null 2>&1; then
    echo "[SKIP] Crontab script is already registerd."
    mark_skipped 6 "Crontab script is already registerd."
else
    (
        echo "$CURRENT_CRON"
        echo "$CRON_COMMENT"
        echo "$CRON_JOB"
    ) | crontab -u "$TARGET_USER" -
    RESULT=$?

    if [ "$RESULT" -ne 0 ]; then
        exit_with_error "$RESULT" "Register crontab is failed."
    fi

    echo "[OK] Register crontab is succeeded."
    echo "      ${CRON_JOB}"
    mark_ok 7 "Register crontab is succeeded."
fi

FAILED_RC=0
print_summary
exit 0
