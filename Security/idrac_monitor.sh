#!/bin/bash

# iLO 모니터링 스크립트
# 파일명: idrac_monitor.sh
# 버젼: v12 2026.10.12
# 기능: iDRAC 로그 모니터링, 상태 감지, 자동 정리, 성능 측정

SCRIPT_NAME="bmc_monitor"
MONITOR_TYPE="idrac"
RACADM="/opt/dell/srvadmin/sbin/racadm"
LOG_DIR="/var/log"
STATE_DIR="/var/lib"
TEMP_DIR="/tmp"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"
ALERT_LOG="${LOG_DIR}/${SCRIPT_NAME}_alerts.log"
PERF_LOG="${LOG_DIR}/${SCRIPT_NAME}_performance.log"
SEQ_STATE_FILE="${STATE_DIR}/${SCRIPT_NAME}_${MONITOR_TYPE}_last_seq"
LINK_STATE_FILE="${STATE_DIR}/${SCRIPT_NAME}_${MONITOR_TYPE}_link_state"
LINK_MONITOR_LOG="${LOG_DIR}/idrac_link_monitor_alerts.log"
LINK_MONITOR_OFFSET_FILE="${STATE_DIR}/${SCRIPT_NAME}_${MONITOR_TYPE}_link_monitor_log_offset"
HEALTH_STATE_FILE="${STATE_DIR}/${SCRIPT_NAME}_${MONITOR_TYPE}_health_state"
LOCK_FILE="${TEMP_DIR}/${SCRIPT_NAME}_${MONITOR_TYPE}.lock"

MAX_LOG_SIZE=5242880          # 5MB
LOG_RETENTION_DAYS=30
MAX_LOG_BACKUPS=10
LOG_BACKUP_COMPRESS=true

TIMEOUT_SECONDS=30
MAX_CONSECUTIVE_FAILURES=3
LCLOG_FETCH_LIMIT=500
DEBUG_MODE="false"

ENABLE_SEL_CHECK=true
SEL_CLEANUP_THRESHOLD=200
ENABLE_SEL_CLEANUP=false

acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            echo "Another instance is already running (PID: $lock_pid)" >&2
            exit 106
        else
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

release_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)

        if [ "$lock_pid" = "$$" ]; then
            rm -f "$LOCK_FILE"
        fi
    fi
}

trap release_lock EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

log_rotation_message() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)

    # rotate/cleanup 내부에서 쓰는 보조 로그 함수.
    # log_message()를 호출하지 않는다. 재귀 rotate 방지 목적.
    echo "[$timestamp] $message" >> "$LOG_FILE" 2>/dev/null || true

	if [ "$DEBUG_MODE" = "true" ]; then
        echo "[$timestamp] $message"
    fi

    return 0
}

cleanup_old_log_backups() {
    local logdir="$1"
    local logname="$2"

    # 1. 날짜 기준 정리
    local deleted_by_date
    deleted_by_date=$(find "$logdir" -name "${logname}.*" -type f -mtime +$LOG_RETENTION_DAYS 2>/dev/null | wc -l)

    find "$logdir" -name "${logname}.*" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null

    if [ "$deleted_by_date" -gt 0 ]; then
        log_rotation_message "Log backup cleanup by age: deleted ${deleted_by_date} files older than ${LOG_RETENTION_DAYS} days"
    fi

    # 2. 개수 기준 정리
    local current_backups
    current_backups=$(find "$logdir" -name "${logname}.*" -type f 2>/dev/null | wc -l)

    if [ "$current_backups" -gt "$MAX_LOG_BACKUPS" ]; then
        local excess_count
        excess_count=$((current_backups - MAX_LOG_BACKUPS))

        find "$logdir" -name "${logname}.*" -type f -printf '%T@ %p\n' 2>/dev/null | \
        sort -n | head -"$excess_count" | cut -d' ' -f2- | \
        while IFS= read -r file; do
            rm -f "$file"
            log_rotation_message "Log backup cleanup by count: deleted $(basename "$file")"
        done
    fi
}

rotate_log_error() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)

    # rotate_log() 안에서 log_message()를 부르면 재귀 rotate가 생길 수 있으므로 직접 기록한다.
    if [ -n "$LOG_FILE" ]; then
        echo "[$timestamp] ERROR: $message" >> "$LOG_FILE" 2>/dev/null || true
    fi

	if [ "$DEBUG_MODE" = "true" ]; then
        echo "[$timestamp] ERROR: $message" >&2
    fi

    return 0
}

