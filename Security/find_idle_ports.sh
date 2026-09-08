#!/bin/bash
# disable_unplugged_ports.sh
# 목적: 케이블 미연결(링크 미감지) 물리 NIC을 찾아 down하고,
#       NM 관리면 autoconnect=no, 레거시면 ONBOOT=no로 설정.
# 기본은 DRY-RUN. --apply 로 실제 적용.
# 옵션: --verbose, --link-only (링크 미감지만으로 대상 선정)

set -u

APPLY=0
VERBOSE=0
LINK_ONLY=0

log(){ echo "[*] $*"; }
vlog(){ [ "$VERBOSE" -eq 1 ] && echo "[v] $*"; }
warn(){ echo "[!] $*" >&2; }
die(){ echo "[x] $*" >&2; exit 1; }

usage(){
  cat <<EOF
Usage: $0 [--apply] [--verbose] [--link-only] [-h|--help]
  --apply       실제 적용(기본: DRY-RUN)
  --verbose     상세 로그
  --link-only   링크 미감지(carrier=0)만으로 대상 선정(주소/라우트 검사를 생략)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1;;
    --verbose) VERBOSE=1;;
    --link-only) LINK_ONLY=1;;
    -h|--help) usage; exit 0;;
    *) warn "Unknown option: $1"; usage; exit 1;;
  esac
  shift
done

[ "$APPLY" -eq 1 ] && [ "$(id -u)" -ne 0 ] && die "root 권한이 필요합니다."

# 도구 체크
HAVE_IP=0; command -v ip >/dev/null 2>&1 && HAVE_IP=1
HAVE_IFCONFIG=0; command -v ifconfig >/dev/null 2>&1 && HAVE_IFCONFIG=1
HAVE_ETHTOOL=0; command -v ethtool >/dev/null 2>&1 && HAVE_ETHTOOL=1
HAVE_NMCLI=0; command -v nmcli >/dev/null 2>&1 && HAVE_NMCLI=1

if [ $HAVE_IP -eq 0 ] && [ $HAVE_IFCONFIG -eq 0 ]; then
  die "ip 또는 ifconfig 가 필요합니다."
fi

# 공통 기능
is_physical(){ [ -e "/sys/class/net/$1/device" ]; }
is_loopback(){ [ "$1" = "lo" ]; }
has_master(){ [ -e "/sys/class/net/$1/master" ]; }

is_admin_up(){
  local dev="$1"
  if [ $HAVE_IP -eq 1 ]; then
    ip -o link show dev "$dev" 2>/dev/null | grep -qw "UP"
  else
    ifconfig "$dev" 2>/dev/null | grep -q "UP"
  fi
}

operstate(){
  local dev="$1"
  if [ -r "/sys/class/net/$dev/operstate" ]; then
    cat "/sys/class/net/$dev/operstate" 2>/dev/null
  else
    echo "unknown"
  fi
}

carrier(){
  local dev="$1"
  if [ -r "/sys/class/net/$dev/carrier" ]; then
    cat "/sys/class/net/$dev/carrier" 2>/dev/null
  else
    if [ $HAVE_ETHTOOL -eq 1 ]; then
      ethtool "$dev" 2>/dev/null | grep -qi "Link detected: yes" && echo 1 || echo 0
    else
      # 정보 없으면 안전을 위해 링크 존재(1)로 간주 -> 대상에서 제외
      echo 1
    fi
  fi
}

has_ipaddr(){
  local dev="$1"
  if [ $HAVE_IP -eq 1 ]; then
    ip -4 addr show dev "$dev" 2>/dev/null \
      | awk '/inet /{print $2}' \
      | awk -F/ '{print $1}' \
      | grep -Ev '^(127\.|169\.254\.)' \
      | grep -q .
    return
  else
    ifconfig "$dev" 2>/dev/null | awk '/inet /{print $2}' | grep -vq '^127\.' && return 0
  fi
  return 1
}

