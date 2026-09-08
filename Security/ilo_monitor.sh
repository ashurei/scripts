#!/bin/bash

# iLO 모니터링 스크립트
# 파일명: ilo_monitor.sh
# 버젼: v4 2026.06.01
# 기능: iLO 로그 모니터링, 상태 감지, 자동 정리, 성능 측정,  EventNumber/RecordId 호환 버전

SCRIPT_NAME="bmc_monitor"
MONITOR_TYPE="ilo"
LOG_DIR="/var/log"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"
ALERT_LOG="${LOG_DIR}/${SCRIPT_NAME}_alerts.log"
PERF_LOG="${LOG_DIR}/${SCRIPT_NAME}_performance.log"
STATE_FILE="/var/lib/${SCRIPT_NAME}_${MONITOR_TYPE}_state"
HEALTH_STATE_FILE="/var/lib/${SCRIPT_NAME}_${MONITOR_TYPE}_health_state"
TEMP_DIR="/var/tmp/ilorest_tmp"
LOCK_FILE="${TEMP_DIR}/${SCRIPT_NAME}_${MONITOR_TYPE}.lock"
CURRENT_ILOREST_TMP=""

# 로그 로테이션 설정
MAX_LOG_SIZE=10485760          # 10MB
LOG_RETENTION_DAYS=30          # 로그 백업 보관 일수
MAX_LOG_BACKUPS=10            # 최대 백업 파일 개수
LOG_BACKUP_COMPRESS=true       # 백업 파일 압축 여부

# iLO 상태 모니터링 설정
MAX_CONSECUTIVE_FAILURES=3     # 연속 실패 허용 횟수
TIMEOUT_SECONDS=30            # ilorest 명령어 타임아웃

# iLO 로그 정리 설정
ENABLE_LOG_CLEANUP=true        # 로그 정리 활성화 여부
MIN_LOGS_TO_KEEP=20           # 최소 보관할 로그 개수
MAX_LOGS_BEFORE_CLEANUP=50   # 이 개수 초과시 정리 수행
BACKUP_BEFORE_CLEANUP=true    # 정리 전 백업 여부

# 백업 정리 설정
BACKUP_RETENTION_DAYS=7       # 백업 보관 일수
MAX_BACKUP_FILES=30          # 최대 백업 파일 개수
MAX_BACKUP_SIZE_MB=100       # 백업 디렉토리 최대 크기 (MB)

# 락 관리
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            echo "Another instance is already running (PID: $lock_pid)"
            exit 1
        else
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}

trap cleanup_on_exit EXIT INT TERM

log_rotation_message() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)

    # rotate/cleanup 내부에서 쓰는 보조 로그 함수.
    # log_message()를 호출하지 않는다. 재귀 rotate 방지 목적.
    echo "[$timestamp] $message" >> "$LOG_FILE" 2>/dev/null || true

    [ "$DEBUG_MODE" = "true" ] && echo "[$timestamp] $message"
}

cleanup_on_exit() {
    if [ -n "$CURRENT_ILOREST_TMP" ] && [ -d "$CURRENT_ILOREST_TMP" ]; then
        rm -rf "$CURRENT_ILOREST_TMP" 2>/dev/null
    fi

    release_lock
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

    [ "$DEBUG_MODE" = "true" ] && echo "[$timestamp] ERROR: $message" >&2
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
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)

    rotate_log "$LOG_FILE"
    echo "[$timestamp] $message" >> "$LOG_FILE"

    if [ "$DEBUG_MODE" = "true" ]; then
        echo "[$timestamp] $message"
    fi
}

send_alert() {
    local code="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
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
}

# 상태 관리 함수들
get_last_event_number() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

save_last_event_number() {
    local event_number="$1"
    mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null
    echo "$event_number" > "$STATE_FILE"
}

get_failure_count() {
    if [ -f "$HEALTH_STATE_FILE" ]; then
        grep "^failure_count=" "$HEALTH_STATE_FILE" 2>/dev/null | cut -d'=' -f2 || echo "0"
    else
        echo "0"
    fi
}

save_failure_count() {
    local count="$1"
    mkdir -p "$(dirname "$HEALTH_STATE_FILE")" 2>/dev/null

    if [ -f "$HEALTH_STATE_FILE" ]; then
        sed -i "s/^failure_count=.*/failure_count=$count/" "$HEALTH_STATE_FILE" 2>/dev/null || echo "failure_count=$count" >> "$HEALTH_STATE_FILE"
    else
        echo "failure_count=$count" > "$HEALTH_STATE_FILE"
    fi
}

get_last_success_time() {
    if [ -f "$HEALTH_STATE_FILE" ]; then
        grep "^last_success=" "$HEALTH_STATE_FILE" 2>/dev/null | cut -d'=' -f2 || echo "0"
    else
        echo "0"
    fi
}

save_last_success_time() {
    local timestamp="$1"
    mkdir -p "$(dirname "$HEALTH_STATE_FILE")" 2>/dev/null

    if [ -f "$HEALTH_STATE_FILE" ]; then
        sed -i "s/^last_success=.*/last_success=$timestamp/" "$HEALTH_STATE_FILE" 2>/dev/null || echo "last_success=$timestamp" >> "$HEALTH_STATE_FILE"
    else
        echo "last_success=$timestamp" > "$HEALTH_STATE_FILE"
    fi
}

# 성능 측정 함수들
get_timestamp_ms() {
    if command -v date >/dev/null 2>&1; then
        date +%s%3N 2>/dev/null || date +%s000
    else
        echo $(($(date +%s) * 1000))
    fi
}

format_duration() {
    local duration_ms="$1"
    local duration_s=$((duration_ms / 1000))
    local ms_part=$((duration_ms % 1000))

    if [ $duration_s -gt 0 ]; then
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
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    rotate_log "$PERF_LOG"
    echo "[$timestamp] $operation: $(format_duration $duration_ms) - $status $details" >> "$PERF_LOG"

    if [ "$DEBUG_MODE" = "true" ]; then
        echo "PERF: $operation took $(format_duration $duration_ms) - $status"
    fi
}