rotate_log() {
    local logfile="$1"

    [ ! -f "$logfile" ] && return 0

    local size
    size=$(stat -c%s "$logfile" 2>/dev/null || stat -f%z "$logfile" 2>/dev/null || echo 0)

    [ "$size" -le "$MAX_LOG_SIZE" ] && return 0

    local logdir logname timestamp backup_file final_backup_file
    logdir=$(dirname "$logfile")
    logname=$(basename "$logfile")

    # 같은 초에 여러 번 rotate되어도 파일명이 겹치지 않도록 PID를 붙인다.
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_file="${logdir}/${logname}.${timestamp}.$$"

    if [ "$LOG_BACKUP_COMPRESS" = "true" ] && command -v gzip >/dev/null 2>&1; then
        final_backup_file="${backup_file}.gz"

        if ! gzip -c "$logfile" > "$final_backup_file" 2>/dev/null; then
            rm -f "$final_backup_file" 2>/dev/null
            rotate_log_error "log rotation backup failed: gzip $logfile -> $final_backup_file"
            return 1
        fi
    else
        final_backup_file="$backup_file"

        if ! cp "$logfile" "$final_backup_file" 2>/dev/null; then
            rm -f "$final_backup_file" 2>/dev/null
            rotate_log_error "log rotation backup failed: cp $logfile -> $final_backup_file"
            return 1
        fi
    fi

    # 백업 파일이 실제로 생성되고 비어 있지 않은 경우에만 원본 truncate.
    if [ ! -s "$final_backup_file" ]; then
        rotate_log_error "log rotation backup file is empty or missing: $final_backup_file"
        rm -f "$final_backup_file" 2>/dev/null
        return 1
    fi

    if ! : > "$logfile" 2>/dev/null; then
        rotate_log_error "log rotation truncate failed: $logfile"
        return 1
    fi

    cleanup_old_log_backups "$logdir" "$logname"
    return 0
}

log_message() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    rotate_log "$LOG_FILE"
    echo "[$timestamp] $message" >> "$LOG_FILE"
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "[$timestamp] $message"
    fi

    return 0
}

send_alert() {
    local code="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
    local alert_text="CODE=${code} ALERT: ${message}"
    log_message "$alert_text"
    rotate_log "$ALERT_LOG"
    echo "[$timestamp] $alert_text" >> "$ALERT_LOG"
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "[$timestamp] $alert_text"
    fi

    if command -v logger >/dev/null 2>&1; then
        logger -t "$SCRIPT_NAME" "$alert_text"
    fi
	
	return 0
}

get_timestamp_ms() {
    date +%s%3N 2>/dev/null || date +%s000
}

format_duration() {
    local duration_ms="$1"
    local duration_s=$((duration_ms / 1000))
    local ms_part=$((duration_ms % 1000))
    if [ "$duration_s" -gt 0 ]; then
        echo "${duration_s}.${ms_part}s"
    else
        echo "${duration_ms}ms"
    fi
}

log_performance() {
    local operation="$1"
    local duration_ms="$2"
    local status="$3"
    local details="$4"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    rotate_log "$PERF_LOG"
    echo "[$timestamp] $operation: $(format_duration "$duration_ms") - $status $details" >> "$PERF_LOG"
	if [ "$DEBUG_MODE" = "true" ]; then
        echo "PERF: $operation took $(format_duration "$duration_ms") - $status"
    fi

    return 0
}

run_racadm() {
    if [ "$TIMEOUT_SECONDS" -gt 0 ] && command -v timeout >/dev/null 2>&1; then
        timeout "$TIMEOUT_SECONDS" "$RACADM" "$@"
    else
        "$RACADM" "$@"
    fi
}

get_last_seq() {
    [ -f "$SEQ_STATE_FILE" ] && cat "$SEQ_STATE_FILE" 2>/dev/null || echo "0"
}

save_last_seq() {
    echo "$1" > "$SEQ_STATE_FILE"
}


get_link_monitor_log_offset() {
    [ -f "$LINK_MONITOR_OFFSET_FILE" ] && cat "$LINK_MONITOR_OFFSET_FILE" 2>/dev/null || echo "0"
}

save_link_monitor_log_offset() {
    echo "$1" > "$LINK_MONITOR_OFFSET_FILE"
}

