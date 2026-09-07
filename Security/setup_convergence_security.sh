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
if "$(id -u)" -ne 0 ]
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
	RPM_FILE="ilorest-3.6.0.0-45.x86_64.rpm"
else [ "$VENDOR" == "DELL" ]
then
	RPM_FILE="idrac-link-monitor-1.0.5-1.el9.noarch.rpm"
fi

### ipmitool
IPMITOOL_RPM_FILE_EL7="ipmitool-1.8.18-5.el7.x86_64.rpm"
IPMITOOL_RPM_FILE_EL8="ipmitool-1.8.18-19.el8.x86_64.rpm"
IPMITOOL_RPM_FILE_EL9="ipmitool-1.8.18-25.el9.x86_64.rpm"
IPMITOOL_RPM_FILE=""
IPMITOOL_PACKAGE="ipmitool"

CRON_COMMENT="### Convergence Security"

STEP_NAMES=(
    "STEP 1 - Check ilorest installed"
    "STEP 2 - ilo_monitor 디렉토리 생성 및 스크립트 이동"
    "STEP 3 - ipmitool RPM 설치"
    "STEP 4 - 스크립트 실행권한 부여"
    "STEP 5 - 실행 스크립트 즉시 수행"
    "STEP 6 - 로그 파일 확인"
    "STEP 7 - 크론탭 등록"
)
STEP_STATUS=("PENDING" "PENDING" "PENDING" "PENDING" "PENDING" "PENDING" "PENDING")
STEP_MESSAGE=("" "" "" "" "" "" "" "")
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
    echo "[SUMMARY] 결과 요약"
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
    STEP_STATUS[$CURRENT_STEP]="FAILED"
    STEP_MESSAGE[$CURRENT_STEP]="$msg"
    echo "[ERROR] $msg"
    print_summary
    exit "$rc"
}

mark_ok() {
    local step="$1"
    local msg="$2"
    STEP_STATUS[$step]="OK"
    STEP_MESSAGE[$step]="$msg"
}

mark_skipped() {
    local step="$1"
    local msg="$2"
    STEP_STATUS[$step]="SKIPPED"
    STEP_MESSAGE[$step]="$msg"
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

    os_major="$(rpm -E '%{rhel}' 2>/dev/null || true)"

    if [ -z "$os_major" ] || [ "$os_major" = "%{rhel}" ]; then
        if [ -r /etc/os-release ]; then
            os_major="$(
                . /etc/os-release
                printf '%s' "${VERSION_ID:-}"
            )"
            os_major="${os_major%%.*}"
        fi
    fi

    printf '%s
' "$os_major"
}

select_ipmitool_rpm() {
    local os_major="$1"

    case "$os_major" in
        7)
            IPMITOOL_RPM_FILE="$IPMITOOL_RPM_FILE_EL7"
            ;;
        8)
            IPMITOOL_RPM_FILE="$IPMITOOL_RPM_FILE_EL8"
            ;;
        9)
            IPMITOOL_RPM_FILE="$IPMITOOL_RPM_FILE_EL9"
            ;;
        *)
            exit_with_error 1 "지원하지 않는 OS 버전: ${os_major:-unknown} (지원: 7, 8, 9)"
            ;;
    esac
}

# ========================================================================================== #
trap 'rc=$?; if [ "$rc" -ne 0 ]; then FAILED_RC="$rc"; FAILED_STEP="$CURRENT_STEP"; STEP_STATUS[$CURRENT_STEP]="FAILED"; STEP_MESSAGE[$CURRENT_STEP]="ERROR"; print_summary; fi' EXIT

echo "=================================================="
echo "[STEP 1] Check ilorest installed"
echo "=================================================="
CURRENT_STEP=1

if rpm -q ilorest >/dev/null 2>&1; then
    INSTALLED_VERSION=$(rpm -q ilorest --queryformat '%{VERSION}\n') || exit_with_error $? "ilorest 버전 확인 실패"
    echo "[INFO] 현재 설치 버전: ${INSTALLED_VERSION}"

    if [[ "$INSTALLED_VERSION" == ${REQUIRED_VERSION}* ]]; then
        echo "[OK] ilorest ${REQUIRED_VERSION} 버전 이미 설치됨 - 스킵"
        mark_skipped 1 "ilorest ${INSTALLED_VERSION} 이미 설치됨"
    else
        echo "[WARN] 다른 버전 설치됨 - 삭제 후 재설치"
        if [ ! -f "${BASE_DIR}/${RPM_FILE}" ]; then
            exit_with_error 1 "RPM 파일 없음: ${BASE_DIR}/${RPM_FILE}"
        fi
        run_cmd rpm -e ilorest
        echo "[INFO] 기존 버전 삭제 완료"
        run_cmd rpm -ivh "${BASE_DIR}/${RPM_FILE}"
        echo "[OK] ilorest ${REQUIRED_VERSION} 설치 완료"
        mark_ok 1 "ilorest ${REQUIRED_VERSION} 재설치 완료"
    fi