has_routes(){
  local dev="$1"
  if [ $HAVE_IP -eq 1 ]; then
    ip route show dev "$dev" 2>/dev/null | grep -q .
    return
  else
    command -v route >/dev/null 2>&1 || return 1
    route -n 2>/dev/null | awk -v D="$dev" '$8==D{c++} END{exit c?0:1}'
    return
  fi
}

# NM 프로파일 autoconnect=no 설정(이미 no면 보고만)
nm_autoconnect_off(){
  local dev="$1" targets="" cur=""
  if [ $HAVE_NMCLI -ne 1 ]; then
    vlog "$dev: nmcli 없음"
    return 2
  fi
  # 활성 연결/UUID
  if nmcli -g GENERAL.CONNECTION device show "$dev" >/dev/null 2>&1; then
    targets=$(nmcli -g GENERAL.CONNECTION device show "$dev" 2>/dev/null | head -n1)
    [ -n "$targets" ] && [ "$targets" != "--" ] && [ "$targets" != "(none)" ] || targets=""
  fi
  # interface-name
  if [ -z "$targets" ] && nmcli -t -f NAME,connection.interface-name connection show >/dev/null 2>&1; then
    targets=$(nmcli -t -f NAME,connection.interface-name connection show | awk -F: -v D="$dev" '$2==D{print $1}')
  fi
  # DEVICE
  if [ -z "$targets" ] && nmcli -t -f NAME,DEVICE connection show >/dev/null 2>&1; then
    targets=$(nmcli -t -f NAME,DEVICE connection show | awk -F: -v D="$dev" '$2==D{print $1}')
  fi
  # fallback: 프로파일 이름 == dev
  if [ -z "$targets" ] && nmcli connection show "$dev" >/dev/null 2>&1; then
    targets="$dev"
  fi

  if [ -z "$targets" ]; then
    log "참고: $dev 에 매핑된 NM 연결 프로파일을 찾지 못했습니다(NM unmanaged 가능)."
    return 2
  fi

  local c
  for c in $targets; do
    cur=$(nmcli -g connection.autoconnect connection show "$c" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if [ "$APPLY" -eq 1 ]; then
      if [ "$cur" = "no" ]; then
        vlog "$dev: \"$c\" autoconnect 이미 no"
      else
        if nmcli connection modify "$c" connection.autoconnect no; then
          log "$dev: \"$c\" autoconnect=no 적용"
        else
          warn "$dev: \"$c\" autoconnect=no 적용 실패"
        fi
      fi
    else
      if [ "$cur" = "no" ]; then
        log "DRY-RUN: $dev \"$c\" autoconnect 현재=no -> 변경 없음"
      else
        log "DRY-RUN: $dev \"$c\" autoconnect 현재=${cur:-<unset>} -> 예정: no로 변경"
      fi
    fi
  done
  return 0
}

# 레거시 ifcfg의 ONBOOT/NM_CONTROLLED=no (상태 보고 포함)
get_ifcfg_value(){
  local file="$1" key="$2"
  awk -F= -v K="$key" '
    $0 !~ /^[[:space:]]*#/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
      if ($1 == K) {
        val=$2
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        gsub(/^"|"$/, "", val); gsub(/^'\''|'\''$/, "", val)
        print val; exit
      }
    }
  ' "$file" 2>/dev/null
}