extract_status_from_link_monitor_line() {
    local line="$1"
    local status=""

    case "$line" in
        *"CODE=BMC-NET-002"*|*"iDRAC network link UP"*)
            status="UP"
            ;;
        *"CODE=BMC-NET-003"*|*"iDRAC network link DOWN"*)
            status="DOWN"
            ;;
        *"CODE=BMC-NET-004"*|*"iDRAC network link state changed"*)
            status=$(printf '%s\n' "$line" | sed -nE 's/.*->[[:space:]]*([A-Za-z_ -]+).*/\1/p' | awk '{print $1}' | tr '[:lower:]' '[:upper:]')
            ;;
        *"Initial BMC LinkStatus saved:"*|*"Initial BMC LinkStatus baseline saved:"*)
            status=$(printf '%s\n' "$line" | sed -nE 's/.*Initial BMC LinkStatus (saved|baseline saved):[[:space:]]*([A-Za-z_ -]+).*/\2/p' | awk '{print $1}' | tr '[:lower:]' '[:upper:]')
            ;;
        *"No BMC LinkStatus change:"*)
            status=$(printf '%s\n' "$line" | sed -nE 's/.*No BMC LinkStatus change:[[:space:]]*([A-Za-z_ -]+).*/\1/p' | awk '{print $1}' | tr '[:lower:]' '[:upper:]')
            ;;
    esac

    normalize_link_status "$status"
}

check_link_monitor_log_change() {
    [ -r "$LINK_MONITOR_LOG" ] || return 1

    local last_line total_lines start_line current previous line status event_seen=false
    last_line=$(get_link_monitor_log_offset)
    total_lines=$(wc -l < "$LINK_MONITOR_LOG" 2>/dev/null || echo 0)

    if ! printf '%s' "$last_line" | grep -Eq '^[0-9]+$'; then
        last_line=0
    fi
    if ! printf '%s' "$total_lines" | grep -Eq '^[0-9]+$'; then
        total_lines=0
    fi

    # Log rotation or truncation detected.
    if [ "$total_lines" -lt "$last_line" ]; then
        last_line=0
    fi

    [ "$total_lines" -gt "$last_line" ] || return 1

    previous=$(get_last_link_state)
    current="$previous"
    start_line=$((last_line + 1))

    while IFS= read -r line || [ -n "$line" ]; do
        status=$(extract_status_from_link_monitor_line "$line")
        [ -z "$status" ] || [ "$status" = "UNKNOWN" ] && continue

        event_seen=true
        current="$status"

        if printf '%s\n' "$line" | grep -Eq 'CODE=BMC-NET-002|CODE=BMC-NET-003|CODE=BMC-NET-004'; then
            if [ "$previous" = "UNKNOWN" ]; then
                log_message "LinkMonitor event detected: current=$current, source=$LINK_MONITOR_LOG"
            elif [ "$current" != "$previous" ]; then
                log_message "LinkMonitor event detected: $previous -> $current, source=$LINK_MONITOR_LOG"
            else
                log_message "LinkMonitor event detected without state change: $current, source=$LINK_MONITOR_LOG"
            fi

            # Re-emit LinkMonitor alerts into bmc_monitor_alerts.log.
            # This keeps the integrated BMC alert log in sync with
            # idrac_link_monitor_alerts.log while avoiding unsupported UNKNOWN entries.
            if [ "$current" = "UP" ]; then
                send_alert "BMC-NET-002" "iDRAC network link UP (previous state: $previous) [source: idrac_link_monitor_alerts]"
            elif [ "$current" = "DOWN" ]; then
                send_alert "BMC-NET-003" "iDRAC network link DOWN (previous state: $previous) [source: idrac_link_monitor_alerts]"
            else
                send_alert "BMC-NET-004" "iDRAC network link state changed - $previous -> $current [source: idrac_link_monitor_alerts]"
            fi

            previous="$current"
        fi
    done <<EOF_LINK_MONITOR_LOG
$(sed -n "${start_line},${total_lines}p" "$LINK_MONITOR_LOG" 2>/dev/null)
EOF_LINK_MONITOR_LOG

    save_link_monitor_log_offset "$total_lines"

    if [ "$event_seen" = "true" ]; then
        save_last_link_state "$current"
        log_message "BMC LinkStatus synchronized from LinkMonitor log: $current"
        return 0
    fi

    return 1
}

get_last_link_state() {
    [ -f "$LINK_STATE_FILE" ] && cat "$LINK_STATE_FILE" 2>/dev/null || echo "UNKNOWN"
}

save_last_link_state() {
    echo "$1" > "$LINK_STATE_FILE"
}

get_failure_count() {
    if [ -f "$HEALTH_STATE_FILE" ]; then
        grep '^failure_count=' "$HEALTH_STATE_FILE" 2>/dev/null | cut -d'=' -f2
    else
        echo "0"
    fi
}

