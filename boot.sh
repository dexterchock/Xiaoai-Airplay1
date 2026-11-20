#!/bin/sh
set -eu

APP_DIR="/data/xiaoai-airplay1"
AIRPLAY_BIN="${APP_DIR}/shairport-sync"
AIRPLAY_CFG="${APP_DIR}/shairport-sync.conf"
AIRPLAY_HOOK="${APP_DIR}/airplay-hook.sh"
AIRPLAY_DAEMON="${APP_DIR}/airplay-daemon.sh"
AIRPLAY_LOG="/tmp/shairport-sync.log"
PID_FILE="/tmp/xiaoai-airplay1.pid"
WAIT_SECONDS=60

if [ ! -x "${AIRPLAY_BIN}" ]; then
  echo "Error: executable not found at ${AIRPLAY_BIN}" >&2
  exit 1
fi

if [ ! -f "${AIRPLAY_CFG}" ]; then
  echo "Error: config not found at ${AIRPLAY_CFG}" >&2
  exit 1
fi

get_wlan_ip() {
  if command -v ip >/dev/null 2>&1; then
    ip -4 addr show dev wlan0 2>/dev/null | awk '/inet / {split($2, a, "/"); print a[1]; exit}'
  elif command -v ifconfig >/dev/null 2>&1; then
    ifconfig wlan0 2>/dev/null | awk '/inet addr:/ {sub(/.*inet addr:/, ""); print $1; exit}'
  fi
}

stop_pids() {
  pids="$1"
  [ -n "${pids}" ] || return 0
  kill -CONT ${pids} >/dev/null 2>&1 || true
  kill ${pids} >/dev/null 2>&1 || true
  w=0
  while [ "${w}" -lt 50 ]; do
    alive=""
    for p in ${pids}; do
      if kill -0 "${p}" 2>/dev/null; then
        alive="${alive} ${p}"
      fi
    done
    [ -z "${alive}" ] && return 0
    sleep 1
    w=$((w + 10))
  done
  kill -9 ${pids} >/dev/null 2>&1 || true
}

write_if_changed() {
  target="$1"
  mode="$2"
  tmp="/tmp/.xiaoai-script.$$"
  cat > "${tmp}"
  if [ ! -f "${target}" ] || ! cmp -s "${tmp}" "${target}"; then
    mv -f "${tmp}" "${target}"
    chmod "${mode}" "${target}"
  else
    rm -f "${tmp}"
  fi
}

# Wait for wlan0 IPv4 and Apple mDNSResponder socket (LAN-only safe)
i=0
while [ "${i}" -lt "${WAIT_SECONDS}" ]; do
  if [ -n "$(get_wlan_ip)" ] && [ -S /var/run/mdnsd ]; then
    break
  fi
  i=$((i + 1))
  sleep 1
done

# Stop previous supervisor, shairport-sync, and any legacy aplay pipeline
if [ -f "${PID_FILE}" ]; then
  OLD_SUP="$(cat "${PID_FILE}" 2>/dev/null || true)"
  case "${OLD_SUP}" in
    ''|*[!0-9]*) OLD_SUP="" ;;
  esac
  stop_pids "${OLD_SUP}"
  rm -f "${PID_FILE}"
fi

PIDS_DAEMON="$(ps -w | grep '[a]irplay-daemon.sh' | awk '{print $1}' || true)"
stop_pids "${PIDS_DAEMON}"

PIDS_AP="$(ps -w | grep '[s]hairport-sync' | awk '{print $1}' || true)"
stop_pids "${PIDS_AP}"

PIDS_APLAY="$(ps -w | grep '[a]play -q -D notify' | awk '{print $1}' || true)"
stop_pids "${PIDS_APLAY}"

# Ensure mipns-xiaomi is never left paused
PIDS_MI="$(pidof mipns-xiaomi 2>/dev/null || true)"
if [ -n "${PIDS_MI}" ]; then
  kill -CONT ${PIDS_MI} >/dev/null 2>&1 || true
fi

# Clean up obsolete files from older versions
rm -f "${APP_DIR}/volume-hook.sh" "${APP_DIR}/shairport.log" \
  /tmp/shairport-sync-metadata /tmp/airplay_pre_vol /tmp/airplay_last_vol

write_if_changed "${AIRPLAY_HOOK}" 0755 <<'HOOK'
#!/bin/sh
PIDS="$(pidof mipns-xiaomi 2>/dev/null || true)"

case "${1:-}" in
  start)
    mphelper pause >/dev/null 2>&1 || true
    [ -n "${PIDS}" ] && kill -STOP ${PIDS} >/dev/null 2>&1 || true
    ;;
  stop)
    [ -n "${PIDS}" ] && kill -CONT ${PIDS} >/dev/null 2>&1 || true
    ;;
esac
exit 0
HOOK

write_if_changed "${AIRPLAY_DAEMON}" 0755 <<'DAEMON'
#!/bin/sh
set -u