cleanup_stale_ilorest_tmp() {
    local base_tmp="${TEMP_DIR:-/tmp}"

    [ -d "$base_tmp" ] || return 0

    find "$base_tmp" -maxdepth 1 -type d -name 'ilorest_run_*' -mmin +10 -exec rm -rf {} + 2>/dev/null
}

run_ilorest() {
    local rc
    local base_tmp="${TEMP_DIR:-/tmp}"
    local run_tmp

    mkdir -p "$base_tmp" 2>/dev/null
    chmod 700 "$base_tmp" 2>/dev/null

    run_tmp=$(mktemp -d "${base_tmp}/ilorest_run_XXXXXX" 2>/dev/null)
    if [ -z "$run_tmp" ] || [ ! -d "$run_tmp" ]; then
        log_message "ERROR: failed to create ilorest temporary directory under $base_tmp"
        return 1
    fi

    CURRENT_ILOREST_TMP="$run_tmp"

    if [ "$TIMEOUT_SECONDS" -gt 0 ] && command -v timeout >/dev/null 2>&1; then
        TMPDIR="$run_tmp" timeout --kill-after=5 "$TIMEOUT_SECONDS" ilorest "$@"
        rc=$?
    else
        TMPDIR="$run_tmp" ilorest "$@"
        rc=$?
    fi

    rm -rf "$run_tmp" 2>/dev/null
    CURRENT_ILOREST_TMP=""

    return "$rc"
}

# iLO 통신 상태 확인
check_ilo_communication_health() {
    local success="$1"
    local current_time=$(date +%s)
    local failure_count=$(get_failure_count)

    if [ "$success" = "true" ]; then
        save_failure_count "0"
        save_last_success_time "$current_time"
        log_message "iLO communication healthy"
    else
        failure_count=$((failure_count + 1))
        save_failure_count "$failure_count"

        log_message "iLO communication failed (consecutive failures: $failure_count)"

        if [ "$failure_count" -ge "$MAX_CONSECUTIVE_FAILURES" ]; then
            local last_success=$(get_last_success_time)
            local duration="unknown"

            if [ "$last_success" != "0" ]; then
                duration=$(( (current_time - last_success) / 60 ))
                duration="${duration} minutes"
            fi

            send_alert "BMC-COMM-001" "iLO communication outage - $failure_count consecutive failures (last success: $duration ago)"
        fi
    fi
}

# 로그 개수 확인 함수
get_total_log_count() {
    local temp_log="${TEMP_DIR}/ilo_count_$$.log"
    local count=0

    if run_ilorest serverlogs --selectlog=IEL > "$temp_log" 2>/dev/null; then
        count=$(grep -c "^@odata.context=" "$temp_log" 2>/dev/null || echo "0")
        rm -f "$temp_log"
    fi

    echo "$count"
}

cleanup_old_backups() {
    local backup_dir="${LOG_DIR}/${SCRIPT_NAME}_${MONITOR_TYPE}_backups"

    if [ ! -d "$backup_dir" ]; then
        return 0
    fi

    log_message "Backup file cleanup started"

    # 1. 날짜 기준 정리
    local deleted_by_date
    deleted_by_date=$(find "$backup_dir" -name "${SCRIPT_NAME}_${MONITOR_TYPE}_logs_*.log" -type f -mtime +$BACKUP_RETENTION_DAYS 2>/dev/null | wc -l)

    find "$backup_dir" -name "${SCRIPT_NAME}_${MONITOR_TYPE}_logs_*.log" -type f -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null

    if [ "$deleted_by_date" -gt 0 ]; then
        log_message "Backup cleanup by age: deleted ${deleted_by_date} files older than ${BACKUP_RETENTION_DAYS} days"
    fi

    # 2. 개수 기준 정리
    local current_count
    current_count=$(find "$backup_dir" -name "${SCRIPT_NAME}_${MONITOR_TYPE}_logs_*.log" -type f 2>/dev/null | wc -l)

    if [ "$current_count" -gt "$MAX_BACKUP_FILES" ]; then
        local excess_count
        excess_count=$((current_count - MAX_BACKUP_FILES))

        find "$backup_dir" -name "${SCRIPT_NAME}_${MONITOR_TYPE}_logs_*.log" -type f -printf '%T@ %p\n' 2>/dev/null | \
        sort -n | head -"$excess_count" | cut -d' ' -f2- | \
        while IFS= read -r file; do
            rm -f "$file"
            log_message "Backup cleanup by count: deleted $(basename "$file")"
        done

        log_message "Backup cleanup by count: deleted ${excess_count} files (keeping max ${MAX_BACKUP_FILES})"
    fi

    # 3. 용량 기준 정리
    # MAX_BACKUP_SIZE_MB를 초과하면 오래된 백업부터 삭제한다.
    if [ "$MAX_BACKUP_SIZE_MB" -gt 0 ] 2>/dev/null; then
        local max_size_kb current_size_kb deleted_by_size
        max_size_kb=$((MAX_BACKUP_SIZE_MB * 1024))
        current_size_kb=$(du -sk "$backup_dir" 2>/dev/null | cut -f1)
        deleted_by_size=0

        if [ -z "$current_size_kb" ]; then
            current_size_kb=0
        fi

        if [ "$current_size_kb" -gt "$max_size_kb" ]; then
            find "$backup_dir" -name "${SCRIPT_NAME}_${MONITOR_TYPE}_logs_*.log" -type f -printf '%T@ %p\n' 2>/dev/null | \
            sort -n | cut -d' ' -f2- | \
            while IFS= read -r file; do
                current_size_kb=$(du -sk "$backup_dir" 2>/dev/null | cut -f1)
                [ -z "$current_size_kb" ] && current_size_kb=0

                if [ "$current_size_kb" -le "$max_size_kb" ]; then
                    break
                fi

                rm -f "$file"
                deleted_by_size=$((deleted_by_size + 1))
                log_message "Backup cleanup by size: deleted $(basename "$file")"
            done

            current_size_kb=$(du -sk "$backup_dir" 2>/dev/null | cut -f1)
            [ -z "$current_size_kb" ] && current_size_kb=0

            log_message "Backup cleanup by size completed - current size: $((current_size_kb / 1024))MB, limit: ${MAX_BACKUP_SIZE_MB}MB"
        fi
    fi

    # 4. 정리 결과 요약
    local final_count final_size_kb final_size_mb
    final_count=$(find "$backup_dir" -name "${SCRIPT_NAME}_${MONITOR_TYPE}_logs_*.log" -type f 2>/dev/null | wc -l)
    final_size_kb=$(du -sk "$backup_dir" 2>/dev/null | cut -f1)
    [ -z "$final_size_kb" ] && final_size_kb=0
    final_size_mb=$((final_size_kb / 1024))

    log_message "Backup cleanup completed - current state: ${final_count} files, ${final_size_mb}MB"
}