save_failure_count() {
    local count="$1"
    if [ -f "$HEALTH_STATE_FILE" ]; then
        sed -i "s/^failure_count=.*/failure_count=$count/" "$HEALTH_STATE_FILE" 2>/dev/null || echo "failure_count=$count" >> "$HEALTH_STATE_FILE"
    else
        echo "failure_count=$count" > "$HEALTH_STATE_FILE"
    fi
}

get_last_success_time() {
    if [ -f "$HEALTH_STATE_FILE" ]; then
        grep '^last_success=' "$HEALTH_STATE_FILE" 2>/dev/null | cut -d'=' -f2
    else
        echo "0"
    fi
}

save_last_success_time() {
    local ts="$1"
    if [ -f "$HEALTH_STATE_FILE" ]; then
        sed -i "s/^last_success=.*/last_success=$ts/" "$HEALTH_STATE_FILE" 2>/dev/null || echo "last_success=$ts" >> "$HEALTH_STATE_FILE"
    else
        printf 'last_success=%s\n' "$ts" > "$HEALTH_STATE_FILE"
    fi
}

check_idrac_communication_health() {
    local success="$1"
    local current_time
    current_time=$(date +%s)
    local failure_count
    failure_count=$(get_failure_count)

    if [ "$success" = "true" ]; then
        save_failure_count "0"
        save_last_success_time "$current_time"
        log_message "iDRAC communication healthy"
    else
        failure_count=$((failure_count + 1))
        save_failure_count "$failure_count"
        log_message "BMC communication failed (consecutive failures: $failure_count)"
        if [ "$failure_count" -ge "$MAX_CONSECUTIVE_FAILURES" ]; then
            send_alert "BMC-COMM-001" "iDRAC communication outage - $failure_count consecutive failures"
        fi
    fi
}

parse_field() {
    local line="$1"
    local key="$2"
    printf '%s\n' "$line" | sed 's/^[[:space:]]*//' | grep -E "^${key}[[:space:]]*=" | sed -E "s/^${key}[[:space:]]*=[[:space:]]*//"
}

normalize_link_status() {
    local raw="$1"
    local lower
    lower=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        *up*|*linkup*|*connected*) echo "UP" ;;
        *down*|*linkdown*|*disconnected*) echo "DOWN" ;;
        "") echo "UNKNOWN" ;;
        *) echo "$raw" ;;
    esac
}

get_current_link_status() {
    local out line status
    out=$(run_racadm get iDRAC.NIC.LinkStatus 2>/dev/null || true)
    line=$(printf '%s\n' "$out" | grep -i 'LinkStatus' | head -1)
    status=$(printf '%s\n' "$line" | awk -F= '{print $2}' | xargs)
    normalize_link_status "$status"
}

check_link_status_change() {
    local current previous

    # Prefer the dedicated idrac_link_monitor daemon log when it has new
    # CODE=BMC-NET-* events. If there is no new usable log entry, fall back
    # to direct RACADM LinkStatus lookup.
    if check_link_monitor_log_change; then
        return 0
    fi

    current=$(get_current_link_status)
    previous=$(get_last_link_state)

    if [ "$current" = "UNKNOWN" ]; then
        log_message "BMC LinkStatus lookup failed or is unsupported"
        return 1
    fi

    if [ "$previous" = "UNKNOWN" ]; then
        save_last_link_state "$current"
        log_message "Initial BMC LinkStatus saved: $current"
        return 0
    fi

    if [ "$current" != "$previous" ]; then
        if [ "$current" = "UP" ]; then
            send_alert "BMC-NET-002" "iDRAC network link UP (previous state: $previous)"
        elif [ "$current" = "DOWN" ]; then
            send_alert "BMC-NET-003" "iDRAC network link DOWN (previous state: $previous)"
        else
            send_alert "BMC-NET-004" "iDRAC network link state changed - $previous -> $current"
        fi
        save_last_link_state "$current"
    else
        log_message "No BMC LinkStatus change: $current"
    fi

    return 0
}