legacy_onboot_off(){
  local dev="$1" ifcfg="/etc/sysconfig/network-scripts/ifcfg-$dev" ts
  ts="$(date +%Y%m%d%H%M%S)"
  if [ ! -f "$ifcfg" ]; then
    vlog "$dev: ifcfg 없음 ($ifcfg)"
    return 0
  fi
  local cur_onboot cur_nmctrl
  cur_onboot="$(get_ifcfg_value "$ifcfg" "ONBOOT" | tr '[:upper:]' '[:lower:]')"
  cur_nmctrl="$(get_ifcfg_value "$ifcfg" "NM_CONTROLLED" | tr '[:upper:]' '[:lower:]')"

  if [ "$APPLY" -eq 1 ]; then
    cp -p "$ifcfg" "${ifcfg}.bak.$ts" 2>/dev/null
    # ONBOOT
    if grep -Eq '^[[:space:]]*ONBOOT[[:space:]]*=' "$ifcfg"; then
      [ "$cur_onboot" = "no" ] || sed -i -E 's/^[[:space:]]*ONBOOT[[:space:]]*=.*/ONBOOT=no/' "$ifcfg"
      [ "$cur_onboot" = "no" ] && log "$dev: ONBOOT=no (변경 없음)" || log "$dev: ONBOOT=$(echo ${cur_onboot:-<unset>}) -> no (적용)"
    else
      echo 'ONBOOT=no' >> "$ifcfg"; log "$dev: ONBOOT 미설정 -> ONBOOT=no 추가(적용)"
    fi
    # NM_CONTROLLED
    if grep -Eq '^[[:space:]]*NM_CONTROLLED[[:space:]]*=' "$ifcfg"; then
      [ "$cur_nmctrl" = "no" ] || sed -i -E 's/^[[:space:]]*NM_CONTROLLED[[:space:]]*=.*/NM_CONTROLLED=no/' "$ifcfg"
      [ "$cur_nmctrl" = "no" ] && log "$dev: NM_CONTROLLED=no (변경 없음)" || log "$dev: NM_CONTROLLED=$(echo ${cur_nmctrl:-<unset>}) -> no (적용)"
    else
      echo 'NM_CONTROLLED=no' >> "$ifcfg"; log "$dev: NM_CONTROLLED 미설정 -> NM_CONTROLLED=no 추가(적용)"
    fi
    log "$dev: ifcfg 백업: ${ifcfg}.bak.$ts"
  else
    if grep -Eq '^[[:space:]]*ONBOOT[[:space:]]*=' "$ifcfg"; then
      [ "$cur_onboot" = "no" ] && log "DRY-RUN: $dev ONBOOT 현재=no -> 변경 없음" || log "DRY-RUN: $dev ONBOOT 현재=$(echo ${cur_onboot:-<unset>}) -> 예정: no로 변경"
    else
      log "DRY-RUN: $dev ONBOOT 현재=미설정 -> 예정: ONBOOT=no 추가"
    fi
    if grep -Eq '^[[:space:]]*NM_CONTROLLED[[:space:]]*=' "$ifcfg"; then
      [ "$cur_nmctrl" = "no" ] && log "DRY-RUN: $dev NM_CONTROLLED 현재=no -> 변경 없음" || log "DRY-RUN: $dev NM_CONTROLLED 현재=$(echo ${cur_nmctrl:-<unset>}) -> 예정: no로 변경"
    else
      log "DRY-RUN: $dev NM_CONTROLLED 현재=미설정 -> 예정: NM_CONTROLLED=no 추가"
    fi
    log "DRY-RUN: 적용 시 백업 예정: ${ifcfg}.bak.$ts"
  fi
}

# 인터페이스 down 단계(드라이런 로그 포함)
down_interface() {
  local dev="$1"
  local have_ifdown=1; command -v ifdown >/dev/null 2>&1 || have_ifdown=0

  if [ "$APPLY" -eq 1 ]; then
    # 1) NM이 실제로 연결 잡고 있을 때만 disconnect
    if command -v nmcli >/dev/null 2>&1; then
      if nm_is_connected "$dev"; then
        nmcli device disconnect "$dev" >/dev/null 2>&1 || true
        log "$dev: nmcli disconnect 적용"
      else
        log "$dev: NM 상태=disconnected/unmanaged -> disconnect 생략"
      fi
    fi

    # 2) admin이 UP일 때만 down 수행
    if is_admin_up "$dev"; then
      if [ $have_ifdown -eq 1 ]; then
        ifdown "$dev" >/dev/null 2>&1 || ip link set dev "$dev" down >/dev/null 2>&1
      else
        ip link set dev "$dev" down >/dev/null 2>&1
      fi
      log "$dev: 인터페이스 down 적용"
    else
      log "$dev: 이미 admin DOWN -> down 생략"
    fi
  else
    # DRY-RUN: 예정 경로 명확히 표시
    if command -v nmcli >/dev/null 2>&1; then
      if nm_is_connected "$dev"; then
        log "DRY-RUN: nmcli device disconnect $dev"
      else
        log "DRY-RUN: nmcli device disconnect 생략(이미 disconnected/unmanaged)"
      fi
    fi
    if is_admin_up "$dev"; then
      if command -v ifdown >/dev/null 2>&1; then
        log "DRY-RUN: ifdown $dev"
        log "DRY-RUN: (ifdown 실패 시) ip link set dev $dev down"
      else
        log "DRY-RUN: ip link set dev $dev down"
      fi
    else
      log "DRY-RUN: 인터페이스가 이미 admin DOWN -> down 생략"
    fi
  fi
}