# 로그 백업 함수
backup_ilo_logs() {
    local backup_dir="${LOG_DIR}/${SCRIPT_NAME}_${MONITOR_TYPE}_backups"
    local backup_file="${backup_dir}/${SCRIPT_NAME}_${MONITOR_TYPE}_logs_$(date +%Y%m%d_%H%M%S).$$.log"

    mkdir -p "$backup_dir" 2>/dev/null

    log_message "BMC log backup started: $backup_file"

    if run_ilorest serverlogs --selectlog=IEL > "$backup_file" 2>/dev/null; then
        local backup_size=$(stat -c%s "$backup_file" 2>/dev/null || echo "0")
        local backup_size_kb=$((backup_size / 1024))

        log_message "BMC log backup completed: $backup_file (${backup_size_kb}KB)"

        # 백업 파일 정리 수행
        cleanup_old_backups

        return 0
    else
        log_message "ERROR: BMC log backup failed"
        rm -f "$backup_file"
        return 1
    fi
}

# 안전한 로그 정리 함수
safe_cleanup_ilo_logs() {
    if [ "$ENABLE_LOG_CLEANUP" != "true" ]; then
        log_message "Log cleanup is disabled"
        return 0
    fi

    local total_logs=$(get_total_log_count)
    log_message "Current BMC log count: $total_logs"

    # 정리 필요성 검사
    if [ "$total_logs" -le "$MAX_LOGS_BEFORE_CLEANUP" ]; then
        log_message "Log cleanup not required (current: $total_logs, threshold: $MAX_LOGS_BEFORE_CLEANUP)"
        return 0
    fi

    log_message "Log cleanup required - threshold exceeded (current: $total_logs, threshold: $MAX_LOGS_BEFORE_CLEANUP)"

    # 백업 수행 (옵션)
    if [ "$BACKUP_BEFORE_CLEANUP" = "true" ]; then
        if ! backup_ilo_logs; then
            log_message "ERROR: stopping log cleanup because backup failed"
            return 1
        fi
    fi

    # 로그 정리 수행
    log_message "BMC log cleanup started"

    local cleanup_start_time=$(get_timestamp_ms)

    if run_ilorest serverlogs --selectlog=IEL --clearlog 2>/dev/null; then
        local cleanup_end_time=$(get_timestamp_ms)
        local cleanup_duration=$((cleanup_end_time - cleanup_start_time))

        log_performance "log_cleanup" "$cleanup_duration" "SUCCESS" "(cleared $total_logs logs)"
        log_message "BMC log cleanup completed - deleted $total_logs logs (duration: $(format_duration $cleanup_duration))"

        # 상태 초기화
        save_last_event_number "0"
        log_message "EventNumber state reset - next run will start from a new baseline"

        # 알림 기록
        send_alert "BMC-CLEANUP-001" "iLO log auto-cleanup completed - deleted $total_logs logs (backup: $BACKUP_BEFORE_CLEANUP)"

        return 0
    else
        log_message "ERROR: BMC log cleanup failed"
        log_performance "log_cleanup" "0" "FAILED" ""
        return 1
    fi
}

initialize_state() {
    local temp_log="${TEMP_DIR}/ilo_init_$$.log"
    local max_event_number=0

    log_message "First run detected - monitoring will start from the current point"

    if ! run_ilorest serverlogs --selectlog=IEL > "$temp_log" 2>/dev/null; then
        log_message "ERROR: ilorest command failed or timed out"
        check_ilo_communication_health "false"
        rm -f "$temp_log"
        return 1
    fi

    # 로그 파일 유효성 검사
    if [ ! -s "$temp_log" ]; then
        log_message "ERROR: BMC log output is empty"
        check_ilo_communication_health "false"
        rm -f "$temp_log"
        return 1
    fi

    # JSON/데이터 형식 검증
    if ! grep -q "^@odata.context=" "$temp_log" 2>/dev/null; then
        log_message "ERROR: BMC log format is invalid"
        check_ilo_communication_health "false"
        rm -f "$temp_log"
        return 1
    fi

    local current_event_number=""
    local current_record_id=""
    local init_in_entry=false

    process_init_entry() {
        local selected_id=""

        # EventNumber를 우선 사용하고, 없으면 RecordId를 사용한다.
        if [ -n "$current_event_number" ]; then
            selected_id="$current_event_number"
        elif [ -n "$current_record_id" ]; then
            selected_id="$current_record_id"
        fi

        if [ -n "$selected_id" ] && echo "$selected_id" | grep -q "^[0-9]\+$"; then
            if [ "$selected_id" -gt "$max_event_number" ]; then
                max_event_number=$selected_id
            fi
        fi
    }

    while IFS= read -r line || [ -n "$line" ]; do
        if echo "$line" | grep -q "^@odata.context="; then
            if [ "$init_in_entry" = true ]; then
                process_init_entry
            fi
            current_event_number=""
            current_record_id=""
            init_in_entry=true
            continue
        fi

        if [ -z "$line" ]; then
            if [ "$init_in_entry" = true ]; then
                process_init_entry
            fi
            current_event_number=""
            current_record_id=""
            init_in_entry=false
            continue
        fi

        if [ "$init_in_entry" = true ]; then
            local event_num=$(echo "$line" | sed 's/^[[:space:]]*//' | grep "^EventNumber=" | cut -d'=' -f2)
            if [ -n "$event_num" ]; then
                current_event_number="$event_num"
            fi

            local record_id=$(echo "$line" | sed 's/^[[:space:]]*//' | grep "^RecordId=" | cut -d'=' -f2)
            if [ -n "$record_id" ] && [ -z "$current_record_id" ]; then
                current_record_id="$record_id"
            fi
        fi
    done < "$temp_log"

    if [ "$init_in_entry" = true ]; then
        process_init_entry
    fi

    rm -f "$temp_log"

    if [ "$max_event_number" -gt 0 ]; then
        save_last_event_number "$max_event_number"
        log_message "Initialization completed - last EventNumber/RecordId: $max_event_number"
        check_ilo_communication_health "true"
    else
        save_last_event_number "0"
        log_message "Initialization completed - EventNumber/RecordId not found"
        check_ilo_communication_health "false"
    fi

    return 0
}