analyze_idrac_health() {
    local message="$1"
    local timestamp="$2"
    local severity="$3"
    local seq="$4"
    local msg_lower
    msg_lower=$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')

    if echo "$msg_lower" | grep -Eq 'watchdog'; then
        send_alert "BMC-HW-001" "iDRAC watchdog reset detected - controller restarted due to an abnormal state ($timestamp) [SeqNumber: $seq]"
        return 0
    fi

    if echo "$msg_lower" | grep -Eq 'self test error|self-test failed|hardware self test'; then
        send_alert "BMC-HW-002" "iDRAC self-test error - controller hardware may have an issue ($timestamp) [SeqNumber: $seq]"
        return 0
    fi

    if echo "$msg_lower" | grep -Eq 'embedded flash.*failed|flash.*failed|mmc.*failed|media manager failed'; then
        send_alert "BMC-STOR-001" "iDRAC embedded flash error - storage issue may affect functionality ($timestamp) [SeqNumber: $seq]"
        return 0
    fi

    if echo "$msg_lower" | grep -Eq 'security.*risk|overall security.*risk|security violation|security state'; then
        send_alert "BMC-SEC-001" "iDRAC security risk state - check system security settings ($timestamp) [SeqNumber: $seq]"
        return 0
    fi

    if echo "$msg_lower" | grep -Eq 'network.*error|network.*failed|nic.*error|dns.*failed'; then
        send_alert "BMC-NET-001" "iDRAC network error - check network connectivity or configuration ($timestamp) [SeqNumber: $seq]"
        return 0
    fi

    if echo "$msg_lower" | grep -Eq 'authentication failed|login failed|invalid username|invalid password|invalid login|unable to log in'; then
        if echo "$msg_lower" | grep -q 'using gui'; then
            send_alert "BMC-AUTH-GUI-001" "iDRAC GUI authentication failure. iDRAC GUI 로그인 시도 및 로그인 인증 실패 발생"
            return 0
        fi

        if echo "$msg_lower" | grep -q 'using racadm'; then
            send_alert "BMC-AUTH-MGMT-001" "iDRAC management CLI/API authentication failure - method: RACADM ($timestamp) [SeqNumber: $seq] iDRAC racadm 로그인 시도 및 로그인 인증 실패 발생"
            return 0
        fi

        if echo "$msg_lower" | grep -q 'using ssh'; then
            send_alert "BMC-AUTH-SSH-001" "iDRAC SSH authentication failure. iDRAC SSH 로그인 시도 및 로그인 인증 실패 발생"
            return 0
        fi

        send_alert "BMC-AUTH-001" "iDRAC Unknown authentication failure. iDRAC 로그인 시도 및 로그인 인증 실패 발생"
        return 0
    fi

    if echo "$msg_lower" | grep -Eq 'license.*expired|license.*invalid|no valid license'; then
        send_alert "BMC-LIC-001" "iDRAC license issue - license expired or invalid ($timestamp) [SeqNumber: $seq]"
        return 0
    fi

    if echo "$severity" | grep -Eq 'Critical'; then
        send_alert "BMC-CRIT-001" "iDRAC critical error: $message ($timestamp) [SeqNumber: $seq]"
        return 0
    fi

    return 1
}