else
    echo "[INFO] ilorest 미설치 상태 - 신규 설치"
    if [ ! -f "${BASE_DIR}/${RPM_FILE}" ]; then
        exit_with_error 1 "RPM 파일 없음: ${BASE_DIR}/${RPM_FILE}"
    fi
    run_cmd rpm -ivh "${BASE_DIR}/${RPM_FILE}"
    echo "[OK] ilorest ${REQUIRED_VERSION} 설치 완료"
    mark_ok 1 "ilorest ${REQUIRED_VERSION} 신규 설치 완료"
fi

echo
echo "=================================================="
echo "[STEP 2] ilo_monitor 디렉토리 생성 및 스크립트 이동"
echo "=================================================="
CURRENT_STEP=2

if [ ! -d "$ILO_DIR" ]; then
    run_cmd mkdir -p "$ILO_DIR"
    echo "[OK] 디렉토리 생성 완료: ${ILO_DIR}"
else
    echo "[OK] 디렉토리 이미 존재: ${ILO_DIR}"
fi

if [ ! -f "$SRC_CRON_SCRIPT" ]; then
    exit_with_error 1 "크론 등록용 원본 스크립트 없음: ${SRC_CRON_SCRIPT}"
fi

if [ ! -f "$SRC_RUN_SCRIPT" ]; then
    exit_with_error 1 "실행용 원본 스크립트 없음: ${SRC_RUN_SCRIPT}"
fi

run_cmd cp -f "$SRC_CRON_SCRIPT" "$DST_CRON_SCRIPT"
run_cmd cp -f "$SRC_RUN_SCRIPT" "$DST_RUN_SCRIPT"
run_cmd chown "$TARGET_USER":"$TARGET_USER" "$ILO_DIR" "$DST_CRON_SCRIPT" "$DST_RUN_SCRIPT"

echo "[OK] 크론 등록용 스크립트 복사 완료: ${DST_CRON_SCRIPT}"
echo "[OK] 실행용 스크립트 복사 완료: ${DST_RUN_SCRIPT}"
mark_ok 2 "디렉토리 및 스크립트 배치 완료"

echo
echo "=================================================="
echo "[STEP 3] ipmitool RPM 설치"
echo "=================================================="
CURRENT_STEP=3