extract_field_value() {
    local line="$1"
    local field="$2"
    echo "$line" | sed 's/^[[:space:]]*//' | grep "^${field}=" | cut -d'=' -f2-
}

# iLO 상태 분석 함수
analyze_ilo_health() {
    local message="$1"
    local created="$2"
    local severity="$3"
    local event_number="$4"

    local message_lower=$(echo "$message" | tr '[:upper:]' '[:lower:]')

    # iLO 하드웨어/펌웨어 문제
    if echo "$message_lower" | grep -q "ilo reset by watchdog"; then
        send_alert "BMC-HW-001" "iLO watchdog reset detected - controller restarted due to an abnormal state ($created) [EventNumber: $event_number]"
        return 0
    fi

    if echo "$message_lower" | grep -q "ilo self test error"; then
        send_alert "BMC-HW-002" "iLO self-test error - controller hardware may have an issue ($created) [EventNumber: $event_number]"
        return 0
    fi

    if echo "$message_lower" | grep -q "embedded flash.*failed\|embedded media manager failed"; then
        send_alert "BMC-STOR-001" "iLO embedded flash error - storage issue may affect functionality ($created) [EventNumber: $event_number]"
        return 0
    fi

    # iLO 보안 상태 문제
    if echo "$message_lower" | grep -q "security state.*risk\|overall security.*risk"; then
        send_alert "BMC-SEC-001" "iLO security risk state - check system security settings ($created) [EventNumber: $event_number]"
        return 0
    fi

    # iLO 네트워크 관련 문제
    if echo "$message_lower" | grep -q "ilo.*network.*error\|network.*ilo.*failed"; then
        send_alert "BMC-NET-001" "iLO network error - check network connectivity or configuration ($created) [EventNumber: $event_number] iLO 네트워크 오류/실패"
        return 0
    fi

    # iLO 인증/접근 문제 - 접속 경로별 분류
    if echo "$message_lower" | grep -Eq "authentication.*failed|login.*failed|invalid username|invalid password|invalid login|access denied|unauthorized|unable to log in|login failure|authentication failure"; then

        # GUI / Web / Browser 인증 실패
        if echo "$message_lower" | grep -Eq "browser|web|gui|https"; then
            send_alert "BMC-AUTH-GUI-001" "iLO GUI authentication failure - possible unauthorized web access attempt or account issue ($created) [EventNumber: $event_number] iLO GUI 로그인 시도 및 로그인 인증 실패 발생"
            return 0
        fi

        # SSH 인증 실패
        if echo "$message_lower" | grep -Eq "ssh|secure shell"; then
            send_alert "BMC-AUTH-SSH-001" "iLO SSH authentication failure - possible unauthorized SSH access attempt or account issue ($created) [EventNumber: $event_number] iLO SSH 로그인 시도 및 로그인 인증 실패 발생"
            return 0
        fi

        # REST / Redfish / iLOREST 인증 실패
        if echo "$message_lower" | grep -Eq "rest|redfish|ilorest|hprest|api|session"; then
            send_alert "BMC-AUTH-MGMT-001" "iLO management CLI/API authentication failure - method: REST/iLOREST - possible unauthorized API access attempt or account issue ($created) [EventNumber: $event_number] iLO ilorest 로그인 시도 및 로그인 인증 실패 발생"
            return 0
        fi

        # 경로를 알 수 없는 인증 실패
        send_alert "BMC-AUTH-001" "iLO authentication failure - possible unauthorized access attempt or account issue ($created) [EventNumber: $event_number] iLO 로그인 시도 및 로그인 인증 실패 발생"
        return 0
    fi

    # iLO 라이센스 문제
    if echo "$message_lower" | grep -q "license.*expired\|license.*invalid"; then
        send_alert "BMC-LIC-001" "iLO license issue - license expired or invalid ($created) [EventNumber: $event_number]"
        return 0
    fi

    # 기타 Critical/Warning 레벨 iLO 메시지
    if [ "$severity" = "Critical" ] && echo "$message_lower" | grep -q "ilo"; then
        send_alert "BMC-CRIT-001" "iLO critical error: $message ($created) [EventNumber: $event_number]"
        return 0
    fi

    return 1
}

extract_ip_address() {
    local message="$1"

    printf '%s\n' "$message" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1
}

extract_login_username() {
    local message="$1"

    printf '%s\n' "$message" | sed -nE \
        -e 's/.*Browser login:[[:space:]]*([^-]+)[[:space:]]*-.*/\1/p' \
        -e 's/.*SSH login:[[:space:]]*([^-]+)[[:space:]]*-.*/\1/p' \
        -e 's/.*Secure Shell login:[[:space:]]*([^-]+)[[:space:]]*-.*/\1/p' \
        -e 's/.*REST login:[[:space:]]*([^ -]+).*/\1/p' \
        -e 's/.*Host REST login:[[:space:]]*([^ -]+).*/\1/p' \
        -e 's/.*Redfish login:[[:space:]]*([^ -]+).*/\1/p' \
        -e 's/.*iLOREST login:[[:space:]]*([^ -]+).*/\1/p' \
        -e 's/.*User[[:space:]]+([^[:space:],]+).*(SSH|Secure Shell|REST|Redfish|iLOREST).*/\1/p' \
        -e 's/.*for[[:space:]]+([^[:space:]]+)[[:space:]]+from.*/\1/p' | \
        head -1 | sed 's/[[:space:]]*$//'
}