analyze_event() {
    local message="$1"
    local timestamp="$2"
    local severity="$3"
    local seq="$4"
    local msg_lower ip_address username

    log_message "Analyzing event: SeqNumber=$seq, Severity=$severity, Timestamp=$timestamp, Message=$message"

    if analyze_idrac_health "$message" "$timestamp" "$severity" "$seq"; then
        return
    fi

    msg_lower=$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')
    ip_address=$(printf '%s' "$message" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)

    if echo "$msg_lower" | grep -Eq 'factory default|factory defaults|racresetcfg|reset.*default'; then
        send_alert "BMC-CONFIG-001" "BMC factory reset detected ($timestamp) [SeqNumber: $seq]"
        return
    fi

    # Browser/GUI login success
    if echo "$msg_lower" | grep -Eq 'browser login|web login|using web|using gui|and gui|using https'; then
        if ! echo "$msg_lower" | grep -Eq '127\.0\.0\.1|::1|localhost'; then
            username=$(printf '%s' "$message" | sed -nE \
  -e 's/.*for ([^ ]+) from.*/\1/p' \
  -e 's/.*using ([^, ]+),[[:space:]]*from.*/\1/p' | head -1)
            if [ -n "$ip_address" ]; then
                send_alert "BMC-ACCESS-001" "BMC browser login - user: ${username:-unknown}, IP: $ip_address ($timestamp) [SeqNumber: $seq] iDRAC 브라우저 또는 GUI 로그인"
            else
                send_alert "BMC-ACCESS-001" "BMC browser login - user: ${username:-unknown} ($timestamp) [SeqNumber: $seq]  iDRAC 브라우저 또는 GUI 로그인"
            fi
            return
        fi
    fi

    # SSH login success
    if echo "$msg_lower" | grep -Eq 'successfully logged in.*and ssh|logged in.*and ssh|ssh login|secure shell'; then
        if ! echo "$msg_lower" | grep -Eq '127\.0\.0\.1|::1|localhost'; then
            username=$(printf '%s' "$message" | sed -nE \
  -e 's/.*using ([^, ]+),[[:space:]]*from.*/\1/p' \
  -e 's/.*for ([^ ]+) from.*/\1/p' | head -1)

            if [ -n "$ip_address" ]; then
                send_alert "BMC-ACCESS-002" "BMC SSH login - user: ${username:-unknown}, IP: $ip_address ($timestamp) [SeqNumber: $seq] iDRAC SSH 로그인"
            else
                send_alert "BMC-ACCESS-002" "BMC SSH login - user: ${username:-unknown} ($timestamp) [SeqNumber: $seq] iDRAC SSH 로그인"
            fi
            return
        fi
    fi

    # RACADM login/access success
    if echo "$msg_lower" | grep -Eq 'using racadm|and racadm'; then
        if ! echo "$msg_lower" | grep -Eq '127\.0\.0\.1|::1|localhost'; then
            username=$(printf '%s' "$message" | sed -nE \
  -e 's/.*for ([^ ]+) from.*/\1/p' \
  -e 's/.*using ([^, ]+),[[:space:]]*from.*/\1/p' | head -1)
            if [ -n "$ip_address" ]; then
                send_alert "BMC-ACCESS-003" "BMC RACADM access/attempt - user: ${username:-unknown}, IP: $ip_address ($timestamp) [SeqNumber: $seq] iDRAC RACADM 로그인"
            else
                send_alert "BMC-ACCESS-003" "BMC RACADM access/attempt - user: ${username:-unknown} ($timestamp) [SeqNumber: $seq] iDRAC RACADM 로그인"
            fi
            return
        fi
    fi


    # Browser/GUI logout - check before browser login to avoid false login alerts.
    if echo "$msg_lower" | grep -Eq '(using web|using gui|and gui|using https|browser|web).*(logged off|logged out|logoff)|(logged off|logged out|logoff).*(using web|using gui|and gui|using https|browser|web)'; then
        if ! echo "$msg_lower" | grep -Eq '127\.0\.0\.1|::1|localhost'; then
            username=$(printf '%s' "$message" | sed -nE \
  -e 's/.*session for ([^ ]+) from.*/\1/p' \
  -e 's/.*for ([^ ]+) from.*/\1/p' \
  -e 's/.*using ([^, ]+),[[:space:]]*from.*/\1/p' | head -1)

            if [ -n "$ip_address" ]; then
                send_alert "BMC-ACCESS-004" "BMC browser logout - user: ${username:-unknown}, IP: $ip_address ($timestamp) [SeqNumber: $seq] iDRAC 브라우저 또는 GUI 로그아웃"
            else
                send_alert "BMC-ACCESS-004" "BMC browser logout - user: ${username:-unknown} ($timestamp) [SeqNumber: $seq] iDRAC 브라우저 또는 GUI 로그아웃"
            fi
            return
        fi
    fi

    # SSH logout - check before SSH login to avoid false login alerts.
    if echo "$msg_lower" | grep -Eq '(using ssh|and ssh|secure shell).*(logged off|logged out|logoff)|(logged off|logged out|logoff).*(using ssh|and ssh|secure shell)'; then
        if ! echo "$msg_lower" | grep -Eq '127\.0\.0\.1|::1|localhost'; then
            username=$(printf '%s' "$message" | sed -nE \
  -e 's/.*session for ([^ ]+) from.*/\1/p' \
  -e 's/.*for ([^ ]+) from.*/\1/p' \
  -e 's/.*using ([^, ]+),[[:space:]]*from.*/\1/p' | head -1)

            if [ -n "$ip_address" ]; then
                send_alert "BMC-ACCESS-005" "BMC SSH logout - user: ${username:-unknown}, IP: $ip_address ($timestamp) [SeqNumber: $seq] iDRAC SSH 로그아웃"
            else
                send_alert "BMC-ACCESS-005" "BMC SSH logout - user: ${username:-unknown} ($timestamp) [SeqNumber: $seq] iDRAC SSH 로그아웃"
            fi
            return
        fi
    fi

    # RACADM logout - check before RACADM login/access to avoid false access alerts.
    if echo "$msg_lower" | grep -Eq '(using racadm|and racadm).*(logged off|logged out|logoff)|(logged off|logged out|logoff).*(using racadm|and racadm)'; then
        if ! echo "$msg_lower" | grep -Eq '127\.0\.0\.1|::1|localhost'; then
            username=$(printf '%s' "$message" | sed -nE \
  -e 's/.*session for ([^ ]+) from.*/\1/p' \
  -e 's/.*for ([^ ]+) from.*/\1/p' \
  -e 's/.*using ([^, ]+),[[:space:]]*from.*/\1/p' | head -1)

            if [ -n "$ip_address" ]; then
                send_alert "BMC-ACCESS-006" "BMC RACADM logout - user: ${username:-unknown}, IP: $ip_address ($timestamp) [SeqNumber: $seq] iDRAC RACADM 로그아웃"
            else
                send_alert "BMC-ACCESS-006" "BMC RACADM logout - user: ${username:-unknown} ($timestamp) [SeqNumber: $seq] iDRAC RACADM 로그아웃"
            fi
            return
        fi
    fi
}