if rpm -q "$IPMITOOL_PACKAGE" >/dev/null 2>&1 || command -v ipmitool >/dev/null 2>&1; then
    if rpm -q "$IPMITOOL_PACKAGE" >/dev/null 2>&1; then
        IPMITOOL_INSTALLED_VERSION=$(rpm -q \
            --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' \
            "$IPMITOOL_PACKAGE") \
            || exit_with_error $? "ipmitool 버전 확인 실패"

        echo "[OK] ipmitool 이미 설치됨 - 스킵: ${IPMITOOL_INSTALLED_VERSION}"
        mark_skipped 3 "ipmitool ${IPMITOOL_INSTALLED_VERSION} 이미 설치됨"
    else
        IPMITOOL_BIN=$(command -v ipmitool)
        echo "[OK] ipmitool 실행 파일 이미 존재 - 스킵: ${IPMITOOL_BIN}"
        mark_skipped 3 "ipmitool 실행 파일 이미 존재: ${IPMITOOL_BIN}"
    fi
else
    echo "[INFO] ipmitool 미설치 상태 - 신규 설치"

    OS_MAJOR=$(detect_rhel_major)
    select_ipmitool_rpm "$OS_MAJOR"

    echo "[INFO] OS 메이저 버전: ${OS_MAJOR}"
    echo "[INFO] 선택된 ipmitool RPM: ${IPMITOOL_RPM_FILE}"

    if [ ! -f "${BASE_DIR}/${IPMITOOL_RPM_FILE}" ]; then
        exit_with_error 1 "RPM 파일 없음: ${BASE_DIR}/${IPMITOOL_RPM_FILE}"
    fi

    IPMITOOL_RPM_VERSION=$(rpm -qp \
        --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' \
        "${BASE_DIR}/${IPMITOOL_RPM_FILE}") \
        || exit_with_error $? "ipmitool RPM 버전 확인 실패"

    echo "[INFO] ipmitool RPM 파일 버전: ${IPMITOOL_RPM_VERSION}"

    run_cmd rpm -ivh "${BASE_DIR}/${IPMITOOL_RPM_FILE}"

    if ! rpm -q "$IPMITOOL_PACKAGE" >/dev/null 2>&1 && ! command -v ipmitool >/dev/null 2>&1; then
        exit_with_error 1 "ipmitool 설치 후 확인 실패"
    fi

    if rpm -q "$IPMITOOL_PACKAGE" >/dev/null 2>&1; then
        IPMITOOL_INSTALLED_VERSION=$(rpm -q \
            --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' \
            "$IPMITOOL_PACKAGE") \
            || exit_with_error $? "ipmitool 버전 확인 실패"
        echo "[OK] ipmitool 설치 완료: ${IPMITOOL_INSTALLED_VERSION}"
        mark_ok 3 "ipmitool ${IPMITOOL_INSTALLED_VERSION} 신규 설치 완료"
    else
        IPMITOOL_BIN=$(command -v ipmitool)
        echo "[OK] ipmitool 설치 완료: ${IPMITOOL_BIN}"
        mark_ok 3 "ipmitool 실행 파일 확인 완료: ${IPMITOOL_BIN}"
    fi
fi

echo
echo "=================================================="
echo "[STEP 4] 스크립트 실행권한 부여"
echo "=================================================="
CURRENT_STEP=4

run_cmd chmod +x "$DST_CRON_SCRIPT"
run_cmd chmod +x "$DST_RUN_SCRIPT"

echo "[OK] chmod +x 완료: ${DST_CRON_SCRIPT}"
echo "[OK] chmod +x 완료: ${DST_RUN_SCRIPT}"
mark_ok 4 "실행권한 부여 완료"

echo
echo "=================================================="
echo "[STEP 5] 실행 스크립트 즉시 수행"
echo "=================================================="
CURRENT_STEP=5

echo "[INFO] 크론 등록용 스크립트 사전 수행: ${DST_CRON_SCRIPT}"
sudo -u "$TARGET_USER" "$DST_CRON_SCRIPT" &
CRON_PID=$!

wait "$CRON_PID"
CRON_RESULT=$?

sleep 2

if [ "$CRON_RESULT" -ne 0 ]; then
    exit_with_error "$CRON_RESULT" "크론 등록용 스크립트 수행 실패, 종료코드: ${CRON_RESULT}"
fi

echo "[OK] 크론 등록용 스크립트 수행 성공"

echo "[INFO] 실행용 스크립트 수행: ${DST_RUN_SCRIPT}"
sudo -u "$TARGET_USER" "$DST_RUN_SCRIPT" --apply &
RUN_PID=$!

wait "$RUN_PID"
RUN_RESULT=$?

sleep 2

if [ "$RUN_RESULT" -ne 0 ]; then
    exit_with_error "$RUN_RESULT" "실행 스크립트 수행 실패, 종료코드: ${RUN_RESULT}"
fi

echo "[OK] 실행 스크립트 수행 성공"
mark_ok 5 "크론 등록/실행 스크립트 수행 성공"

echo
echo "=================================================="
echo "[STEP 6] 로그 파일 확인"
echo "=================================================="
CURRENT_STEP=6

LOG_FILE="/var/log/bmc_monitor.log"

if [ -f "$LOG_FILE" ]; then
    echo "[OK] 로그 파일 확인 완료: ${LOG_FILE}"
    mark_ok 6 "로그 파일 확인 완료: ${LOG_FILE}"
else
    exit_with_error 1 "로그 파일 없음: ${LOG_FILE}"
fi

echo
echo "=================================================="
echo "[STEP 7] 크론탭 등록"
echo "=================================================="
CURRENT_STEP=7

CRON_JOB="* * * * * sudo ${DST_CRON_SCRIPT} >/dev/null 2>&1; sleep 30; sudo ${DST_CRON_SCRIPT} >/dev/null 2>&1"
CURRENT_CRON=$(crontab -u "$TARGET_USER" -l 2>/dev/null || true)

if echo "$CURRENT_CRON" | grep -F "$DST_CRON_SCRIPT" >/dev/null 2>&1; then
    echo "[OK] 이미 크론탭 등록되어 있음 - 스킵"
    mark_skipped 7 "이미 등록되어 있음"
else
    (
        echo "$CURRENT_CRON"
        echo "$CRON_COMMENT"
        echo "$CRON_JOB"
    ) | crontab -u "$TARGET_USER" -
    RESULT=$?

    if [ "$RESULT" -ne 0 ]; then
        exit_with_error "$RESULT" "크론탭 등록 실패"
    fi

    echo "[OK] 크론탭 등록 완료"
    echo "      ${CRON_JOB}"
    mark_ok 7 "크론탭 등록 완료"
fi

FAILED_RC=0
print_summary
exit 0