extract_logout_username() {
    local message="$1"

    printf '%s\n' "$message" | sed -nE \
        -e 's/.*Browser logout:[[:space:]]*([^-]+)[[:space:]]*-.*/\1/p' \
        -e 's/.*Browser logged out:[[:space:]]*([^-]+)[[:space:]]*-.*/\1/p' \
        -e 's/.*SSH logout:[[:space:]]*([^-]+)[[:space:]]*-.*/\1/p' \
        -e 's/.*SSH logged out:[[:space:]]*([^-]+)[[:space:]]*-.*/\1/p' \
        -e 's/.*Secure Shell logout:[[:space:]]*([^-]+)[[:space:]]*-.*/\1/p' \
        -e 's/.*REST logout:[[:space:]]*([^ -]+).*/\1/p' \
        -e 's/.*Host REST logout:[[:space:]]*([^ -]+).*/\1/p' \
        -e 's/.*Redfish logout:[[:space:]]*([^ -]+).*/\1/p' \
        -e 's/.*iLOREST logout:[[:space:]]*([^ -]+).*/\1/p' \
        -e 's/.*User[[:space:]]+([^[:space:],]+).*(logout|logged out).*/\1/p' \
        -e 's/.*for[[:space:]]+([^[:space:]]+)[[:space:]]+from.*/\1/p' | \
        head -1 | sed 's/[[:space:]]*$//'
}

is_loopback_or_local_event() {
    local message_lower="$1"
    local ip_address="$2"

    if printf '%s\n' "$ip_address" | grep -Eq '^127\.|^::1$'; then
        return 0
    fi

    if printf '%s\n' "$message_lower" | grep -Eq '127\.0\.0\.1|::1|localhost'; then
        return 0
    fi

    return 1
}

is_browser_logout_event() {
    local message_lower="$1"

    printf '%s\n' "$message_lower" | grep -Eq \
        'browser logout|browser logged out|web logout|web logged out|gui logout|gui logged out|https logout|https logged out|logged out.*browser|logged out.*web|logged out.*gui|session.*closed.*browser|session.*closed.*web|session.*terminated.*browser|session.*terminated.*web'
}

is_ssh_logout_event() {
    local message_lower="$1"

    printf '%s\n' "$message_lower" | grep -Eq \
        'ssh logout|ssh logged out|secure shell logout|secure shell.*logged out|logged out.*ssh|session.*closed.*ssh|session.*terminated.*ssh|session.*using.*ssh.*logged out'
}

is_rest_logout_event() {
    local message_lower="$1"

    printf '%s\n' "$message_lower" | grep -Eq \
        'host rest logout|rest logout|redfish logout|ilorest logout|hprest logout|logged out.*rest|logged out.*redfish|logged out.*ilorest|session.*closed.*redfish|session.*closed.*rest|session.*terminated.*redfish|session.*terminated.*rest|session.*deleted.*redfish|session.*deleted.*rest'
}

is_rest_login_event() {
    local message_lower="$1"

    # logout은 로그인 이벤트가 아니므로 제외한다.
    if is_rest_logout_event "$message_lower" || printf '%s\n' "$message_lower" | grep -Eq 'logout|logged out'; then
        return 1
    fi

    printf '%s\n' "$message_lower" | grep -Eq \
        'host rest login|rest login|redfish login|ilorest login|hprest login|login.*using.*rest|login.*via.*rest|logged in.*rest|logged in.*redfish|session.*created.*redfish|session.*created.*rest'
}

is_periodic_os_rest_noise() {
    local message_lower="$1"
    local ip_address="$2"
    local username="$3"

    # 사용자가 말한 기준: OS 주기 접근은 127.0.0.1/localhost 형태로 남는 경우가 많음.
    if ! is_loopback_or_local_event "$message_lower" "$ip_address"; then
        return 1
    fi

    # Host REST + loopback이면 주기적 OS/agent 접근으로 보고 alert 제외.
    if printf '%s\n' "$message_lower" | grep -Eq 'host rest login|host rest session|host rest'; then
        return 0
    fi

    # 환경별 서비스 계정이 있다면 여기에 추가 가능.
    # 예: hpams, ams, hponcfg, smad 등 실제 로그에서 확인된 계정만 넣는 것을 권장.
    if printf '%s\n' "$username" | grep -Eiq '^(hpams|ams|hponcfg|smad|system|unknown)$'; then
        return 0
    fi

    return 1
}