get_latest_seq_from_file() {
    local file="$1"
    awk -F= '/^[[:space:]]*SeqNumber[[:space:]]*=/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}' "$file" | tail -1
}

process_lclog_file() {
    local file="$1"
    local last_seq="$2"
    local current_seq="" current_severity="" current_ts="" current_msg=""
    local max_seq="$last_seq"
    local count=0

    finalize_entry() {
        if [ -n "$current_seq" ] && echo "$current_seq" | grep -q '^[0-9]\+$'; then
            if [ "$current_seq" -gt "$last_seq" ]; then
                analyze_event "$current_msg" "$current_ts" "$current_severity" "$current_seq"
                count=$((count + 1))
            fi
            if [ "$current_seq" -gt "$max_seq" ]; then
                max_seq="$current_seq"
            fi
        fi
        current_seq=""
        current_severity=""
        current_ts=""
        current_msg=""
    }

    while IFS= read -r line || [ -n "$line" ]; do
        if printf '%s\n' "$line" | grep -qE '^[[:space:]]*SeqNumber[[:space:]]*='; then
            [ -n "$current_seq" ] && finalize_entry
            current_seq=$(parse_field "$line" "SeqNumber")
            continue
        fi

        [ -z "$line" ] && continue

        local value
        value=$(parse_field "$line" "Severity")
        [ -n "$value" ] && current_severity="$value"
        value=$(parse_field "$line" "Timestamp")
        [ -n "$value" ] && current_ts="$value"
        value=$(parse_field "$line" "Message")
        [ -n "$value" ] && current_msg="$value"
    done < "$file"

    [ -n "$current_seq" ] && finalize_entry

    echo "$count|$max_seq"
}

initialize_state() {
    local tmp_file
    tmp_file=$(mktemp /tmp/idrac_init.XXXXXX)
    log_message "First run detected - monitoring will start from the current point"

    if ! run_racadm lclog view -n "$LCLOG_FETCH_LIMIT" > "$tmp_file" 2>/dev/null; then
        log_message "ERROR: racadm lclog view failed"
        check_idrac_communication_health "false"
        rm -f "$tmp_file"
        return 1
    fi

    local latest_seq
    latest_seq=$(get_latest_seq_from_file "$tmp_file")
    [ -z "$latest_seq" ] && latest_seq="0"
    save_last_seq "$latest_seq"
    save_last_link_state "$(get_current_link_status)"
    if [ -r "$LINK_MONITOR_LOG" ]; then
        save_link_monitor_log_offset "$(wc -l < "$LINK_MONITOR_LOG" 2>/dev/null || echo 0)"
    fi
    log_message "Initialization completed - last SeqNumber: $latest_seq, initial LinkStatus: $(get_last_link_state)"
    check_idrac_communication_health "true"
    rm -f "$tmp_file"
    return 0
}