APP_DIR="/data/xiaoai-airplay1"
AIRPLAY_BIN="${APP_DIR}/shairport-sync"
AIRPLAY_CFG="${APP_DIR}/shairport-sync.conf"
AIRPLAY_HOOK="${APP_DIR}/airplay-hook.sh"
AIRPLAY_LOG="/tmp/shairport-sync.log"
PID_FILE="/tmp/xiaoai-airplay1.pid"
MAX_LOG_BYTES=262144

STOPPING=0
CHILD_PID=""
SLEEP_PID=""

for fd_path in /proc/$$/fd/*; do
  fd="${fd_path##*/}"
  case "${fd}" in
    0|1|2|'*') continue ;;
  esac
  target="$(readlink "${fd_path}" 2>/dev/null || true)"
  case "${target}" in
    pipe:*) eval "exec ${fd}>&-" 2>/dev/null || true ;;
  esac
done

echo $$ > "${PID_FILE}"

get_wlan_ip() {
  if command -v ip >/dev/null 2>&1; then
    ip -4 addr show dev wlan0 2>/dev/null | awk '/inet / {split($2, a, "/"); print a[1]; exit}'
  elif command -v ifconfig >/dev/null 2>&1; then
    ifconfig wlan0 2>/dev/null | awk '/inet addr:/ {sub(/.*inet addr:/, ""); print $1; exit}'
  fi
}

get_mdns_pid() {
  cat /var/run/mdnsd.pid 2>/dev/null || true
}

trim_log() {
  if [ -f "${AIRPLAY_LOG}" ]; then
    sz="$(wc -c < "${AIRPLAY_LOG}" 2>/dev/null || echo 0)"
    if [ "${sz}" -gt "${MAX_LOG_BYTES}" ]; then
      : > "${AIRPLAY_LOG}"
    fi
  fi
}

stop_child() {
  if [ -n "${CHILD_PID}" ] && kill -0 "${CHILD_PID}" 2>/dev/null; then
    kill "${CHILD_PID}" >/dev/null 2>&1 || true
    k=0
    while [ "${k}" -lt 5 ] && kill -0 "${CHILD_PID}" 2>/dev/null; do
      sleep 1
      k=$((k + 1))
    done
    kill -9 "${CHILD_PID}" >/dev/null 2>&1 || true
    wait "${CHILD_PID}" 2>/dev/null || true
  fi
  CHILD_PID=""
}

cleanup() {
  STOPPING=1
  if [ -n "${SLEEP_PID}" ]; then
    kill "${SLEEP_PID}" >/dev/null 2>&1 || true
    SLEEP_PID=""
  fi
  stop_child
  "${AIRPLAY_HOOK}" stop >/dev/null 2>&1 || true
  rm -f "${PID_FILE}"
  exit 0
}

trap cleanup INT TERM

cd "${APP_DIR}" || exit 1

while [ "${STOPPING}" -eq 0 ]; do
  trim_log
  LAST_IP="$(get_wlan_ip)"
  LAST_MDNS="$(get_mdns_pid)"

  MALLOC_ARENA_MAX=2 nice -n -15 "${AIRPLAY_BIN}" -c "${AIRPLAY_CFG}" </dev/null >/dev/null 2>>"${AIRPLAY_LOG}" &
  CHILD_PID=$!

  while [ "${STOPPING}" -eq 0 ] && kill -0 "${CHILD_PID}" 2>/dev/null; do
    sleep 5 &
    SLEEP_PID=$!
    wait "${SLEEP_PID}" 2>/dev/null || true
    SLEEP_PID=""
    [ "${STOPPING}" -eq 0 ] || break
    CUR_IP="$(get_wlan_ip)"
    CUR_MDNS="$(get_mdns_pid)"
    if [ -n "${CUR_IP}" ] && [ "${CUR_IP}" != "${LAST_IP}" ]; then
      stop_child
      break
    fi
    if [ -n "${CUR_MDNS}" ] && [ "${CUR_MDNS}" != "${LAST_MDNS}" ]; then
      stop_child
      break
    fi
  done

  wait "${CHILD_PID}" 2>/dev/null || true
  CHILD_PID=""
  "${AIRPLAY_HOOK}" stop >/dev/null 2>&1 || true

  if [ "${STOPPING}" -eq 0 ]; then
    sleep 2 &
    SLEEP_PID=$!
    wait "${SLEEP_PID}" 2>/dev/null || true
    SLEEP_PID=""
  fi
done
DAEMON

echo "Starting AirPlay 1 service..."
if command -v start-stop-daemon >/dev/null 2>&1; then
  start-stop-daemon -S -b -p "${PID_FILE}" -x "${AIRPLAY_DAEMON}"
else
  ( "${AIRPLAY_DAEMON}" </dev/null >/dev/null 2>&1 ) &
fi

started=0
i=0
while [ "${i}" -lt 5 ]; do
  if ps -w | grep -q '[s]hairport-sync'; then
    started=1
    break
  fi
  sleep 1
  i=$((i + 1))
done

if [ "${started}" -ne 1 ]; then
  echo "Error: AirPlay failed to start, check ${AIRPLAY_LOG}" >&2
  exit 1
fi

echo "AirPlay 1 started. Log: ${AIRPLAY_LOG}"