analyze_event() {
    local message="$1"
    local created="$2"
    local severity="$3"
    local event_number="$4"

    log_message "Analyzing event: EventNumber=$event_number, Message=$message"

    # iLO 상태/인증 분석에서 alert를 처리했으면 성공 로그인 분석으로 넘어가지 않는다.
    if analyze_ilo_health "$message" "$created" "$severity" "$event_number"; then
        return
    fi

    local message_lower
    message_lower=$(echo "$message" | tr '[:upper:]' '[:lower:]')

    # 기존 네트워크 모니터링
    if echo "$message_lower" | grep -q "network link up\|link up"; then
        local speed=$(echo "$message" | grep -o '[0-9]\+ Mbps' || echo "unknown speed")
        send_alert "BMC-NET-002" "iLO network link UP - $speed ($created) [EventNumber: $event_number]"

    elif echo "$message_lower" | grep -q "network link down\|link down"; then
        send_alert "BMC-NET-003" "iLO network link DOWN ($created) [EventNumber: $event_number]"
    fi



    # 기존 로그인 모니터링
    if echo "$message_lower" | grep -q "browser login"; then
        if ! echo "$message_lower" | grep -q "localhost\|127\.0\.0\.1\|::1"; then
            local ip_address=$(echo "$message" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
            local username=$(echo "$message" | sed -n 's/.*Browser login: \([^-]*\) -.*/\1/p' | sed 's/[[:space:]]*$//')

            if [ -n "$ip_address" ]; then
                send_alert "BMC-ACCESS-001" "iLO browser login - user: $username, IP: $ip_address ($created) [EventNumber: $event_number]  iLO 브라우저 또는 GUI 로그인"
            else
                send_alert "BMC-ACCESS-001" "iLO browser login - user: $username ($created) [EventNumber: $event_number]  iLO 브라우저 또는 GUI 로그인"
            fi
        fi
    fi

    if echo "$message_lower" | grep -q "ssh login\|secure shell"; then
        if ! echo "$message_lower" | grep -q "localhost\|127\.0\.0\.1\|::1"; then
            local ip_address
            local username
            ip_address=$(extract_ip_address "$message")
            username=$(extract_login_username "$message")
            if [ -n "$ip_address" ]; then
                send_alert "BMC-ACCESS-002" "iLO SSH login - user: ${username:-unknown}, IP: $ip_address ($created) [EventNumber: $event_number] iLO SSH 로그인"
            else
                send_alert "BMC-ACCESS-002" "iLO SSH login - user: ${username:-unknown} ($created) [EventNumber: $event_number] iLO SSH 로그인"
            fi
        fi
    fi

        # REST/Redfish/iLOREST 로그인 모니터링
    if is_rest_login_event "$message_lower"; then
        local ip_address
        local username

        ip_address=$(extract_ip_address "$message")
        username=$(extract_login_username "$message")

        if is_periodic_os_rest_noise "$message_lower" "$ip_address" "${username:-unknown}"; then
            # 주기적 OS/agent 접근은 alert 로그에 남기지 않는다.
            # 필요하면 일반 로그에만 남겨서 디버깅 가능하게 한다.
            log_message "Ignored periodic/local BMC REST login event - user: ${username:-unknown}, IP: ${ip_address:-unknown}, EventNumber: $event_number"
        else
            if [ -n "$ip_address" ]; then
                send_alert "BMC-ACCESS-003" "iLO REST/iLOREST login - user: ${username:-unknown}, IP: $ip_address ($created) [EventNumber: $event_number]  iLO ilorest 로그인"
            else
                send_alert "BMC-ACCESS-003" "iLO REST/iLOREST login - user: ${username:-unknown} ($created) [EventNumber: $event_number]  iLO ilorest 로그인"
            fi
        fi
    fi



    # 로그아웃 모니터링 - login/access 오탐 방지를 위해 로그인 검사보다 먼저 처리한다.
    if is_browser_logout_event "$message_lower"; then
        local ip_address
        local username

        ip_address=$(extract_ip_address "$message")
        username=$(extract_logout_username "$message")

        if ! is_loopback_or_local_event "$message_lower" "$ip_address"; then
            if [ -n "$ip_address" ]; then
                send_alert "BMC-ACCESS-004" "iLO browser logout - user: ${username:-unknown}, IP: $ip_address ($created) [EventNumber: $event_number] iLO 브라우저 또는 GUI 로그아웃"
            else
                send_alert "BMC-ACCESS-004" "iLO browser logout - user: ${username:-unknown} ($created) [EventNumber: $event_number] iLO 브라우저 또는 GUI 로그아웃"
            fi
        fi
        return
    fi

    if is_ssh_logout_event "$message_lower"; then
        local ip_address
        local username

        ip_address=$(extract_ip_address "$message")
        username=$(extract_logout_username "$message")

        if ! is_loopback_or_local_event "$message_lower" "$ip_address"; then
            if [ -n "$ip_address" ]; then
                send_alert "BMC-ACCESS-005" "iLO SSH logout - user: ${username:-unknown}, IP: $ip_address ($created) [EventNumber: $event_number] iLO SSH 로그아웃"
            else
                send_alert "BMC-ACCESS-005" "iLO SSH logout - user: ${username:-unknown} ($created) [EventNumber: $event_number] iLO SSH 로그아웃"
            fi
        fi
        return
    fi

    if is_rest_logout_event "$message_lower"; then
        local ip_address
        local username

        ip_address=$(extract_ip_address "$message")
        username=$(extract_logout_username "$message")

        if is_periodic_os_rest_noise "$message_lower" "$ip_address" "${username:-unknown}"; then
            log_message "Ignored periodic/local BMC REST logout event - user: ${username:-unknown}, IP: ${ip_address:-unknown}, EventNumber: $event_number"
        else
            if [ -n "$ip_address" ]; then
                send_alert "BMC-ACCESS-006" "iLO REST/iLOREST logout - user: ${username:-unknown}, IP: $ip_address ($created) [EventNumber: $event_number] iLO REST/iLOREST 로그아웃"
            else
                send_alert "BMC-ACCESS-006" "iLO REST/iLOREST logout - user: ${username:-unknown} ($created) [EventNumber: $event_number] iLO REST/iLOREST 로그아웃"
            fi
        fi
        return
    fi

    if echo "$message_lower" | grep -q "reset to factory defaults"; then
        send_alert "BMC-CONFIG-001" "iLO factory reset detected ($created) [EventNumber: $event_number]"
    fi
}

parse_ilorest_output() {
    local temp_log="$1"
    local last_event_number=$(get_last_event_number)
    local max_event_number=$last_event_number
    local new_entries_count=0
    local current_event_number=""
    local current_message=""
    local current_created=""
    local current_severity=""
    local in_entry=false

    log_message "Last processed EventNumber/RecordId: $last_event_number"

    process_current_entry() {
        if [ -n "$current_event_number" ] && [ -n "$current_message" ]; then
            if echo "$current_event_number" | grep -q "^[0-9]\+$"; then
                if [ "$current_event_number" -gt "$last_event_number" ]; then
                    analyze_event "$current_message" "$current_created" "$current_severity" "$current_event_number"
                    new_entries_count=$((new_entries_count + 1))

                    if [ "$current_event_number" -gt "$max_event_number" ]; then
                        max_event_number=$current_event_number
                    fi
                fi
            fi
        fi
    }

    local skip_header=true

    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$skip_header" = true ]; then
            if echo "$line" | grep -q "^@odata.context="; then
                skip_header=false
                in_entry=true
                current_event_number=""
                current_message=""
                current_created=""
                current_severity=""
                continue
            else
                continue
            fi
        fi

        if echo "$line" | grep -q "^@odata.context="; then
            if [ "$in_entry" = true ]; then
                process_current_entry
            fi

            current_event_number=""
            current_message=""
            current_created=""
            current_severity=""
            in_entry=true
            continue
        fi

        if [ -z "$line" ]; then
            if [ "$in_entry" = true ]; then
                process_current_entry
            fi
            in_entry=false
            continue
        fi

        if [ "$in_entry" = true ]; then
            local event_num=$(extract_field_value "$line" "EventNumber")
            if [ -n "$event_num" ]; then
                # EventNumber를 우선 사용한다.
                current_event_number="$event_num"
            fi

            local record_id=$(extract_field_value "$line" "RecordId")
            if [ -n "$record_id" ] && [ -z "$current_event_number" ]; then
                # EventNumber가 없는 서버는 RecordId를 fallback으로 사용한다.
                current_event_number="$record_id"
            fi

            local msg=$(extract_field_value "$line" "Message")
            if [ -n "$msg" ]; then
                current_message="$msg"
            fi

            local created=$(extract_field_value "$line" "Created")
            if [ -n "$created" ]; then
                current_created="$created"
            fi

            local severity=$(extract_field_value "$line" "Severity")
            if [ -n "$severity" ]; then
                current_severity="$severity"
            fi
        fi

    done < "$temp_log"

    # 마지막 엔트리 처리
    if [ "$in_entry" = true ]; then
        process_current_entry
    fi

    log_message "Processed new entry count: $new_entries_count"

    if [ "$max_event_number" -gt "$last_event_number" ]; then
        save_last_event_number "$max_event_number"
        log_message "Updated last processed EventNumber/RecordId: $last_event_number -> $max_event_number"
    else
        log_message "No new log entries"
    fi
}

analyze_ilo_logs() {
    local temp_log="${TEMP_DIR}/ilo_current_$$.log"
    local start_time=$(get_timestamp_ms)
    local ilorest_start_time
    local ilorest_end_time
    local parsing_start_time
    local parsing_end_time

    log_message "BMC log analysis started"

    # ilorest 명령어 실행 시간 측정
    ilorest_start_time=$(get_timestamp_ms)

    if ! run_ilorest serverlogs --selectlog=IEL > "$temp_log" 2>/dev/null; then
        ilorest_end_time=$(get_timestamp_ms)
        local ilorest_duration=$((ilorest_end_time - ilorest_start_time))

        log_performance "ilorest_command" "$ilorest_duration" "FAILED" "(timeout or error)"
        log_message "ERROR: ilorest command failed or timed out (${TIMEOUT_SECONDS}s)"
        check_ilo_communication_health "false"
        rm -f "$temp_log"
        return 1
    fi

    ilorest_end_time=$(get_timestamp_ms)
    local ilorest_duration=$((ilorest_end_time - ilorest_start_time))

    # 로그 파일 유효성 검사
    if [ ! -s "$temp_log" ]; then
        log_performance "ilorest_command" "$ilorest_duration" "FAILED" "(empty log)"
        log_message "ERROR: BMC log output is empty"
        check_ilo_communication_health "false"
        rm -f "$temp_log"
        return 1
    fi

    # 로그 형식 검증
    if ! grep -q "^@odata.context=" "$temp_log" 2>/dev/null; then
        log_performance "ilorest_command" "$ilorest_duration" "FAILED" "(invalid format)"
        log_message "ERROR: BMC log format is invalid"
        check_ilo_communication_health "false"
        rm -f "$temp_log"
        return 1
    fi

    local total_lines=$(wc -l < "$temp_log")
    local file_size=$(stat -c%s "$temp_log" 2>/dev/null || stat -f%z "$temp_log" 2>/dev/null || echo 0)
    local log_count=$(grep -c "^@odata.context=" "$temp_log" 2>/dev/null || echo "0")

    log_performance "ilorest_command" "$ilorest_duration" "SUCCESS" "(${log_count} logs, ${total_lines} lines, ${file_size} bytes)"
    log_message "BMC log file size: $log_count logs, $total_lines lines, $file_size bytes"

    # 로그 파싱 시간 측정
    parsing_start_time=$(get_timestamp_ms)

    if ! parse_ilorest_output "$temp_log"; then
        parsing_end_time=$(get_timestamp_ms)
        local parsing_duration=$((parsing_end_time - parsing_start_time))

        log_performance "log_parsing" "$parsing_duration" "FAILED" ""
        log_message "ERROR: failed while parsing BMC logs"
        check_ilo_communication_health "false"
        rm -f "$temp_log"
        return 1
    fi

    parsing_end_time=$(get_timestamp_ms)
    local parsing_duration=$((parsing_end_time - parsing_start_time))

    log_performance "log_parsing" "$parsing_duration" "SUCCESS" ""

    # 성공적으로 완료
    check_ilo_communication_health "true"

    local end_time=$(get_timestamp_ms)
    local total_duration=$((end_time - start_time))

    log_performance "total_analysis" "$total_duration" "SUCCESS" "(ilorest: $(format_duration $ilorest_duration), parsing: $(format_duration $parsing_duration))"
    log_message "BMC log analysis completed - total duration: $(format_duration $total_duration) (fetch: $(format_duration $ilorest_duration), parse: $(format_duration $parsing_duration))"

    rm -f "$temp_log"

    # 로그 정리 수행
    safe_cleanup_ilo_logs

    return 0
}

# 상태 표시 함수들
show_cleanup_config() {
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "=== Log cleanup configuration ==="
        echo "Cleanup enabled: $ENABLE_LOG_CLEANUP"
        echo "Minimum logs to keep: $MIN_LOGS_TO_KEEP"
        echo "Cleanup threshold: $MAX_LOGS_BEFORE_CLEANUP"
        echo "Backup before cleanup: $BACKUP_BEFORE_CLEANUP"
        echo "======================"
    fi
}

show_log_status() {
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "=== Log file status ==="

        for logfile in "$LOG_FILE" "$ALERT_LOG" "$PERF_LOG"; do
            if [ -f "$logfile" ]; then
                local size=$(stat -c%s "$logfile" 2>/dev/null || echo "0")
                local size_kb=$((size / 1024))

                echo "$(basename "$logfile"): ${size_kb}KB"

                # 백업 파일 개수 확인
                local logdir=$(dirname "$logfile")
                local logname=$(basename "$logfile")
                local backup_count=$(find "$logdir" -name "${logname}.*" -type f 2>/dev/null | wc -l)

                if [ "$backup_count" -gt 0 ]; then
                    echo "  Backup files: ${backup_count}"
                fi
            fi
        done

        echo "Rotation settings: $((MAX_LOG_SIZE / 1024))KB, retention ${LOG_RETENTION_DAYS} days, max ${MAX_LOG_BACKUPS} backups"
        echo "===================="
    fi
}

show_backup_status() {
    local backup_dir="${LOG_DIR}/${SCRIPT_NAME}_${MONITOR_TYPE}_backups"

    if [ "$DEBUG_MODE" = "true" ] && [ -d "$backup_dir" ]; then
        echo "=== Backup file status ==="

        local backup_count=$(find "$backup_dir" -name "${SCRIPT_NAME}_${MONITOR_TYPE}_logs_*.log" 2>/dev/null | wc -l)
        local backup_size_kb=$(du -sk "$backup_dir" 2>/dev/null | cut -f1)
        local backup_size_mb=$((backup_size_kb / 1024))

        echo "Backup file count: $backup_count"
        echo "Backup directory size: ${backup_size_mb}MB"
        echo "Retention policy: ${BACKUP_RETENTION_DAYS} days, max ${MAX_BACKUP_FILES} files, max ${MAX_BACKUP_SIZE_MB}MB"

        # 최근 5개 백업 파일 표시
        if [ "$backup_count" -gt 0 ]; then
            echo "Recent backup files:"
            find "$backup_dir" -name "${SCRIPT_NAME}_${MONITOR_TYPE}_logs_*.log" -type f -printf '%T@ %p\n' 2>/dev/null | \
            sort -nr | head -5 | \
            while read timestamp file; do
                local file_size=$(stat -c%s "$file" 2>/dev/null || echo "0")
                local file_size_kb=$((file_size / 1024))
                echo "  $(basename "$file") (${file_size_kb}KB)"
            done
        fi

        echo "======================"
    fi
}

print_system_status() {
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "=== BMC monitoring system status ==="
        echo "Last EventNumber/RecordId: $(get_last_event_number)"
        echo "Consecutive failure count: $(get_failure_count)"
        local last_success=$(get_last_success_time)
        if [ "$last_success" != "0" ]; then
            echo "Last success time: $(date -d @$last_success 2>/dev/null || echo 'Unknown')"
        else
            echo "Last success time: Unknown"
        fi
        echo "================================"
    fi
}

show_performance_summary() {
    if [ "$DEBUG_MODE" = "true" ] && [ -f "$PERF_LOG" ]; then
        echo "=== Recent performance statistics (last 10 runs) ==="

        # 최근 10개 ilorest 명령어 실행 시간
        echo "ilorest command execution time:"
        grep "ilorest_command.*SUCCESS" "$PERF_LOG" | tail -10 | while read line; do
            echo "  $line"
        done

        echo "================================"
    fi
}

# 수동 로그 정리 함수
clear_ilo_logs() {
    local log_type="${1:-IEL}"

    log_message "BMC $log_type log clear started"

    if run_ilorest serverlogs --selectlog="$log_type" --clearlog 2>/dev/null; then
        log_message "BMC $log_type log clear completed"
        send_alert "BMC-CLEANUP-002" "iLO $log_type log was manually cleared"

        # 상태 파일 초기화 (EventNumber 리셋)
        save_last_event_number "0"
        log_message "EventNumber state reset"

        return 0
    else
        log_message "ERROR: failed to clear iLO $log_type log"
        return 1
    fi
}

# 메인 함수
main() {
    case "$1" in
        "--debug")
            DEBUG_MODE="true"
            shift
            ;;
        "--no-cleanup")
            ENABLE_LOG_CLEANUP=false
            shift
            ;;
        "--force-cleanup")
            DEBUG_MODE="true"
            acquire_lock
            safe_cleanup_ilo_logs
            exit $?
            ;;
        "--clear-logs")
            DEBUG_MODE="true"
            acquire_lock
            clear_ilo_logs "${2:-IEL}"
            exit $?
            ;;
        "--clear-all")
            DEBUG_MODE="true"
            acquire_lock
            clear_ilo_logs "IEL"
            clear_ilo_logs "IML"
            exit $?
            ;;
    esac

    acquire_lock

    mkdir -p "$LOG_DIR" 2>/dev/null
    mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null
    mkdir -p "$(dirname "$HEALTH_STATE_FILE")" 2>/dev/null
    mkdir -p "$TEMP_DIR" 2>/dev/null
    chmod 700 "$TEMP_DIR" 2>/dev/null

    cleanup_stale_ilorest_tmp

    if ! command -v ilorest >/dev/null 2>&1; then
        log_message "ERROR: ilorest command not found"
        send_alert "BMC-SYS-001" "iLO monitoring system error - ilorest command not found"
        exit 1
    fi

    if ! command -v timeout >/dev/null 2>&1; then
        log_message "WARNING: timeout command not found. Timeout handling will be disabled."
        TIMEOUT_SECONDS=0
    fi

    local ilorest_version
    ilorest_version=$(run_ilorest -V 2>/dev/null | head -1)
    log_message "Using ilorest version: $ilorest_version"

    show_cleanup_config
    show_log_status
    show_backup_status
    print_system_status

    local last_event_number=$(get_last_event_number)
    if [ "$last_event_number" = "0" ]; then
        initialize_state
    else
        analyze_ilo_logs
    fi

    print_system_status
    show_performance_summary
    log_message "BMC log analysis completed"
}

main "$@"