analyze_lclog() {
    local last_seq
    last_seq=$(get_last_seq)
    local tmp_file
    tmp_file=$(mktemp /tmp/idrac_lclog.XXXXXX)
    local start_ms end_ms
    start_ms=$(get_timestamp_ms)

    log_message "iDRAC Lifecycle Log analysis started (baseline SeqNumber: ${last_seq})"

    if ! run_racadm lclog view -n "$LCLOG_FETCH_LIMIT" > "$tmp_file" 2>"${tmp_file}.err"; then
        log_message "ERROR: racadm lclog view failed"

        if [ -s "${tmp_file}.err" ]; then
            while IFS= read -r errline; do
                log_message "RACADM STDERR: $errline"

                err_lower=$(printf '%s' "$errline" | tr '[:upper:]' '[:lower:]')

                if echo "$err_lower" | grep -Eq 'login failed|invalid username|invalid password|authentication failed'; then
                    send_alert "BMC-AUTH-MGMT-001" "iDRAC management CLI/API authentication failure - method: RACADM command - account or password error"
                fi

                if echo "$err_lower" | grep -Eq 'ssl library|certificate|self signed'; then
                    send_alert "BMC-SSL-001" "iDRAC SSL/certificate error detected"
                fi

                if echo "$err_lower" | grep -Eq 'unable to connect|connection timed out|no route to host'; then
                    send_alert "BMC-NET-001" "iDRAC network connection failed iDRAC 네트워크 오류/실패"
                fi
            done < "${tmp_file}.err"
        fi

        check_idrac_communication_health "false"
        rm -f "$tmp_file" "${tmp_file}.err"
        return 1
    fi

    local result count new_max_seq
    result=$(process_lclog_file "$tmp_file" "$last_seq")
    count=${result%%|*}
    new_max_seq=${result##*|}

    log_message "Processed new Lifecycle Log entry count: $count"
    if [ -n "$new_max_seq" ] && echo "$new_max_seq" | grep -q '^[0-9]\+$' && [ "$new_max_seq" -gt "$last_seq" ]; then
        save_last_seq "$new_max_seq"
        log_message "Updated last SeqNumber: $last_seq -> $new_max_seq"
    else
        log_message "No new Lifecycle Log entries"
    fi

    check_idrac_communication_health "true"
    end_ms=$(get_timestamp_ms)
    log_performance "lclog_analysis" "$((end_ms - start_ms))" "SUCCESS" "(new=$count, last_seq=$new_max_seq)"

    rm -f "$tmp_file" "${tmp_file}.err"
    return 0
}

get_sel_count() {
    local tmp_file count
    tmp_file=$(mktemp /tmp/idrac_sel.XXXXXX)
    if ! run_racadm getsel -i > "$tmp_file" 2>/dev/null; then
        rm -f "$tmp_file"
        echo "0"
        return 0
    fi
    count=$(grep -Eio '([0-9]+)[[:space:]]+record' "$tmp_file" | grep -Eo '[0-9]+' | head -1)
    [ -z "$count" ] && count=$(grep -Eio 'entries[[:space:]]*=[[:space:]]*[0-9]+' "$tmp_file" | grep -Eo '[0-9]+' | head -1)
    [ -z "$count" ] && count=0
    rm -f "$tmp_file"
    echo "$count"
}

check_sel_cleanup() {
    [ "$ENABLE_SEL_CHECK" != "true" ] && return 0
    local count
    count=$(get_sel_count)
    log_message "Current SEL log count: ${count}"
    if [ "$count" -gt "$SEL_CLEANUP_THRESHOLD" ]; then
        log_message "SEL cleanup required (current: ${count}, threshold: ${SEL_CLEANUP_THRESHOLD})"
        if [ "$ENABLE_SEL_CLEANUP" = "true" ]; then
            if run_racadm clrsel >/dev/null 2>&1; then
                send_alert "BMC-CLEANUP-001" "SEL auto-cleanup completed - deleted ${count} entries"
            else
                log_message "ERROR: SEL auto-cleanup failed"
            fi
        fi
    else
        log_message "SEL cleanup not required (current: ${count}, threshold: ${SEL_CLEANUP_THRESHOLD})"
    fi
}

show_version() {
    local info
    info=$(run_racadm getsysinfo 2>/dev/null | grep -E 'Bios Version|iDRAC Version|Lifecycle Controller Version' | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')
    log_message "Using RACADM/BMC version information: ${info}"
}

usage() {
    cat <<USAGE
Usage: $0 [--debug] [--init-state] [--check-link-only]
  --debug            Also print logs to stdout
  --init-state       Initialize the current SeqNumber/LinkStatus as the baseline
  --check-link-only  Check only LinkStatus changes
USAGE
}

main() {
    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: this script must be run as root (local racadm requires root)" >&2
        exit 101
    fi

    mkdir -p "$LOG_DIR" "$STATE_DIR"

    if [ ! -x "$RACADM" ]; then
        echo "ERROR: racadm not found at $RACADM" >&2
        exit 102
    fi

    acquire_lock

    case "$1" in
        --debug)
            DEBUG_MODE="true"
            ;;
        --init-state)
            DEBUG_MODE="true"
            show_version
            initialize_state
            exit $?
            ;;
        --check-link-only)
            DEBUG_MODE="true"
            show_version
            check_link_status_change
            exit $?
            ;;
        "")
            ;;
        *)
            usage
            exit 103
            ;;
    esac

    show_version

    if [ "$(get_last_seq)" = "0" ] || [ ! -f "$SEQ_STATE_FILE" ]; then
        initialize_state || exit 104
        exit 0
    fi

    analyze_lclog || exit 105
    check_link_status_change || true
    check_sel_cleanup
    log_message "BMC log analysis completed"
	
    return 0
}

main "$@"