# 후보 판정: 링크 미감지(+안전 조건)
is_unplugged_candidate(){
  local dev="$1"
  is_loopback "$dev" && { vlog "$dev: loopback 제외"; return 1; }
  is_physical "$dev" || { vlog "$dev: 물리 아님 제외"; return 1; }
  has_master "$dev" && { vlog "$dev: master 종속 제외"; return 1; }

  local car op
  car="$(carrier "$dev")"
  op="$(operstate "$dev")"
  vlog "$dev: carrier=$car operstate=$op"

  # 링크 감지 실패해야 후보
  [ "$car" = "0" ] || { vlog "$dev: 링크 감지됨(carrier=1) -> 제외"; return 1; }

  if [ "$LINK_ONLY" -eq 1 ]; then
    return 0
  fi

  # 추가 안전 조건: IPv4 주소/라우트 없어야
  has_ipaddr "$dev" && { vlog "$dev: IPv4 주소 존재 -> 제외"; return 1; }
  has_routes "$dev" && { vlog "$dev: 라우트 존재 -> 제외"; return 1; }

  return 0
}

# NM이 연결 상태인가?
nm_is_connected() {
  local dev="$1"
  command -v nmcli >/dev/null 2>&1 || return 1
  # connected|connecting|activated 등 상태만 true
  nmcli -g GENERAL.STATE device show "$dev" 2>/dev/null \
    | grep -Eiq 'connected|connecting|activated'
}

# admin UP 여부
is_admin_up() {
  ip -o link show dev "$1" 2>/dev/null | grep -qw "UP"
}

main(){
  local dev any=0
  for dev in $(ls -1 /sys/class/net 2>/dev/null); do
    case "$dev" in
      lo|bond*|team*|br*|virbr*|vnet*|docker*|flannel*|tun*|tap*|veth* )
        vlog "$dev: 네이밍 제외"; continue;;
    esac

    if is_unplugged_candidate "$dev"; then
      any=1
      # 상태 리포트
      local admin="DOWN"; is_admin_up "$dev" && admin="UP"
      log "대상(링크 미감지): $dev"
      log "  상태: admin=$admin, operstate=$(operstate "$dev"), carrier=$(carrier "$dev")"
      if [ $LINK_ONLY -eq 0 ]; then
        if has_ipaddr "$dev"; then log "  IPv4: 존재(주의)"; else log "  IPv4: 없음"; fi
        if has_routes "$dev"; then log "  route: 존재(주의)"; else log "  route: 없음"; fi
      fi

      # down 처리
      down_interface "$dev"

      # NM 관리: autoconnect=no
      if [ $HAVE_NMCLI -eq 1 ]; then
        nm_autoconnect_off "$dev" || true
      fi

      # 레거시/비관리 대비: ONBOOT/NM_CONTROLLED=no
      legacy_onboot_off "$dev"
    fi
  done

  if [ $any -eq 0 ]; then
    log "대상 포트 없음(링크가 모두 감지되었거나 안전 조건을 만족하지 않음)."
  fi

  [ "$APPLY" -eq 1 ] && log "적용 완료" || log "드라이런 완료(변경 없음)"
}

main
